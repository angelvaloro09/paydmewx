import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { eq } from 'drizzle-orm';
import { buildApp } from '../app.js';
import { client, db } from '../db/index.js';
import { orders, products } from '../db/schema.js';
import {
  createLlmClient,
  type LlmChatResponse,
  type LlmClient,
  type LlmMessage,
  type LlmTool,
} from '../lib/llm.js';

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

describe('AI Assistant API (POST /ai/assist - T14)', () => {
  let app: FastifyInstance;
  const chatMock = vi.fn<(messages: LlmMessage[], tools: LlmTool[]) => Promise<LlmChatResponse>>();
  const fakeLlm: LlmClient = {
    chat: (messages, tools) => chatMock(messages, tools),
  };

  beforeAll(async () => {
    app = await buildApp({ llm: fakeLlm });
    await app.ready();
  });

  beforeEach(async () => {
    await clearDatabase();
    chatMock.mockReset();
  });

  afterAll(async () => {
    await app.close();
  });

  async function setupOwnerAndCustomer() {
    const ownerReg = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: 'owner-ai@example.com',
        password: 'password123',
        name: 'Taquero Owner',
      },
    });
    const ownerToken = ownerReg.json().token as string;
    const ownerId = ownerReg.json().user.id as string;

    const bizRes = await app.inject({
      method: 'POST',
      url: '/me/business',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: 'Tacos El Paisa',
        category: 'food',
        prepType: 'made_to_order',
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
        stock: 20,
      },
    });
    const prod1 = prod1Res.json();

    const prod2Res = await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: 'Agua de jamaica',
        priceCents: 3500,
        trackStock: true,
        stock: 3,
      },
    });
    const prod2 = prod2Res.json();

    const custReg = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: 'cust-ai@example.com',
        password: 'password123',
        name: 'Cliente CDMX',
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

  it('returns 401 without token, 503 when not configured (default client with empty key), and 429 on the 21st call', async () => {
    const unauthRes = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      payload: { message: 'Hola' },
    });
    expect(unauthRes.statusCode).toBe(401);

    // 503 when not configured using default client with empty key
    const unconfiguredApp = await buildApp({
      llm: createLlmClient({ apiKey: '', model: '' }),
    });
    await unconfiguredApp.ready();
    try {
      const regRes = await unconfiguredApp.inject({
        method: 'POST',
        url: '/auth/register',
        payload: {
          email: 'unconf@example.com',
          password: 'password123',
          name: 'Unconfigured User',
        },
      });
      const token = regRes.json().token as string;

      const res503 = await unconfiguredApp.inject({
        method: 'POST',
        url: '/ai/assist',
        headers: { authorization: `Bearer ${token}` },
        payload: { message: 'Vende 2 tacos' },
      });
      expect(res503.statusCode).toBe(503);
      expect(res503.json().error.code).toBe('AI_NOT_CONFIGURED');
    } finally {
      await unconfiguredApp.close();
    }

    // 429 on the 21st call within 60s for the same user
    const rateReg = await app.inject({
      method: 'POST',
      url: '/auth/register',
      payload: {
        email: 'ratelimit@example.com',
        password: 'password123',
        name: 'Rate Limit User',
      },
    });
    const rateToken = rateReg.json().token as string;

    chatMock.mockResolvedValue({
      content: 'Respuesta breve',
      toolCalls: [],
    });

    for (let i = 0; i < 20; i++) {
      const okRes = await app.inject({
        method: 'POST',
        url: '/ai/assist',
        headers: { authorization: `Bearer ${rateToken}` },
        payload: { message: `Mensaje ${i + 1}` },
      });
      expect(okRes.statusCode).toBe(200);
    }

    const res429 = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${rateToken}` },
      payload: { message: 'Mensaje 21' },
    });
    expect(res429.statusCode).toBe(429);
    expect(res429.json().error.code).toBe('RATE_LIMITED');
  });

  it('owner flow: fake LLM calls record_sale for "2 Taco al pastor", then returns final text; creates walk-in order and returns order_created action', async () => {
    const { ownerToken, business } = await setupOwnerAndCustomer();

    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_sale_1',
            name: 'record_sale',
            arguments: JSON.stringify({
              items: [{ productName: 'Taco al pastor', qty: 2 }],
            }),
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'Listo, cree la orden por $50.00 pendiente de cobro.',
        toolCalls: [],
      });

    const res = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        message: 'Cobrame 2 tacos al pastor',
      },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.reply).toBe('Listo, cree la orden por $50.00 pendiente de cobro.');
    expect(body.actions).toHaveLength(1);
    expect(body.actions[0]).toMatchObject({
      type: 'order_created',
      totalCents: 5000,
    });

    const createdOrderId = body.actions[0].orderId as string;
    const [dbOrder] = await db.select().from(orders).where(eq(orders.id, createdOrderId));
    expect(dbOrder).toBeDefined();
    expect(dbOrder?.businessId).toBe(business.id);
    expect(dbOrder?.customerId).toBeNull();
    expect(dbOrder?.status).toBe('pending_payment');
    expect(dbOrder?.totalCents).toBe(5000);

    // Check that tool result sent to LLM on round 2 had integer centavos + display string
    const secondCallMessages = chatMock.mock.calls[1]?.[0] ?? [];
    const toolMessage = secondCallMessages.find((m) => m.role === 'tool');
    expect(toolMessage).toBeDefined();
    if (toolMessage && toolMessage.role === 'tool') {
      const parsedToolOutput = JSON.parse(toolMessage.content);
      expect(parsedToolOutput).toEqual({
        orderId: createdOrderId,
        totalCents: 5000,
        display: '$50.00',
      });
    }
  });

  it('adjust_stock changes stock; unknown product name returns an error to the model and no order is created', async () => {
    const { ownerToken, prod1 } = await setupOwnerAndCustomer();

    // 1. adjust_stock changes stock
    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_adj_1',
            name: 'adjust_stock',
            arguments: JSON.stringify({
              productName: 'taco al pastor',
              delta: 5,
              reason: 'restock',
            }),
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'Stock actualizado a 25 unidades.',
        toolCalls: [],
      });

    const adjRes = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { message: 'Agrega 5 tacos al pastor al inventario' },
    });

    expect(adjRes.statusCode).toBe(200);
    expect(adjRes.json().actions).toEqual([
      {
        type: 'stock_adjusted',
        productId: prod1.id,
        newStock: 25,
      },
    ]);

    const [updatedProd] = await db.select().from(products).where(eq(products.id, prod1.id));
    expect(updatedProd?.stock).toBe(25);

    // 2. unknown product name in record_sale returns error to model and no order is created
    chatMock.mockReset();
    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_unknown_1',
            name: 'record_sale',
            arguments: JSON.stringify({
              items: [{ productName: 'Torta de Tamal', qty: 1 }],
            }),
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'No encontre Torta de Tamal. Tenemos Taco al Pastor y Agua de jamaica.',
        toolCalls: [],
      });

    const unknownRes = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { message: 'Vende una torta de tamal' },
    });

    expect(unknownRes.statusCode).toBe(200);
    expect(unknownRes.json().actions).toEqual([]);

    const allOrders = await db.select().from(orders);
    expect(allOrders).toHaveLength(0);

    const round2Messages = chatMock.mock.calls[1]?.[0] ?? [];
    const errToolMsg = round2Messages.find((m) => m.role === 'tool');
    expect(errToolMsg).toBeDefined();
    if (errToolMsg && errToolMsg.role === 'tool') {
      expect(errToolMsg.content).toContain('Error:');
      expect(errToolMsg.content).toContain('Taco al Pastor');
    }
  });

  it('customer cannot call owner tools (tool not offered and returns error if invoked) and can reorder_last', async () => {
    const { customerToken, business, prod1 } = await setupOwnerAndCustomer();

    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_illegal_owner_tool',
            name: 'record_sale',
            arguments: JSON.stringify({
              items: [{ productName: 'Taco al Pastor', qty: 1 }],
            }),
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'Solo puedes buscar negocios o repetir tu ultimo pedido.',
        toolCalls: [],
      });

    const res = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: { message: 'Registra una venta' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().actions).toEqual([]);

    // Verify owner tools were NOT offered in tools parameter
    const offeredTools = chatMock.mock.calls[0]?.[1] ?? [];
    const offeredNames = offeredTools.map((t) => t.function.name);
    expect(offeredNames).toEqual(['search_businesses', 'reorder_last']);
    expect(offeredNames).not.toContain('record_sale');

    // Verify tool output returned an error to the model
    const secondCallMessages = chatMock.mock.calls[1]?.[0] ?? [];
    const toolMsg = secondCallMessages.find((m) => m.role === 'tool');
    expect(toolMsg?.content).toContain('Error:');

    const allOrders = await db.select().from(orders);
    expect(allOrders).toHaveLength(0);

    // Customer reorder_last works when customer has a previous order
    await app.inject({
      method: 'POST',
      url: '/orders',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: {
        businessId: business.id,
        items: [{ productId: prod1.id, qty: 2 }],
      },
    });

    chatMock.mockReset();
    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_reorder_1',
            name: 'reorder_last',
            arguments: '{}',
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'Repeti tu ultimo pedido.',
        toolCalls: [],
      });

    const reorderRes = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${customerToken}` },
      payload: { message: 'Repite mi ultimo pedido' },
    });
    expect(reorderRes.statusCode).toBe(200);
    expect(reorderRes.json().actions).toHaveLength(1);
    expect(reorderRes.json().actions[0]).toMatchObject({
      type: 'order_created',
      totalCents: 5000,
    });
  });

  it('stops the tool loop after 4 rounds when the model keeps returning tool calls', async () => {
    const { ownerToken } = await setupOwnerAndCustomer();

    let callCount = 0;
    chatMock.mockImplementation(async () => {
      callCount += 1;
      return {
        content: `Paso ${callCount}`,
        toolCalls: [
          {
            id: `call_loop_${callCount}`,
            name: 'list_low_stock',
            arguments: JSON.stringify({ threshold: 5 }),
          },
        ],
      };
    });

    const res = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { message: 'Revisa el inventario en bucle' },
    });

    expect(res.statusCode).toBe(200);
    expect(chatMock).toHaveBeenCalledTimes(4);
    expect(res.json().reply).toBe('Paso 4');
  });

  it('list_products returns names, display price, stock (null when trackStock is false) and hides Cobro rapido', async () => {
    const { ownerToken } = await setupOwnerAndCustomer();

    // Add Cobro rapido and an untracked product
    await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: 'Cobro rapido',
        priceCents: 100,
        trackStock: false,
      },
    });
    await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: 'Salsa extra',
        priceCents: 1000,
        trackStock: false,
        stock: 99,
      },
    });

    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_list_prod_1',
            name: 'list_products',
            arguments: '{}',
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'Tienes Taco al Pastor ($25.00, 20), Agua de jamaica ($35.00, 3) y Salsa extra ($10.00).',
        toolCalls: [],
      });

    const res = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { message: 'Que productos tengo y cuanto stock hay?' },
    });

    expect(res.statusCode).toBe(200);
    const secondCallMessages = chatMock.mock.calls[1]?.[0] ?? [];
    const toolMessage = secondCallMessages.find((m) => m.role === 'tool');
    expect(toolMessage).toBeDefined();
    if (toolMessage && toolMessage.role === 'tool') {
      const parsed = JSON.parse(toolMessage.content) as {
        products: Array<{ name: string; priceCents: number; display: string; stock: number | null }>;
      };
      expect(parsed.products.map((p) => p.name)).not.toContain('Cobro rapido');
      expect(parsed.products).toEqual([
        { name: 'Taco al Pastor', priceCents: 2500, display: '$25.00', stock: 20 },
        { name: 'Agua de jamaica', priceCents: 3500, display: '$35.00', stock: 3 },
        { name: 'Salsa extra', priceCents: 1000, display: '$10.00', stock: null },
      ]);
    }
  });

  it('matcher: "tacos" matches "Taco al Pastor"; ambiguous query returns candidate list and creates nothing; unknown lists available names', async () => {
    const { ownerToken } = await setupOwnerAndCustomer();

    // 1. "tacos" matches "Taco al Pastor"
    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_plural_1',
            name: 'record_sale',
            arguments: JSON.stringify({
              items: [{ productName: 'tacos', qty: 2 }],
            }),
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'Orden creada por $50.00.',
        toolCalls: [],
      });

    const pluralRes = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { message: 'Vende 2 tacos' },
    });
    expect(pluralRes.statusCode).toBe(200);
    expect(pluralRes.json().actions).toHaveLength(1);
    expect(pluralRes.json().actions[0]).toMatchObject({
      type: 'order_created',
      totalCents: 5000,
    });

    // Add second taco product to make "tacos" ambiguous
    await app.inject({
      method: 'POST',
      url: '/business/products',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: {
        name: 'Taco de Suadero',
        priceCents: 2800,
        trackStock: true,
        stock: 15,
      },
    });

    // 2. Ambiguous query returns candidate list and creates nothing
    chatMock.mockReset();
    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_ambig_1',
            name: 'record_sale',
            arguments: JSON.stringify({
              items: [{ productName: 'tacos', qty: 1 }],
            }),
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'Cual taco quieres: Taco al Pastor o Taco de Suadero?',
        toolCalls: [],
      });

    const ambigRes = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { message: 'Vende 1 taco' },
    });
    expect(ambigRes.statusCode).toBe(200);
    expect(ambigRes.json().actions).toEqual([]);

    const ambigRound2 = chatMock.mock.calls[1]?.[0] ?? [];
    const ambigToolMsg = ambigRound2.find((m) => m.role === 'tool');
    expect(ambigToolMsg?.content).toContain('Taco al Pastor');
    expect(ambigToolMsg?.content).toContain('Taco de Suadero');

    const ordersAfterAmbig = await db.select().from(orders);
    expect(ordersAfterAmbig).toHaveLength(1); // Only the first order from step 1

    // 3. Unknown product lists available names
    chatMock.mockReset();
    chatMock
      .mockResolvedValueOnce({
        content: null,
        toolCalls: [
          {
            id: 'call_unk_1',
            name: 'record_sale',
            arguments: JSON.stringify({
              items: [{ productName: 'quesadillas', qty: 1 }],
            }),
          },
        ],
      })
      .mockResolvedValueOnce({
        content: 'No tenemos quesadillas.',
        toolCalls: [],
      });

    const unkRes = await app.inject({
      method: 'POST',
      url: '/ai/assist',
      headers: { authorization: `Bearer ${ownerToken}` },
      payload: { message: 'Vende 1 quesadilla' },
    });
    expect(unkRes.statusCode).toBe(200);
    expect(unkRes.json().actions).toEqual([]);
    const unkRound2 = chatMock.mock.calls[1]?.[0] ?? [];
    const unkToolMsg = unkRound2.find((m) => m.role === 'tool');
    expect(unkToolMsg?.content).toContain('Taco al Pastor');
    expect(unkToolMsg?.content).toContain('Agua de jamaica');
    expect(unkToolMsg?.content).toContain('Taco de Suadero');
  });

  it('llm.ts: 429 then 200 succeeds; 429 twice throws LLM_BUSY; 500 throws LLM_ERROR without leaking upstream body', async () => {
    // 1. 429 then 200 succeeds
    const fetch429Then200 = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ error: { message: 'Rate limit reached, try again in 10ms' } }),
          { status: 429 }
        )
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            choices: [{ message: { content: 'Hola tras reintento', tool_calls: [] } }],
          }),
          { status: 200, headers: { 'Content-Type': 'application/json' } }
        )
      );

    const clientRetryOk = createLlmClient({
      baseUrl: 'https://fake.llm/v1',
      apiKey: 'fake-key',
      model: 'fake-model',
      fetch: fetch429Then200,
    });

    const okResult = await clientRetryOk.chat([{ role: 'user', content: 'Hola' }], []);
    expect(okResult.content).toBe('Hola tras reintento');
    expect(fetch429Then200).toHaveBeenCalledTimes(2);

    // 2. 429 twice -> LLM_BUSY (503)
    const fetch429Twice = vi.fn<typeof fetch>().mockImplementation(async () =>
      new Response(JSON.stringify({ error: { message: 'try again in 5ms' } }), {
        status: 429,
        headers: { 'retry-after': '0.005' },
      })
    );

    const clientBusy = createLlmClient({
      baseUrl: 'https://fake.llm/v1',
      apiKey: 'fake-key',
      model: 'fake-model',
      fetch: fetch429Twice,
    });

    await expect(clientBusy.chat([{ role: 'user', content: 'Hola' }], [])).rejects.toMatchObject({
      statusCode: 503,
      code: 'LLM_BUSY',
      message: 'El asistente esta ocupado, intenta de nuevo en unos segundos',
    });
    expect(fetch429Twice).toHaveBeenCalledTimes(2);

    // 3. 500 -> LLM_ERROR (502) with generic message and upstream body not leaked
    const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    try {
      const secretOrgBody = JSON.stringify({
        error: { message: 'Internal error for org_secret_999999' },
      });
      const fetch500 = vi
        .fn<typeof fetch>()
        .mockResolvedValueOnce(new Response(secretOrgBody, { status: 500 }));

      const client500 = createLlmClient({
        baseUrl: 'https://fake.llm/v1',
        apiKey: 'fake-key',
        model: 'fake-model',
        fetch: fetch500,
      });

      let caughtError: unknown;
      try {
        await client500.chat([{ role: 'user', content: 'Hola' }], []);
      } catch (err) {
        caughtError = err;
      }

      expect(caughtError).toMatchObject({
        statusCode: 502,
        code: 'LLM_ERROR',
        message: 'No pudimos contactar al asistente',
      });
      expect((caughtError as Error).message).not.toContain('org_secret_999999');
      expect(errSpy).toHaveBeenCalledWith('LLM upstream error: HTTP 500');
    } finally {
      errSpy.mockRestore();
    }
  });
});
