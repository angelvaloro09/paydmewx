import { and, asc, eq, gte, inArray, lte } from 'drizzle-orm';
import { ulid } from 'ulid';
import { db } from '../db/index.js';
import {
  orderItems,
  orders,
  products,
  stockMovements,
  type ProductRow,
  type StockMovementRow,
} from '../db/schema.js';
import { AppError } from '../lib/errors.js';

export interface CreateProductInput {
  name: string;
  priceCents: number;
  trackStock?: boolean;
  stock?: number;
  prepMinutes?: number | null;
  imageUrl?: string | null;
}

export interface UpdateProductInput {
  name?: string;
  priceCents?: number;
  trackStock?: boolean;
  stock?: number;
  prepMinutes?: number | null;
  imageUrl?: string | null;
  active?: boolean;
}

export async function listOwnerProducts(businessId: string): Promise<ProductRow[]> {
  return db.select().from(products).where(eq(products.businessId, businessId));
}

export async function getOwnedProductOrThrow(
  businessId: string,
  productId: string
): Promise<ProductRow> {
  const [product] = await db
    .select()
    .from(products)
    .where(and(eq(products.id, productId), eq(products.businessId, businessId)))
    .limit(1);

  if (!product) {
    throw new AppError(404, 'PRODUCT_NOT_FOUND', 'Product not found');
  }

  return product;
}

export async function createOwnerProduct(
  businessId: string,
  input: CreateProductInput
): Promise<ProductRow> {
  const now = Math.floor(Date.now() / 1000);
  const row: ProductRow = {
    id: ulid(),
    businessId,
    name: input.name.trim(),
    priceCents: input.priceCents,
    trackStock: input.trackStock ?? true,
    stock: input.stock ?? 0,
    prepMinutes: input.prepMinutes ?? null,
    imageUrl: input.imageUrl ?? null,
    active: true,
    createdAt: now,
  };

  await db.insert(products).values(row);
  return row;
}

export async function updateOwnerProduct(
  businessId: string,
  productId: string,
  input: UpdateProductInput
): Promise<ProductRow> {
  const existing = await getOwnedProductOrThrow(businessId, productId);

  const updates: Partial<ProductRow> = {};
  if (input.name !== undefined) updates.name = input.name.trim();
  if (input.priceCents !== undefined) updates.priceCents = input.priceCents;
  if (input.trackStock !== undefined) updates.trackStock = input.trackStock;
  if (input.stock !== undefined) updates.stock = input.stock;
  if (input.prepMinutes !== undefined) updates.prepMinutes = input.prepMinutes;
  if (input.imageUrl !== undefined) updates.imageUrl = input.imageUrl;
  if (input.active !== undefined) updates.active = input.active;

  if (Object.keys(updates).length > 0) {
    await db
      .update(products)
      .set(updates)
      .where(and(eq(products.id, existing.id), eq(products.businessId, businessId)));
  }

  return getOwnedProductOrThrow(businessId, productId);
}

export async function softDeleteOwnerProduct(
  businessId: string,
  productId: string
): Promise<ProductRow> {
  const existing = await getOwnedProductOrThrow(businessId, productId);

  await db
    .update(products)
    .set({ active: false })
    .where(and(eq(products.id, existing.id), eq(products.businessId, businessId)));

  return { ...existing, active: false };
}

export async function adjustProductStock(
  businessId: string,
  productId: string,
  input: { delta: number; reason: string }
): Promise<ProductRow & { product: ProductRow; movement: StockMovementRow }> {
  return db.transaction(async (tx) => {
    const [existing] = await tx
      .select()
      .from(products)
      .where(and(eq(products.id, productId), eq(products.businessId, businessId)))
      .limit(1);

    if (!existing) {
      throw new AppError(404, 'PRODUCT_NOT_FOUND', 'Product not found');
    }

    const newStock = existing.stock + input.delta;
    if (newStock < 0) {
      throw new AppError(400, 'INSUFFICIENT_STOCK', 'Resulting stock cannot be negative');
    }

    await tx
      .update(products)
      .set({ stock: newStock })
      .where(and(eq(products.id, existing.id), eq(products.businessId, businessId)));

    const now = Math.floor(Date.now() / 1000);
    const movement: StockMovementRow = {
      id: ulid(),
      productId: existing.id,
      delta: input.delta,
      reason: input.reason.trim(),
      createdAt: now,
    };

    await tx.insert(stockMovements).values(movement);

    const updatedProduct: ProductRow = {
      ...existing,
      stock: newStock,
    };

    return {
      ...updatedProduct,
      product: updatedProduct,
      movement,
    };
  });
}

export async function listLowStockProducts(
  businessId: string,
  threshold = 5
): Promise<ProductRow[]> {
  return db
    .select()
    .from(products)
    .where(
      and(
        eq(products.businessId, businessId),
        eq(products.active, true),
        eq(products.trackStock, true),
        lte(products.stock, threshold)
      )
    )
    .orderBy(asc(products.stock));
}

export async function getSalesSummary(
  businessId: string,
  range: { from?: number; to?: number }
): Promise<{
  totalCents: number;
  orders: number;
  topProducts: Array<{
    productId: string;
    name: string;
    qty: number;
    revenueCents: number;
  }>;
}> {
  const paidStatuses = ['paid', 'preparing', 'ready', 'delivered'] as const;
  const conditions = [
    eq(orders.businessId, businessId),
    inArray(orders.status, [...paidStatuses]),
  ];

  if (range.from !== undefined) {
    conditions.push(gte(orders.createdAt, range.from));
  }
  if (range.to !== undefined) {
    conditions.push(lte(orders.createdAt, range.to));
  }

  const matchingOrders = await db
    .select()
    .from(orders)
    .where(and(...conditions));

  if (matchingOrders.length === 0) {
    return {
      totalCents: 0,
      orders: 0,
      topProducts: [],
    };
  }

  const totalCents = matchingOrders.reduce((acc, o) => acc + o.totalCents, 0);
  const orderIds = matchingOrders.map((o) => o.id);

  const items = await db
    .select()
    .from(orderItems)
    .where(inArray(orderItems.orderId, orderIds));

  const productAgg = new Map<
    string,
    { productId: string; name: string; qty: number; revenueCents: number }
  >();

  for (const item of items) {
    const prev = productAgg.get(item.productId) ?? {
      productId: item.productId,
      name: item.name,
      qty: 0,
      revenueCents: 0,
    };
    prev.qty += item.qty;
    prev.revenueCents += item.priceCents * item.qty;
    productAgg.set(item.productId, prev);
  }

  const topProducts = Array.from(productAgg.values())
    .sort((a, b) => b.qty - a.qty || b.revenueCents - a.revenueCents)
    .slice(0, 10);

  return {
    totalCents,
    orders: matchingOrders.length,
    topProducts,
  };
}
