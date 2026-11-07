import { and, asc, desc, eq, inArray, or } from 'drizzle-orm';
import { ulid } from 'ulid';
import { db } from '../db/index.js';
import {
  businesses,
  orderItems,
  orders,
  payments,
  products,
  stockMovements,
  webhookEvents,
  type BusinessRow,
  type OrderItemRow,
  type OrderRow,
  type OrderStatus,
  type PaymentRow,
  type PrepType,
} from '../db/schema.js';
import { AppError } from '../lib/errors.js';
import type { PeyClient } from '../lib/pey.js';

export const ORDER_EXPIRY_SECONDS = 15 * 60;
export const CODI_QR_EXPIRATION_SECONDS = 600;

export interface OrderItemInput {
  productId: string;
  qty: number;
}

export interface CreateOrderInput {
  businessId: string;
  items: OrderItemInput[];
  note?: string | null;
}

export interface OrderWithDetails extends OrderRow {
  items: OrderItemRow[];
  payment: PaymentRow | null;
}

export interface PayOrderResult {
  qrString: string;
  codiQrId: string;
  expiresAt: number;
  amountCents: number;
}

export function deriveNumRef(orderId: string): string {
  let hash = 0;
  for (let i = 0; i < orderId.length; i++) {
    hash = (hash * 31 + orderId.charCodeAt(i)) >>> 0;
  }
  const sevenDigit = 1000000 + (hash % 9000000);
  return String(sevenDigit);
}

export function isValidOwnerStatusTransition(
  current: OrderStatus,
  next: OrderStatus,
  prepType: PrepType
): boolean {
  if (current === 'pending_payment') {
    return next === 'cancelled';
  }
  if (current === 'paid') {
    if (prepType === 'made_to_order') {
      return next === 'preparing' || next === 'delivered' || next === 'cancelled';
    }
    return next === 'delivered' || next === 'cancelled';
  }
  if (current === 'preparing') {
    return next === 'ready';
  }
  if (current === 'ready') {
    return next === 'delivered';
  }
  return false;
}

async function expireOrderIfStale(
  order: OrderRow,
  nowSec = Math.floor(Date.now() / 1000)
): Promise<OrderRow> {
  if (order.status === 'pending_payment' && nowSec - order.createdAt >= ORDER_EXPIRY_SECONDS) {
    await db
      .update(orders)
      .set({ status: 'expired' })
      .where(and(eq(orders.id, order.id), eq(orders.status, 'pending_payment')));
    await db
      .update(payments)
      .set({ status: 'expired' })
      .where(and(eq(payments.orderId, order.id), eq(payments.status, 'pending')));
    return { ...order, status: 'expired' };
  }
  return order;
}

async function hydrateOrders(orderRows: OrderRow[]): Promise<OrderWithDetails[]> {
  if (orderRows.length === 0) {
    return [];
  }

  const orderIds = orderRows.map((o) => o.id);

  const [allItems, allPayments] = await Promise.all([
    db
      .select()
      .from(orderItems)
      .where(inArray(orderItems.orderId, orderIds)),
    db
      .select()
      .from(payments)
      .where(inArray(payments.orderId, orderIds))
      .orderBy(desc(payments.createdAt), desc(payments.id)),
  ]);

  const itemsByOrder = new Map<string, OrderItemRow[]>();
  for (const item of allItems) {
    const list = itemsByOrder.get(item.orderId) ?? [];
    list.push(item);
    itemsByOrder.set(item.orderId, list);
  }

  const latestPaymentByOrder = new Map<string, PaymentRow>();
  for (const payment of allPayments) {
    if (!latestPaymentByOrder.has(payment.orderId)) {
      latestPaymentByOrder.set(payment.orderId, payment);
    }
  }

  return orderRows.map((order) => ({
    ...order,
    items: itemsByOrder.get(order.id) ?? [],
    payment: latestPaymentByOrder.get(order.id) ?? null,
  }));
}

async function getOrderAndBusinessWithAccess(
  userId: string,
  orderId: string
): Promise<{
  order: OrderRow;
  business: BusinessRow;
  isOwner: boolean;
  isCustomer: boolean;
}> {
  const [order] = await db.select().from(orders).where(eq(orders.id, orderId)).limit(1);
  if (!order) {
    throw new AppError(404, 'ORDER_NOT_FOUND', 'Order not found');
  }

  const [business] = await db
    .select()
    .from(businesses)
    .where(eq(businesses.id, order.businessId))
    .limit(1);

  if (!business) {
    throw new AppError(404, 'ORDER_NOT_FOUND', 'Order business not found');
  }

  const isOwner = business.ownerId === userId;
  const isCustomer = order.customerId !== null && order.customerId === userId;

  if (!isOwner && !isCustomer) {
    throw new AppError(404, 'ORDER_NOT_FOUND', 'Order not found');
  }

  const freshOrder = await expireOrderIfStale(order);

  return {
    order: freshOrder,
    business,
    isOwner,
    isCustomer,
  };
}

export async function createOrder(
  userId: string,
  input: CreateOrderInput
): Promise<OrderWithDetails> {
  const [business] = await db
    .select()
    .from(businesses)
    .where(and(eq(businesses.id, input.businessId), eq(businesses.active, true)))
    .limit(1);

  if (!business) {
    throw new AppError(404, 'BUSINESS_NOT_FOUND', 'Business not found');
  }

  const uniqueProductIds = Array.from(new Set(input.items.map((i) => i.productId)));
  const productRows = await db
    .select()
    .from(products)
    .where(
      and(
        eq(products.businessId, business.id),
        eq(products.active, true),
        inArray(products.id, uniqueProductIds)
      )
    );

  if (productRows.length !== uniqueProductIds.length) {
    throw new AppError(
      404,
      'PRODUCT_NOT_FOUND',
      'One or more products do not exist or are inactive for this business'
    );
  }

  const productById = new Map(productRows.map((p) => [p.id, p]));

  const requestedQtyByProduct = new Map<string, number>();
  for (const item of input.items) {
    requestedQtyByProduct.set(
      item.productId,
      (requestedQtyByProduct.get(item.productId) ?? 0) + item.qty
    );
  }

  for (const [productId, totalQty] of requestedQtyByProduct.entries()) {
    const product = productById.get(productId)!;
    if (product.trackStock && totalQty > product.stock) {
      throw new AppError(
        409,
        'INSUFFICIENT_STOCK',
        `Insufficient stock for product "${product.name}"`
      );
    }
  }

  const now = Math.floor(Date.now() / 1000);
  const orderId = ulid();
  const customerId = business.ownerId === userId ? null : userId;

  let totalCents = 0;
  const itemRows: OrderItemRow[] = input.items.map((item) => {
    const product = productById.get(item.productId)!;
    totalCents += product.priceCents * item.qty;
    return {
      id: ulid(),
      orderId,
      productId: product.id,
      name: product.name,
      priceCents: product.priceCents,
      qty: item.qty,
    };
  });

  const orderRow: OrderRow = {
    id: orderId,
    businessId: business.id,
    customerId,
    status: 'pending_payment',
    totalCents,
    note: input.note ?? null,
    createdAt: now,
    paidAt: null,
  };

  await db.transaction(async (tx) => {
    await tx.insert(orders).values(orderRow);
    await tx.insert(orderItems).values(itemRows);
  });

  return {
    ...orderRow,
    items: itemRows,
    payment: null,
  };
}

export async function getOrderForUser(
  userId: string,
  orderId: string
): Promise<OrderWithDetails> {
  const { order } = await getOrderAndBusinessWithAccess(userId, orderId);
  const [hydrated] = await hydrateOrders([order]);
  return hydrated!;
}

export async function listOrdersForUser(
  userId: string,
  filters: {
    role?: 'customer' | 'business';
    status?: OrderStatus;
  }
): Promise<OrderWithDetails[]> {
  const [userBusiness] = await db
    .select()
    .from(businesses)
    .where(eq(businesses.ownerId, userId))
    .limit(1);

  let candidateOrders: OrderRow[];

  if (filters.role === 'customer') {
    candidateOrders = await db
      .select()
      .from(orders)
      .where(eq(orders.customerId, userId))
      .orderBy(desc(orders.createdAt), desc(orders.id));
  } else if (filters.role === 'business') {
    if (!userBusiness) {
      return [];
    }
    candidateOrders = await db
      .select()
      .from(orders)
      .where(eq(orders.businessId, userBusiness.id))
      .orderBy(desc(orders.createdAt), desc(orders.id));
  } else {
    const condition = userBusiness
      ? or(eq(orders.customerId, userId), eq(orders.businessId, userBusiness.id))!
      : eq(orders.customerId, userId);
    candidateOrders = await db
      .select()
      .from(orders)
      .where(condition)
      .orderBy(desc(orders.createdAt), desc(orders.id));
  }

  const now = Math.floor(Date.now() / 1000);
  const refreshed: OrderRow[] = [];
  for (const order of candidateOrders) {
    refreshed.push(await expireOrderIfStale(order, now));
  }

  const filtered = filters.status
    ? refreshed.filter((o) => o.status === filters.status)
    : refreshed;

  return hydrateOrders(filtered);
}

export async function updateOrderStatus(
  userId: string,
  orderId: string,
  nextStatus: OrderStatus
): Promise<OrderWithDetails> {
  const { order, business, isOwner } = await getOrderAndBusinessWithAccess(userId, orderId);

  if (!isOwner) {
    throw new AppError(403, 'FORBIDDEN', 'Only the business owner may update order status');
  }

  if (!isValidOwnerStatusTransition(order.status, nextStatus, business.prepType)) {
    throw new AppError(
      409,
      'INVALID_TRANSITION',
      `Invalid status transition from ${order.status} to ${nextStatus}`
    );
  }

  const now = Math.floor(Date.now() / 1000);

  await db.transaction(async (tx) => {
    await tx.update(orders).set({ status: nextStatus }).where(eq(orders.id, order.id));

    if (order.status === 'paid' && nextStatus === 'cancelled') {
      const items = await tx
        .select()
        .from(orderItems)
        .where(eq(orderItems.orderId, order.id));

      for (const item of items) {
        const [product] = await tx
          .select()
          .from(products)
          .where(eq(products.id, item.productId))
          .limit(1);

        if (product && product.trackStock) {
          const newStock = product.stock + item.qty;
          await tx
            .update(products)
            .set({ stock: newStock })
            .where(eq(products.id, product.id));

          await tx.insert(stockMovements).values({
            id: ulid(),
            productId: product.id,
            delta: item.qty,
            reason: 'order_cancelled',
            createdAt: now,
          });
        }
      }
    }
  });

  const updatedOrder: OrderRow = {
    ...order,
    status: nextStatus,
  };

  const [hydrated] = await hydrateOrders([updatedOrder]);
  return hydrated!;
}

export async function payOrder(
  userId: string,
  orderId: string,
  pey: PeyClient
): Promise<PayOrderResult> {
  const { order, business } = await getOrderAndBusinessWithAccess(userId, orderId);

  if (order.status !== 'pending_payment') {
    throw new AppError(409, 'INVALID_TRANSITION', 'Order is not pending payment');
  }

  const now = Math.floor(Date.now() / 1000);

  const existingPayments = await db
    .select()
    .from(payments)
    .where(and(eq(payments.orderId, order.id), eq(payments.status, 'pending')))
    .orderBy(desc(payments.createdAt), desc(payments.id));

  for (const existing of existingPayments) {
    const expiresAt = existing.expiresAt ?? existing.createdAt + CODI_QR_EXPIRATION_SECONDS;
    if (existing.codiQrId && existing.qrString && expiresAt > now) {
      return {
        qrString: existing.qrString,
        codiQrId: existing.codiQrId,
        expiresAt,
        amountCents: existing.amountCents,
      };
    }
  }

  const bankAccountId =
    business.codiStatus === 'ACTIVE' && business.peyBankAccountId
      ? business.peyBankAccountId
      : undefined;

  const qr = await pey.createCodiQr({
    amountCents: order.totalCents,
    concept: `Pedido ${order.id.slice(-6)}`,
    numRef: deriveNumRef(order.id),
    expirationSec: CODI_QR_EXPIRATION_SECONDS,
    ...(bankAccountId ? { bankAccountId } : {}),
    metadata: {
      orderId: order.id,
      businessId: order.businessId,
    },
  });

  const createdAt = Math.floor(Date.now() / 1000);
  const expiresAt = createdAt + CODI_QR_EXPIRATION_SECONDS;

  await db.insert(payments).values({
    id: ulid(),
    orderId: order.id,
    codiQrId: qr.id,
    qrString: qr.qrString,
    expiresAt,
    transactionId: null,
    status: 'pending',
    amountCents: order.totalCents,
    createdAt,
  });

  return {
    qrString: qr.qrString,
    codiQrId: qr.id,
    expiresAt,
    amountCents: order.totalCents,
  };
}

type DbTx = Parameters<Parameters<typeof db.transaction>[0]>[0];

export async function markOrderPaidInTx(
  tx: DbTx,
  params: {
    orderId: string;
    paymentId?: string;
    transactionId?: string | null;
    now?: number;
  }
): Promise<{ order: OrderRow | null; alreadyPaid: boolean }> {
  const now = params.now ?? Math.floor(Date.now() / 1000);

  const [order] = await tx
    .select()
    .from(orders)
    .where(eq(orders.id, params.orderId))
    .limit(1);

  if (!order) {
    return { order: null, alreadyPaid: false };
  }

  if (
    order.status === 'paid' ||
    order.status === 'preparing' ||
    order.status === 'ready' ||
    order.status === 'delivered'
  ) {
    return { order, alreadyPaid: true };
  }

  if (order.status !== 'pending_payment') {
    return { order, alreadyPaid: false };
  }

  let targetPaymentId = params.paymentId;
  if (!targetPaymentId) {
    const [latestPayment] = await tx
      .select()
      .from(payments)
      .where(eq(payments.orderId, order.id))
      .orderBy(desc(payments.createdAt), desc(payments.id))
      .limit(1);
    targetPaymentId = latestPayment?.id;
  }

  if (targetPaymentId) {
    await tx
      .update(payments)
      .set({
        status: 'paid',
        ...(params.transactionId !== undefined ? { transactionId: params.transactionId } : {}),
      })
      .where(eq(payments.id, targetPaymentId));
  } else {
    await tx.insert(payments).values({
      id: ulid(),
      orderId: order.id,
      codiQrId: null,
      qrString: null,
      expiresAt: null,
      transactionId: params.transactionId ?? `sim_${order.id}`,
      status: 'paid',
      amountCents: order.totalCents,
      createdAt: now,
    });
  }

  await tx
    .update(orders)
    .set({
      status: 'paid',
      paidAt: now,
    })
    .where(eq(orders.id, order.id));

  const items = await tx
    .select()
    .from(orderItems)
    .where(eq(orderItems.orderId, order.id))
    .orderBy(asc(orderItems.id));

  for (const item of items) {
    const [product] = await tx
      .select()
      .from(products)
      .where(eq(products.id, item.productId))
      .limit(1);

    if (product && product.trackStock) {
      const newStock = Math.max(0, product.stock - item.qty);
      await tx
        .update(products)
        .set({ stock: newStock })
        .where(eq(products.id, product.id));

      await tx.insert(stockMovements).values({
        id: ulid(),
        productId: product.id,
        delta: -item.qty,
        reason: 'sale',
        createdAt: now,
      });
    }
  }

  return {
    order: {
      ...order,
      status: 'paid',
      paidAt: now,
    },
    alreadyPaid: false,
  };
}

export async function simulateOrderPaid(orderId: string): Promise<OrderWithDetails> {
  const now = Math.floor(Date.now() / 1000);

  const result = await db.transaction(async (tx) => {
    return markOrderPaidInTx(tx, {
      orderId,
      transactionId: `sim_${orderId}`,
      now,
    });
  });

  if (!result.order) {
    throw new AppError(404, 'ORDER_NOT_FOUND', 'Order not found');
  }

  const [hydrated] = await hydrateOrders([result.order]);
  return hydrated!;
}

export async function processPeyWebhookEvent(
  webhookId: string,
  payload: Record<string, unknown>
): Promise<{ ok: true; duplicate?: true }> {
  const now = Math.floor(Date.now() / 1000);

  return db.transaction(async (tx) => {
    const [existingEvent] = await tx
      .select()
      .from(webhookEvents)
      .where(eq(webhookEvents.id, webhookId))
      .limit(1);

    if (existingEvent) {
      return { ok: true, duplicate: true };
    }

    await tx.insert(webhookEvents).values({
      id: webhookId,
      receivedAt: now,
    });

    const eventType = typeof payload.type === 'string' ? payload.type : '';
    const dataObj =
      payload.data && typeof payload.data === 'object'
        ? { ...payload, ...(payload.data as Record<string, unknown>) }
        : payload;

    if (eventType === 'codi.qr.payment_received') {
      const codiQrId =
        typeof dataObj.codiQrId === 'string'
          ? dataObj.codiQrId
          : typeof dataObj.id === 'string'
            ? dataObj.id
            : undefined;

      const transactionId =
        typeof dataObj.transactionId === 'string' ? dataObj.transactionId : null;

      const metadata =
        dataObj.metadata && typeof dataObj.metadata === 'object'
          ? (dataObj.metadata as Record<string, unknown>)
          : undefined;
      const externalMetadata =
        metadata?.externalMetadata && typeof metadata.externalMetadata === 'object'
          ? (metadata.externalMetadata as Record<string, unknown>)
          : undefined;

      const fallbackOrderId =
        typeof externalMetadata?.orderId === 'string'
          ? externalMetadata.orderId
          : typeof metadata?.orderId === 'string'
            ? metadata.orderId
            : undefined;

      let matchedPayment: PaymentRow | undefined;
      if (codiQrId) {
        const [found] = await tx
          .select()
          .from(payments)
          .where(eq(payments.codiQrId, codiQrId))
          .limit(1);
        matchedPayment = found;
      }

      const targetOrderId = matchedPayment?.orderId ?? fallbackOrderId;
      if (!targetOrderId) {
        console.warn('Webhook codi.qr.payment_received: unknown payment', {
          codiQrId,
          fallbackOrderId,
        });
        return { ok: true };
      }

      const paidResult = await markOrderPaidInTx(tx, {
        orderId: targetOrderId,
        paymentId: matchedPayment?.id,
        transactionId,
        now,
      });

      if (!paidResult.order) {
        console.warn('Webhook codi.qr.payment_received: order not found', { targetOrderId });
      }

      return { ok: true };
    }

    if (eventType === 'bank.account.updated') {
      const bankAccountId =
        typeof dataObj.bankAccountId === 'string'
          ? dataObj.bankAccountId
          : typeof dataObj.id === 'string'
            ? dataObj.id
            : undefined;

      if (bankAccountId) {
        await tx
          .update(businesses)
          .set({ codiStatus: 'ACTIVE' })
          .where(eq(businesses.peyBankAccountId, bankAccountId));
      }

      return { ok: true };
    }

    return { ok: true };
  });
}
