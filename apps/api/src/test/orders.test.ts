import crypto from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { eq } from 'drizzle-orm';
import { buildApp } from '../app.js';
import { client, db } from '../db/index.js';
import { businesses, orders, payments, products, stockMovements } from '../db/schema.js';
import { AppError } from '../lib/errors.js';
import {
  createPeyClient,
  type CreateCodiQrInput,
  type CreateCodiQrResult,
  type PeyClient,
} from '../lib/pey.js';

const TEST_WEBHOOK_SECRET_RAW = Buffer.from('super-secret-webhook-key-for-pey-tests').toString(
  'base64'
);
const TEST_WEBHOOK_SECRET = `whsec_${TEST_WEBHOOK_SECRET_RAW}`;

function signWebhookPayload(
  webhookId: string,
  timestampSec: number,
  rawBody: string,
  secret = TEST_WEBHOOK_SECRET
): string {
  const key = Buffer.from(secret.replace(/^whsec_/, ''), 'base64');
  const toSign = `${webhookId}.${timestampSec}.${rawBody}`;
  const sig = crypto.createHmac('sha256', key).update(toSign, 'utf8').digest('base64');
  return `v1,${sig}`;
}

async function clearDatabase(): Promise<void> {
  await client.execute('DELETE FROM payments');
  await client.execute('DELETE FROM order_items');
  await client.execute('DELETE FROM orders');
  await client.execute('DELETE FROM stock_movements');
  await client.execute('DELETE FROM products');
  await client.execute('DELETE FROM businesses');
  await client.execute('DELETE FROM users');
  await client.execute('DELETE FROM webhook_events');
}

describe('Orders, pey CoDi QR & Webhooks (T02)', () => {
  let app: FastifyInstance;
  const createCodiQrMock = vi.fn<(input: CreateCodiQrInput) => Promise<CreateCodiQrResult>>();
  const mockPey: PeyClient = {
    createCodiQr: (input) => createCodiQrMock(input),
  };

  beforeAll(async () => {
    process.env.PEY_WEBHOOK_SECRET = TEST_WEBHOOK_SECRET;
    app = await buildApp({ pey: mockPey });
    await app.ready();
  });

  beforeEach(async () => {
    await clearDatabase();
    createCodiQrMock.mockReset();
    let qrCounter = 0;
    createCodiQrMock.mockImplementation(async () => {
      qrCounter += 1;
      return {
        id: `codi_qr_${qrCounter}`,
        qrString: `00020101021226580010MX.CODI.QR${qrCounter}`,
      };
    });
    process.env.PEY_WEBHOOK_SECRET = TEST_WEBHOOK_SECRET;
  });

  afterAll(async () => {
    await app.close();
  });

  async function setupMerchantAndCustomer(prepType: 'made_to_order' | 'instant' = 'made_to_order') {
    const ownerReg = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: `owner-${prepType}@example.com`,
        password: 'password123',
        name: 'Merchant Owner',
      },
    });
    const ownerToken = ownerReg.json().token as string;
    const ownerId = ownerReg.json().user.id as string;

    const bizRes = await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: `Negocio ${prepType}`,
        category: 'food',
        prepType,
      },
    });
    const business = bizRes.json();

    const prod1Res = await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: 'Taco al Pastor',
        priceCents: 2500,
        trackStock: true,
        stock: 10,
        prepMinutes: 8,
      },
    });
    const prod1 = prod1Res.json();

    const prod2Res = await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: 'Agua de Horchata',
        priceCents: 3000,
        trackStock: false,
        stock: 0,
      },
    });
    const prod2 = prod2Res.json();

    const custReg = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: `cust-${prepType}@example.com`,
        password: 'password123',
        name: 'Customer User',
      },
    });
    const customerToken = custReg.json().token as string;
    const customerId = custReg.json().user.id as string;

    return {
      ownerToken,
      ownerId,
      customerToken,
      customerId,
      business,
      prod1,
      prod2,
    };
  }

  it('creates customer and walk-in orders, snapshots prices, computes totals server-side, and rejects insufficient stock without decrementing', async () => {
    const { ownerToken, customerToken, customerId, business, prod1, prod2 } =
      await setupMerchantAndCustomer('made_to_order');

    // Reject insufficient stock (prod1 has stock 10, requesting 11)
    const insufficientRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [{ productId: prod1.id, qty: 11 }],
      },
    });
    expect(insufficientRes.statusCode).toBe(409);
    expect(insufficientRes.json().error.code).toBe('INSUFFICIENT_STOCK');

    // Customer creates valid order (2 * 2500 + 1 * 3000 = 8000)
    const custOrderRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [
          { productId: prod1.id, qty: 2 },
          { productId: prod2.id, qty: 1 },
        ],
        note: 'Con todo y salsa verde',
      },
    });
    expect(custOrderRes.statusCode).toBe(201);
    const custOrder = custOrderRes.json();
    expect(custOrder.status).toBe('pending_payment');
    expect(custOrder.customerId).toBe(customerId);
    expect(custOrder.totalCents).toBe(8000);
    expect(custOrder.items).toHaveLength(2);
    expect(custOrder.items[0]).toMatchObject({
      productId: prod1.id,
      name: 'Taco al Pastor',
      priceCents: 2500,
      qty: 2,
    });

    // Stock must NOT be decremented yet on order creation
    const [prod1Row] = await db.select().from(products).where(eq(products.id, prod1.id));
    expect(prod1Row?.stock).toBe(10);

    // Owner ordering from their own business creates a walk-in order (customerId = null)
    const walkInRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        businessId: business.id,
        items: [{ productId: prod1.id, qty: 3 }],
      },
    });
    expect(walkInRes.statusCode).toBe(201);
    const walkInOrder = walkInRes.json();
    expect(walkInOrder.customerId).toBeNull();
    expect(walkInOrder.totalCents).toBe(7500);

    // Visibility: unrelated third user gets 404 on GET /orders/:id
    const strangerReg = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'stranger@example.com', password: 'password123', name: 'Stranger' },
    });
    const strangerToken = strangerReg.json().token as string;

    const strangerGet = await app.inject({
      method: 'GET',
      url: `/orders/${custOrder.id}`,
      headers: { authorization: `Bearer ${strangerToken}` },
    });
    expect(strangerGet.statusCode).toBe(404);

    // Customer and Owner can both GET /orders/:id and list orders
    const custGet = await app.inject({
      method: 'GET',
      url: `/orders/${custOrder.id}`,
      headers: { authorization: `Bearer ${customerToken}` },
    });
    expect(custGet.statusCode).toBe(200);
    expect(custGet.json().id).toBe(custOrder.id);

    const bizList = await app.inject({
      method: 'GET',
      url: '/orders?role=business',
      headers: { authorization: `Bearer ${ownerToken}` },
    });
    expect(bizList.statusCode).toBe(200);
    expect(bizList.json()).toHaveLength(2);

    const custList = await app.inject({
      method: 'GET',
      url: '/orders?role=customer',
      headers: { authorization: `Bearer ${customerToken}` },
    });
    expect(custList.statusCode).toBe(200);
    expect(custList.json()).toHaveLength(1);
  });

  it('lazily expires pending_payment orders older than 15 minutes on read', async () => {
    const { customerToken, business, prod1 } = await setupMerchantAndCustomer('made_to_order');

    const createRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [{ productId: prod1.id, qty: 1 }],
      },
    });
    const order = createRes.json();

    const sixteenMinutesAgo = Math.floor(Date.now() / 1000) - 16 * 60;
    await db
      .update(orders)
      .set({ createdAt: sixteenMinutesAgo })
      .where(eq(orders.id, order.id));

    const getRes = await app.inject({
      method: 'GET',
      url: `/orders/${order.id}`,
      headers: { authorization: `Bearer ${customerToken}` },
    });
    expect(getRes.statusCode).toBe(200);
    expect(getRes.json().status).toBe('expired');
  });

  it('enforces status machine transitions for made_to_order and instant businesses, and restocks on cancelling a paid order', async () => {
    // 1. made_to_order flow
    const mto = await setupMerchantAndCustomer('made_to_order');

    const order1Res = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${mto.customerToken}` },
      payload: {
        businessId: mto.business.id,
        items: [{ productId: mto.prod1.id, qty: 4 }],
      },
    });
    const order1 = order1Res.json();

    // Customer cannot PATCH status
    const custPatch = await app.inject({
      method: 'PATCH',
      url: `/orders/${order1.id}/status`,
      headers: { authorization: `Bearer ${mto.customerToken}` },
      payload: { status: 'cancelled' },
    });
    expect(custPatch.statusCode).toBe(403);

    // Invalid transition: pending_payment -> preparing (409)
    const invalidPendingToPrep = await app.inject({
      method: 'PATCH',
      url: `/orders/${order1.id}/status`,
      headers: { authorization: `Bearer ${mto.ownerToken}` },
      payload: { status: 'preparing' },
    });
    expect(invalidPendingToPrep.statusCode).toBe(409);
    expect(invalidPendingToPrep.json().error.code).toBe('INVALID_TRANSITION');

    // Simulate paid -> stock becomes 10 - 4 = 6
    const simRes = await app.inject({
      method: 'POST',
      url: `/dev/orders/${order1.id}/simulate-paid`,
    });
    expect(simRes.statusCode).toBe(200);
    expect(simRes.json().status).toBe('paid');

    // Invalid transition: paid -> ready directly (skipping preparing) -> 409
    const invalidPaidToReady = await app.inject({
      method: 'PATCH',
      url: `/orders/${order1.id}/status`,
      headers: { authorization: `Bearer ${mto.ownerToken}` },
      payload: { status: 'ready' },
    });
    expect(invalidPaidToReady.statusCode).toBe(409);

    // Valid transition: paid -> preparing -> ready -> delivered
    const toPrep = await app.inject({
      method: 'PATCH',
      url: `/orders/${order1.id}/status`,
      headers: { authorization: `Bearer ${mto.ownerToken}` },
      payload: { status: 'preparing' },
    });
    expect(toPrep.statusCode).toBe(200);
    expect(toPrep.json().status).toBe('preparing');

    const toReady = await app.inject({
      method: 'PATCH',
      url: `/orders/${order1.id}/status`,
      headers: { authorization: `Bearer ${mto.ownerToken}` },
      payload: { status: 'ready' },
    });
    expect(toReady.statusCode).toBe(200);
    expect(toReady.json().status).toBe('ready');

    const toDelivered = await app.inject({
      method: 'PATCH',
      url: `/orders/${order1.id}/status`,
      headers: { authorization: `Bearer ${mto.ownerToken}` },
      payload: { status: 'delivered' },
    });
    expect(toDelivered.statusCode).toBe(200);
    expect(toDelivered.json().status).toBe('delivered');

    // Cancel a paid order -> restocks and writes stock_movements reason 'order_cancelled'
    const order2Res = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${mto.customerToken}` },
      payload: {
        businessId: mto.business.id,
        items: [{ productId: mto.prod1.id, qty: 2 }],
      },
    });
    const order2 = order2Res.json();
    await app.inject({ method: 'POST', url: `/dev/orders/${order2.id}/simulate-paid` });

    const [stockBeforeCancel] = await db
      .select()
      .from(products)
      .where(eq(products.id, mto.prod1.id));
    expect(stockBeforeCancel?.stock).toBe(4); // 10 - 4 - 2 = 4

    const cancelPaid = await app.inject({
      method: 'PATCH',
      url: `/orders/${order2.id}/status`,
      headers: { authorization: `Bearer ${mto.ownerToken}` },
      payload: { status: 'cancelled' },
    });
    expect(cancelPaid.statusCode).toBe(200);
    expect(cancelPaid.json().status).toBe('cancelled');

    const [stockAfterCancel] = await db
      .select()
      .from(products)
      .where(eq(products.id, mto.prod1.id));
    expect(stockAfterCancel?.stock).toBe(6); // restocked +2

    const movements = await db
      .select()
      .from(stockMovements)
      .where(eq(stockMovements.productId, mto.prod1.id));
    const cancelMovement = movements.find((m) => m.reason === 'order_cancelled');
    expect(cancelMovement).toBeDefined();
    expect(cancelMovement?.delta).toBe(2);

    // 2. instant business flow: paid -> preparing is rejected with 409, paid -> delivered succeeds
    const inst = await setupMerchantAndCustomer('instant');
    const instOrderRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${inst.customerToken}` },
      payload: {
        businessId: inst.business.id,
        items: [{ productId: inst.prod1.id, qty: 1 }],
      },
    });
    const instOrder = instOrderRes.json();
    await app.inject({ method: 'POST', url: `/dev/orders/${instOrder.id}/simulate-paid` });

    const instToPrep = await app.inject({
      method: 'PATCH',
      url: `/orders/${instOrder.id}/status`,
      headers: { authorization: `Bearer ${inst.ownerToken}` },
      payload: { status: 'preparing' },
    });
    expect(instToPrep.statusCode).toBe(409);
    expect(instToPrep.json().error.code).toBe('INVALID_TRANSITION');

    const instToDelivered = await app.inject({
      method: 'PATCH',
      url: `/orders/${instOrder.id}/status`,
      headers: { authorization: `Bearer ${inst.ownerToken}` },
      payload: { status: 'delivered' },
    });
    expect(instToDelivered.statusCode).toBe(200);
    expect(instToDelivered.json().status).toBe('delivered');
  });

  it('POST /orders/:id/pay creates CoDi QR via pey client, passes bankAccountId only when ACTIVE, and reuses unexpired pending QR', async () => {
    const { customerToken, business, prod1 } = await setupMerchantAndCustomer('made_to_order');

    // Set peyBankAccountId with PENDING status first -> bankAccountId must be omitted
    await db
      .update(businesses)
      .set({ peyBankAccountId: 'ba_123', codiStatus: 'PENDING' })
      .where(eq(businesses.id, business.id));

    const orderRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [{ productId: prod1.id, qty: 2 }],
      },
    });
    const order = orderRes.json();

    const payRes1 = await app.inject({
      method: 'POST',
      url: `/orders/${order.id}/pay`,
      headers: { authorization: `Bearer ${customerToken}` },
    });
    expect(payRes1.statusCode).toBe(200);
    const payBody1 = payRes1.json();
    expect(payBody1).toMatchObject({
      qrString: '00020101021226580010MX.CODI.QR1',
      codiQrId: 'codi_qr_1',
      amountCents: 5000,
    });
    expect(payBody1.expiresAt).toBeTypeOf('number');
    expect(createCodiQrMock).toHaveBeenCalledTimes(1);
    expect(createCodiQrMock).toHaveBeenCalledWith({
      amountCents: 5000,
      concept: `Pedido ${order.id.slice(-6)}`,
      numRef: expect.stringMatching(/^\d{7}$/),
      expirationSec: 600,
      metadata: {
        orderId: order.id,
        businessId: business.id,
      },
    });
    expect(createCodiQrMock.mock.calls[0]?.[0]?.bankAccountId).toBeUndefined();

    // Second call to /pay reuses unexpired pending payment without calling pey again
    const payRes2 = await app.inject({
      method: 'POST',
      url: `/orders/${order.id}/pay`,
      headers: { authorization: `Bearer ${customerToken}` },
    });
    expect(payRes2.statusCode).toBe(200);
    expect(payRes2.json()).toEqual(payBody1);
    expect(createCodiQrMock).toHaveBeenCalledTimes(1);

    // When business codiStatus is ACTIVE, bankAccountId is included
    await db
      .update(businesses)
      .set({ peyBankAccountId: 'ba_active_999', codiStatus: 'ACTIVE' })
      .where(eq(businesses.id, business.id));

    const order2Res = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [{ productId: prod1.id, qty: 1 }],
      },
    });
    const order2 = order2Res.json();

    const payOrder2 = await app.inject({
      method: 'POST',
      url: `/orders/${order2.id}/pay`,
      headers: { authorization: `Bearer ${customerToken}` },
    });
    expect(payOrder2.statusCode).toBe(200);
    expect(createCodiQrMock).toHaveBeenCalledTimes(2);
    expect(createCodiQrMock.mock.calls[1]?.[0]?.bankAccountId).toBe('ba_active_999');
  });

  it('verifies Standard Webhooks signature, marks order paid + decrements stock in one tx, handles duplicates idempotently, and updates sales summary', async () => {
    const { ownerToken, customerToken, business, prod1, prod2 } =
      await setupMerchantAndCustomer('made_to_order');

    const orderRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [
          { productId: prod1.id, qty: 3 },
          { productId: prod2.id, qty: 2 },
        ],
      },
    });
    const order = orderRes.json();

    const payRes = await app.inject({
      method: 'POST',
      url: `/orders/${order.id}/pay`,
      headers: { authorization: `Bearer ${customerToken}` },
    });
    const { codiQrId } = payRes.json();

    const nowSec = Math.floor(Date.now() / 1000);
    const rawPayload = JSON.stringify({
      type: 'codi.qr.payment_received',
      amount: 135,
      codiQrId,
      transactionId: 'tx_pey_001',
      datePaid: new Date().toISOString(),
      numRef: '1234567',
      concept: `Pedido ${order.id.slice(-6)}`,
      metadata: {
        externalMetadata: {
          orderId: order.id,
          businessId: business.id,
        },
      },
    });

    // 1. Bad signature -> 401 INVALID_SIGNATURE
    const badSigRes = await app.inject({
      method: 'POST',
      url: '/webhooks/pey',
      headers: {
        'content-type': 'application/json',
        'webhook-id': 'msg_bad_sig',
        'webhook-timestamp': String(nowSec),
        'webhook-signature': 'v1,invalidbase64signature==',
      },
      payload: rawPayload,
    });
    expect(badSigRes.statusCode).toBe(401);
    expect(badSigRes.json().error.code).toBe('INVALID_SIGNATURE');

    // 2. Stale timestamp (> 5 minutes old) -> 401 INVALID_SIGNATURE
    const staleTs = nowSec - 360;
    const staleSig = signWebhookPayload('msg_stale', staleTs, rawPayload);
    const staleRes = await app.inject({
      method: 'POST',
      url: '/webhooks/pey',
      headers: {
        'content-type': 'application/json',
        'webhook-id': 'msg_stale',
        'webhook-timestamp': String(staleTs),
        'webhook-signature': staleSig,
      },
      payload: rawPayload,
    });
    expect(staleRes.statusCode).toBe(401);
    expect(staleRes.json().error.code).toBe('INVALID_SIGNATURE');

    // 3. Valid signature (including multiple space-separated v1 signatures) -> 200, marks paid, decrements stock
    const validSig = signWebhookPayload('msg_valid_1', nowSec, rawPayload);
    const validRes = await app.inject({
      method: 'POST',
      url: '/webhooks/pey',
      headers: {
        'content-type': 'application/json',
        'webhook-id': 'msg_valid_1',
        'webhook-timestamp': String(nowSec),
        'webhook-signature': `v1,otherKeySig== ${validSig}`,
      },
      payload: rawPayload,
    });
    expect(validRes.statusCode).toBe(200);
    expect(validRes.json()).toEqual({ ok: true });

    // Order is paid and paidAt is set
    const updatedOrderRes = await app.inject({
      method: 'GET',
      url: `/orders/${order.id}`,
      headers: { authorization: `Bearer ${customerToken}` },
    });
    expect(updatedOrderRes.statusCode).toBe(200);
    expect(updatedOrderRes.json().status).toBe('paid');
    expect(updatedOrderRes.json().paidAt).toBeTypeOf('number');
    expect(updatedOrderRes.json().payment.status).toBe('paid');
    expect(updatedOrderRes.json().payment.transactionId).toBe('tx_pey_001');

    // Stock decremented from 10 to 7 and stock_movements row written with reason 'sale'
    const [prod1After] = await db.select().from(products).where(eq(products.id, prod1.id));
    expect(prod1After?.stock).toBe(7);

    const movements = await db
      .select()
      .from(stockMovements)
      .where(eq(stockMovements.productId, prod1.id));
    expect(movements).toHaveLength(1);
    expect(movements[0]?.delta).toBe(-3);
    expect(movements[0]?.reason).toBe('sale');

    // 4. Duplicate webhook-id -> 200 { ok: true, duplicate: true }, NO double decrement
    const dupRes = await app.inject({
      method: 'POST',
      url: '/webhooks/pey',
      headers: {
        'content-type': 'application/json',
        'webhook-id': 'msg_valid_1',
        'webhook-timestamp': String(nowSec),
        'webhook-signature': validSig,
      },
      payload: rawPayload,
    });
    expect(dupRes.statusCode).toBe(200);
    expect(dupRes.json()).toEqual({ ok: true, duplicate: true });

    const [prod1AfterDup] = await db.select().from(products).where(eq(products.id, prod1.id));
    expect(prod1AfterDup?.stock).toBe(7);

    // 5. bank.account.updated webhook activates business codiStatus
    await db
      .update(businesses)
      .set({ peyBankAccountId: 'ba_webhook_777', codiStatus: 'PENDING' })
      .where(eq(businesses.id, business.id));

    const bankBody = JSON.stringify({
      type: 'bank.account.updated',
      bankAccountId: 'ba_webhook_777',
      codiStatus: 'ACTIVE',
    });
    const bankSig = signWebhookPayload('msg_bank_1', nowSec, bankBody);
    const bankRes = await app.inject({
      method: 'POST',
      url: '/webhooks/pey',
      headers: {
        'content-type': 'application/json',
        'webhook-id': 'msg_bank_1',
        'webhook-timestamp': String(nowSec),
        'webhook-signature': bankSig,
      },
      payload: bankBody,
    });
    expect(bankRes.statusCode).toBe(200);

    const [bizAfterBank] = await db
      .select()
      .from(businesses)
      .where(eq(businesses.id, business.id));
    expect(bizAfterBank?.codiStatus).toBe('ACTIVE');

    // 6. Sales summary reflects paid orders
    const summaryRes = await app.inject({
      method: 'GET',
      url: '/business/sales/summary',
      headers: { authorization: `Bearer ${ownerToken}` },
    });
    expect(summaryRes.statusCode).toBe(200);
    expect(summaryRes.json()).toEqual({
      totalCents: 13500,
      orders: 1,
      topProducts: [
        {
          productId: prod1.id,
          name: 'Taco al Pastor',
          qty: 3,
          revenueCents: 7500,
        },
        {
          productId: prod2.id,
          name: 'Agua de Horchata',
          qty: 2,
          revenueCents: 6000,
        },
      ],
    });
  });

  it('disables POST /dev/orders/:id/simulate-paid when NODE_ENV=production', async () => {
    const { customerToken, business, prod1 } = await setupMerchantAndCustomer('made_to_order');
    const orderRes = await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [{ productId: prod1.id, qty: 1 }],
      },
    });
    const order = orderRes.json();

    // Route registration depends on env at build time: build a fresh "production" app.
    const prevNodeEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    const prodApp = await buildApp({ pey: mockPey });
    try {
      const res = await prodApp.inject({
        method: 'POST',
        url: `/dev/orders/${order.id}/simulate-paid`,
      });
      expect(res.statusCode).toBe(404);
    } finally {
      process.env.NODE_ENV = prevNodeEnv;
      await prodApp.close();
    }
  });

  it('pey client handles missing key (503), pey error payload (502), and PEY_TEST_AMOUNT_OVERRIDE', async () => {
    // Missing key -> 503 PEY_NOT_CONFIGURED
    const noKeyClient = createPeyClient({ apiKey: '' });
    await expect(
      noKeyClient.createCodiQr({
        amountCents: 5000,
        concept: 'Pedido 123456',
        numRef: '1234567',
        expirationSec: 600,
      })
    ).rejects.toMatchObject({
      statusCode: 503,
      code: 'PEY_NOT_CONFIGURED',
    } satisfies Partial<AppError>);

    // Mock global fetch for error and override tests
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    try {
      fetchSpy.mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            error: {
              message: 'Invalid bankAccountId',
              type: 'invalid_request_error',
              requestId: 'req_abc123',
            },
          }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        )
      );

      const clientWithKey = createPeyClient({
        baseUrl: 'https://api.pey.mx',
        apiKey: 'test_key_never_logged',
      });

      await expect(
        clientWithKey.createCodiQr({
          amountCents: 5000,
          concept: 'Pedido 123456',
          numRef: '1234567',
          expirationSec: 600,
        })
      ).rejects.toMatchObject({
        statusCode: 502,
        code: 'PEY_ERROR',
      } satisfies Partial<AppError>);

      // Override amount test
      fetchSpy.mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 'qr_live_1',
            qrString: '00020101',
            qrImage: null,
          }),
          { status: 200, headers: { 'Content-Type': 'application/json' } }
        )
      );

      const clientWithOverride = createPeyClient({
        baseUrl: 'https://api.pey.mx',
        apiKey: 'test_key_never_logged',
        testAmountOverride: '0.01',
      });

      const qr = await clientWithOverride.createCodiQr({
        amountCents: 15000,
        concept: 'Pedido 654321',
        numRef: '7654321',
        expirationSec: 600,
      });
      expect(qr).toEqual({ id: 'qr_live_1', qrString: '00020101' });

      const lastCallBody = JSON.parse(String(fetchSpy.mock.calls[1]?.[1]?.body));
      expect(lastCallBody.amount).toBe(0.01);
    } finally {
      fetchSpy.mockRestore();
    }
  });
});
