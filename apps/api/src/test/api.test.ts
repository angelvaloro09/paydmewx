import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../app.js';
import { client, db } from '../db/index.js';
import { stockMovements } from '../db/schema.js';
import { runSeed } from '../db/seed.js';
import { eq } from 'drizzle-orm';

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

describe('PaydMewx API Core (T01)', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();
  });

  beforeEach(async () => {
    await clearDatabase();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health returns { ok: true }', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/health',
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });

  it('registers, logs in, fetches /me, and never returns passwordHash', async () => {
    const regRes = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: 'ana@example.com',
        password: 'password123',
        name: 'Ana López',
      },
    });

    expect(regRes.statusCode).toBe(201);
    const regBody = regRes.json();
    expect(regBody.token).toBeTypeOf('string');
    expect(regBody.user).toMatchObject({
      email: 'ana@example.com',
      name: 'Ana López',
    });
    expect(regBody.user.passwordHash).toBeUndefined();

    // Duplicate registration returns 409
    const dupRes = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: 'ANA@example.com',
        password: 'password123',
        name: 'Ana Duplicate',
      },
    });
    expect(dupRes.statusCode).toBe(409);

    // Login with valid credentials
    const loginRes = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: {
        email: 'ana@example.com',
        password: 'password123',
      },
    });
    expect(loginRes.statusCode).toBe(200);
    const loginBody = loginRes.json();
    expect(loginBody.token).toBeTypeOf('string');
    expect(loginBody.user.passwordHash).toBeUndefined();

    // Login with wrong password returns 401
    const badLoginRes = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: {
        email: 'ana@example.com',
        password: 'wrongpassword',
      },
    });
    expect(badLoginRes.statusCode).toBe(401);

    // GET /me returns user and null business initially
    const meRes = await app.inject({
      method: 'GET',
      url: '/me',
      headers: {
        authorization: `Bearer ${loginBody.token}`,
      },
    });
    expect(meRes.statusCode).toBe(200);
    const meBody = meRes.json();
    expect(meBody.user.email).toBe('ana@example.com');
    expect(meBody.user.passwordHash).toBeUndefined();
    expect(meBody.business).toBeNull();
  });

  it('converts user to business, returns 409 on second attempt, and validates CLABE on PATCH /me/business', async () => {
    const regRes = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: 'carlos@example.com',
        password: 'password123',
        name: 'Carlos',
      },
    });
    const { token } = regRes.json();

    const createBizRes = await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        name: 'Tacos Don Carlos',
        category: 'food',
        prepType: 'made_to_order',
        description: 'Tacos al pastor',
        address: 'Roma Norte, CDMX',
        lat: 19.417,
        lng: -99.162,
      },
    });
    expect(createBizRes.statusCode).toBe(201);
    const biz = createBizRes.json();
    expect(biz.name).toBe('Tacos Don Carlos');
    expect(biz.category).toBe('food');
    expect(biz.prepType).toBe('made_to_order');
    expect(biz.active).toBe(true);

    // Second POST /me/business returns 409
    const secondBizRes = await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        name: 'Otro Negocio',
        category: 'grocery',
        prepType: 'instant',
      },
    });
    expect(secondBizRes.statusCode).toBe(409);

    // PATCH /me/business with invalid CLABE returns 400
    const badClabeRes = await app.inject({
      method: 'PATCH',
      url: '/me/business',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        clabe: '012180015826225719',
      },
    });
    expect(badClabeRes.statusCode).toBe(400);

    // PATCH /me/business with valid CLABE stores it
    const goodClabeRes = await app.inject({
      method: 'PATCH',
      url: '/me/business',
      headers: { authorization: `Bearer ${token}` },
      payload: {
        name: 'Tacos Don Carlos Oficial',
        clabe: '012180015826225713',
      },
    });
    expect(goodClabeRes.statusCode).toBe(200);
    expect(goodClabeRes.json().clabe).toBe('012180015826225713');
    expect(goodClabeRes.json().name).toBe('Tacos Don Carlos Oficial');

    // GET /me now includes the business
    const meRes = await app.inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(meRes.statusCode).toBe(200);
    expect(meRes.json().business.id).toBe(biz.id);
    expect(meRes.json().business.clabe).toBe('012180015826225713');
  });

  it('filters businesses in discovery endpoints by category, prepType, and search query q', async () => {
    // Owner 1: food / made_to_order
    const reg1 = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'b1@example.com', password: 'password123', name: 'Owner 1' },
    });
    const t1 = reg1.json().token;
    const b1Res = await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${t1}` },
      payload: {
        name: 'Taquería El Sol',
        description: 'Especialidad en suadero y pastor',
        category: 'food',
        prepType: 'made_to_order',
      },
    });
    const b1 = b1Res.json();

    // Owner 2: footwear / instant
    const reg2 = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'b2@example.com', password: 'password123', name: 'Owner 2' },
    });
    const t2 = reg2.json().token;
    const b2Res = await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${t2}` },
      payload: {
        name: 'Zapatería Coyoacán',
        description: 'Botas y tenis de piel',
        category: 'footwear',
        prepType: 'instant',
      },
    });
    const b2 = b2Res.json();

    // All active businesses
    const allRes = await app.inject({ method: 'GET', url: '/businesses' });
    expect(allRes.statusCode).toBe(200);
    expect(allRes.json()).toHaveLength(2);

    // Filter by category=food
    const foodRes = await app.inject({ method: 'GET', url: '/businesses?category=food' });
    expect(foodRes.statusCode).toBe(200);
    expect(foodRes.json()).toHaveLength(1);
    expect(foodRes.json()[0].id).toBe(b1.id);

    // Filter by prepType=instant
    const instantRes = await app.inject({ method: 'GET', url: '/businesses?prepType=instant' });
    expect(instantRes.statusCode).toBe(200);
    expect(instantRes.json()).toHaveLength(1);
    expect(instantRes.json()[0].id).toBe(b2.id);

    // Filter by q=suadero
    const qRes = await app.inject({ method: 'GET', url: '/businesses?q=suadero' });
    expect(qRes.statusCode).toBe(200);
    expect(qRes.json()).toHaveLength(1);
    expect(qRes.json()[0].id).toBe(b1.id);

    // Detail endpoint
    const detailRes = await app.inject({ method: 'GET', url: `/businesses/${b1.id}` });
    expect(detailRes.statusCode).toBe(200);
    expect(detailRes.json().name).toBe('Taquería El Sol');
  });

  it('supports product CRUD, ownership isolation (404 for other owner), stock adjust transaction, and low-stock listing', async () => {
    // Owner A
    const regA = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'ownera@example.com', password: 'password123', name: 'Owner A' },
    });
    const tokenA = regA.json().token;
    const bizARes = await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${tokenA}` },
      payload: { name: 'Negocio A', category: 'food', prepType: 'made_to_order' },
    });
    const bizA = bizARes.json();

    // Owner B
    const regB = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: { email: 'ownerb@example.com', password: 'password123', name: 'Owner B' },
    });
    const tokenB = regB.json().token;
    await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${tokenB}` },
      payload: { name: 'Negocio B', category: 'tailoring', prepType: 'made_to_order' },
    });

    // Owner A creates two products
    const createProd1 = await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${tokenA}` },
      payload: {
        name: 'Taco Pastor',
        priceCents: 2200,
        trackStock: true,
        stock: 10,
        prepMinutes: 5,
      },
    });
    expect(createProd1.statusCode).toBe(201);
    const prod1 = createProd1.json();
    expect(prod1.stock).toBe(10);

    const createProd2 = await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${tokenA}` },
      payload: {
        name: 'Refresco',
        priceCents: 2500,
        trackStock: true,
        stock: 3,
      },
    });
    expect(createProd2.statusCode).toBe(201);
    const prod2 = createProd2.json();

    // Owner B cannot update, delete, or adjust stock of Owner A's product (404)
    const patchByB = await app.inject({
      method: 'PATCH',
      url: `/business/products/${prod1.id}`,
      headers: { authorization: `Bearer ${tokenB}` },
      payload: { name: 'Hacked' },
    });
    expect(patchByB.statusCode).toBe(404);

    const deleteByB = await app.inject({
      method: 'DELETE',
      url: `/business/products/${prod1.id}`,
      headers: { authorization: `Bearer ${tokenB}` },
    });
    expect(deleteByB.statusCode).toBe(404);

    const stockByB = await app.inject({
      method: 'POST',
      url: `/business/products/${prod1.id}/stock`,
      headers: { authorization: `Bearer ${tokenB}` },
      payload: { delta: -2, reason: 'steal' },
    });
    expect(stockByB.statusCode).toBe(404);

    // Owner A updates prod1 price
    const patchByA = await app.inject({
      method: 'PATCH',
      url: `/business/products/${prod1.id}`,
      headers: { authorization: `Bearer ${tokenA}` },
      payload: { priceCents: 2400 },
    });
    expect(patchByA.statusCode).toBe(200);
    expect(patchByA.json().priceCents).toBe(2400);

    // Stock adjustment: valid decrement
    const adjustOk = await app.inject({
      method: 'POST',
      url: `/business/products/${prod1.id}/stock`,
      headers: { authorization: `Bearer ${tokenA}` },
      payload: { delta: -6, reason: 'Venta mostrador' },
    });
    expect(adjustOk.statusCode).toBe(200);
    expect(adjustOk.json().stock).toBe(4);

    // Verify stock_movements row was written
    const movements = await db
      .select()
      .from(stockMovements)
      .where(eq(stockMovements.productId, prod1.id));
    expect(movements).toHaveLength(1);
    expect(movements[0]?.delta).toBe(-6);
    expect(movements[0]?.reason).toBe('Venta mostrador');

    // Stock adjustment: reject negative resulting stock (4 - 10 = -6)
    const adjustNegative = await app.inject({
      method: 'POST',
      url: `/business/products/${prod1.id}/stock`,
      headers: { authorization: `Bearer ${tokenA}` },
      payload: { delta: -10, reason: 'Merma excesiva' },
    });
    expect(adjustNegative.statusCode).toBe(400);

    // Low stock endpoint (threshold=5 -> both prod2(3) and prod1(4) returned; threshold=3 -> only prod2(3))
    const low5 = await app.inject({
      method: 'GET',
      url: '/business/inventory/low?threshold=5',
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(low5.statusCode).toBe(200);
    expect(low5.json().map((p: { id: string }) => p.id)).toEqual([prod2.id, prod1.id]);

    const low3 = await app.inject({
      method: 'GET',
      url: '/business/inventory/low?threshold=3',
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(low3.statusCode).toBe(200);
    expect(low3.json().map((p: { id: string }) => p.id)).toEqual([prod2.id]);

    // Soft delete prod2 -> hidden from public /businesses/:id/products, still in /business/products with active=false
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/business/products/${prod2.id}`,
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(delRes.statusCode).toBe(200);
    expect(delRes.json().active).toBe(false);

    const publicProds = await app.inject({
      method: 'GET',
      url: `/businesses/${bizA.id}/products`,
    });
    expect(publicProds.statusCode).toBe(200);
    expect(publicProds.json()).toHaveLength(1);
    expect(publicProds.json()[0].id).toBe(prod1.id);

    const ownerProds = await app.inject({
      method: 'GET',
      url: '/business/products',
      headers: { authorization: `Bearer ${tokenA}` },
    });
    expect(ownerProds.statusCode).toBe(200);
    expect(ownerProds.json()).toHaveLength(2);
  });

  it('runs idempotent seed and logs in as demo@paydmewx.mx owning the taco stall', async () => {
    await runSeed();
    await runSeed(); // idempotent second run

    const bizRes = await app.inject({ method: 'GET', url: '/businesses' });
    expect(bizRes.statusCode).toBe(200);
    expect(bizRes.json()).toHaveLength(3);

    const loginRes = await app.inject({
      method: 'POST',
      url: '/auth/login',
      payload: { email: 'demo@paydmewx.mx', password: 'demo1234' },
    });
    expect(loginRes.statusCode).toBe(200);
    const { token } = loginRes.json();

    const meRes = await app.inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(meRes.statusCode).toBe(200);
    expect(meRes.json().business.category).toBe('food');
    expect(meRes.json().business.prepType).toBe('made_to_order');

    const prodsRes = await app.inject({
      method: 'GET',
      url: '/business/products',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(prodsRes.statusCode).toBe(200);
    expect(prodsRes.json().length).toBeGreaterThanOrEqual(4);
    expect(prodsRes.json().length).toBeLessThanOrEqual(6);

    const summaryRes = await app.inject({
      method: 'GET',
      url: '/business/sales/summary',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(summaryRes.statusCode).toBe(200);
    expect(summaryRes.json()).toEqual({
      totalCents: 0,
      orders: 0,
      topProducts: [],
    });
  });
});
