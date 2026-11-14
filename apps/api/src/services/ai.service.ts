import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { db } from '../db/index.js';
import {
  businesses,
  type BusinessRow,
  type ProductRow,
} from '../db/schema.js';
import type { PublicUser } from '../lib/auth.js';
import type { LlmClient, LlmMessage, LlmTool } from '../lib/llm.js';
import { listActiveBusinesses, listActiveBusinessProducts } from './business.service.js';
import { createOrder, listOrdersForUser } from './order.service.js';
import {
  adjustProductStock,
  createOwnerProduct,
  getSalesSummary,
  listLowStockProducts,
  listOwnerProducts,
} from './product.service.js';

export type Action =
  | { type: 'order_created'; orderId: string; totalCents: number }
  | { type: 'stock_adjusted'; productId: string; newStock: number }
  | { type: 'product_created'; productId: string };

export interface AssistHistoryItem {
  role: 'user' | 'assistant';
  content: string;
}

export interface AssistInput {
  user: PublicUser;
  message: string;
  history?: AssistHistoryItem[];
  llm: LlmClient;
}

export interface AssistResult {
  reply: string;
  actions: Action[];
}

const MAX_TOOL_ROUNDS = 4;

export function formatCentsDisplay(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function normalizeText(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
}

function stripPluralSuffix(token: string): string {
  if (token.length > 3 && token.endsWith('es')) {
    return token.slice(0, -2);
  }
  if (token.length > 2 && token.endsWith('s')) {
    return token.slice(0, -1);
  }
  return token;
}

function tokenizeNormalized(normText: string): string[] {
  return normText.split(/\s+/).filter(Boolean);
}

function matchesTokenPrefixes(queryNorm: string, productNorm: string): boolean {
  const queryTokens = tokenizeNormalized(queryNorm).map(stripPluralSuffix).filter(Boolean);
  const prodTokens = tokenizeNormalized(productNorm);
  if (queryTokens.length === 0 || prodTokens.length === 0) {
    return false;
  }
  return queryTokens.every((qt) =>
    prodTokens.some((pt) => pt.startsWith(qt) || stripPluralSuffix(pt).startsWith(qt))
  );
}

function matchProductByName(
  activeProducts: ProductRow[],
  queryName: string
): { product?: ProductRow; error?: string } {
  const sellableProducts = activeProducts.filter((p) => p.name !== 'Cobro rapido');
  const normQuery = normalizeText(queryName);
  if (!normQuery) {
    const allNames = sellableProducts.map((p) => p.name).join(', ') || 'ninguno';
    return { error: `Error: Nombre de producto vacio. Candidatos disponibles: ${allNames}` };
  }

  const exactMatches = sellableProducts.filter((p) => normalizeText(p.name) === normQuery);
  if (exactMatches.length === 1) {
    return { product: exactMatches[0]! };
  }
  if (exactMatches.length > 1) {
    const candidates = exactMatches.map((p) => p.name).join(', ');
    return {
      error: `Error: Producto ambiguo "${queryName}". Candidatos: ${candidates}`,
    };
  }

  const prefixMatches = sellableProducts.filter((p) =>
    matchesTokenPrefixes(normQuery, normalizeText(p.name))
  );
  if (prefixMatches.length === 1) {
    return { product: prefixMatches[0]! };
  }
  if (prefixMatches.length > 1) {
    const candidates = prefixMatches.map((p) => p.name).join(', ');
    return {
      error: `Error: Producto ambiguo "${queryName}". Candidatos: ${candidates}`,
    };
  }

  const containsMatches = sellableProducts.filter((p) =>
    normalizeText(p.name).includes(normQuery)
  );
  if (containsMatches.length === 1) {
    return { product: containsMatches[0]! };
  }
  if (containsMatches.length > 1) {
    const candidates = containsMatches.map((p) => p.name).join(', ');
    return {
      error: `Error: Producto ambiguo "${queryName}". Candidatos: ${candidates}`,
    };
  }

  const allCandidates = sellableProducts.map((p) => p.name).join(', ') || 'ninguno';
  return {
    error: `Error: Producto desconocido "${queryName}". Candidatos disponibles: ${allCandidates}`,
  };
}

const recordSaleArgsSchema = z.object({
  items: z
    .array(
      z.object({
        productName: z.string().trim().min(1),
        qty: z.number().int().positive(),
      })
    )
    .min(1),
});

const adjustStockArgsSchema = z.object({
  productName: z.string().trim().min(1),
  delta: z
    .number()
    .int()
    .refine((n) => n !== 0, 'delta cannot be 0'),
  reason: z.string().trim().min(1),
});

const listLowStockArgsSchema = z.object({
  threshold: z.number().int().min(0).optional(),
});

const listProductsArgsSchema = z.object({
  query: z.string().optional(),
});

const salesSummaryArgsSchema = z.object({
  from: z.number().int().optional(),
  to: z.number().int().optional(),
});

const createProductArgsSchema = z.object({
  name: z.string().trim().min(1),
  priceCents: z.number().int().positive(),
  trackStock: z.boolean().optional(),
  stock: z.number().int().min(0).optional(),
});

const businessCategoryEnum = z.enum([
  'food',
  'tailoring',
  'footwear',
  'clothing',
  'department',
  'grocery',
  'services',
  'other',
]);

const searchBusinessesArgsSchema = z.object({
  query: z.string().optional(),
  category: businessCategoryEnum.optional(),
});

const reorderLastArgsSchema = z.object({
  businessId: z.string().trim().min(1).optional(),
});

const OWNER_TOOLS: LlmTool[] = [
  {
    type: 'function',
    function: {
      name: 'list_products',
      description: 'Lista productos activos con precio e inventario (max 20).',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'record_sale',
      description:
        'Registra una venta en mostrador creando una orden pendiente de pago (pending_payment). Nunca cobra dinero.',
      parameters: {
        type: 'object',
        properties: {
          items: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                productName: { type: 'string' },
                qty: { type: 'integer', minimum: 1 },
              },
              required: ['productName', 'qty'],
            },
          },
        },
        required: ['items'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'adjust_stock',
      description: 'Ajusta el inventario de un producto del negocio.',
      parameters: {
        type: 'object',
        properties: {
          productName: { type: 'string' },
          delta: { type: 'integer' },
          reason: { type: 'string' },
        },
        required: ['productName', 'delta', 'reason'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'list_low_stock',
      description: 'Lista los productos activos con bajo inventario.',
      parameters: {
        type: 'object',
        properties: {
          threshold: { type: 'integer', minimum: 0 },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'sales_summary',
      description: 'Obtiene el resumen de ventas pagadas en un rango de tiempo (segundos unix).',
      parameters: {
        type: 'object',
        properties: {
          from: { type: 'integer' },
          to: { type: 'integer' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'create_product',
      description: 'Crea un nuevo producto en el catalogo del negocio (precio en centavos).',
      parameters: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          priceCents: { type: 'integer', minimum: 1 },
          trackStock: { type: 'boolean' },
          stock: { type: 'integer', minimum: 0 },
        },
        required: ['name', 'priceCents'],
      },
    },
  },
];

const CUSTOMER_TOOLS: LlmTool[] = [
  {
    type: 'function',
    function: {
      name: 'search_businesses',
      description: 'Busca negocios activos por texto o categoria (maximo 5).',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string' },
          category: {
            type: 'string',
            enum: [
              'food',
              'tailoring',
              'footwear',
              'clothing',
              'department',
              'grocery',
              'services',
              'other',
            ],
          },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'reorder_last',
      description:
        'Crea una orden pendiente de pago copiando los productos disponibles de la ultima orden del cliente.',
      parameters: {
        type: 'object',
        properties: {
          businessId: { type: 'string' },
        },
      },
    },
  },
];

function sanitizeReply(text: string): string {
  return text
    .replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, '')
    .replace(/\*\*|__|`/g, '')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

function buildSystemPrompt(business: BusinessRow | null): string {
  const today = new Date().toISOString().slice(0, 10);
  const roleDesc = business ? `owner (negocio: ${business.name})` : 'customer (cliente)';
  return [
    'Eres el asistente de PaydMex en CDMX.',
    'Responde en el idioma del usuario de forma breve y directa.',
    'Nunca inventes datos; usa siempre las herramientas disponibles.',
    'Para preguntas de inventario, stock o precios debes llamar a list_products.',
    'Escribe texto plano: sin emojis, sin markdown, sin negritas, maximo 3 frases cortas. Nunca muestres IDs ni codigos internos de ordenes.',
    'Nunca cobras dinero: record_sale solo crea una orden pendiente de pago (pending_payment).',
    `Fecha de hoy: ${today}.`,
    `Rol del usuario: ${roleDesc}.`,
  ].join(' ');
}

async function executeToolCall(params: {
  toolName: string;
  rawArguments: string;
  user: PublicUser;
  business: BusinessRow | null;
  actions: Action[];
}): Promise<string> {
  const { toolName, rawArguments, user, business, actions } = params;

  let parsedJson: unknown;
  try {
    parsedJson = rawArguments.trim() ? JSON.parse(rawArguments) : {};
  } catch {
    return 'Error: Argumentos JSON invalidos para la herramienta.';
  }

  try {
    if (business) {
      switch (toolName) {
        case 'list_products': {
          const parsed = listProductsArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en list_products: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const allProducts = await listOwnerProducts(business.id);
          let activeProducts = allProducts.filter(
            (p) => p.active && p.name !== 'Cobro rapido'
          );
          const normQuery = parsed.data.query ? normalizeText(parsed.data.query) : '';
          if (normQuery) {
            activeProducts = activeProducts.filter((p) => {
              const prodNorm = normalizeText(p.name);
              return (
                prodNorm === normQuery ||
                matchesTokenPrefixes(normQuery, prodNorm) ||
                prodNorm.includes(normQuery)
              );
            });
          }
          return JSON.stringify({
            products: activeProducts.slice(0, 20).map((p) => ({
              name: p.name,
              priceCents: p.priceCents,
              display: formatCentsDisplay(p.priceCents),
              stock: p.trackStock ? p.stock : null,
            })),
          });
        }

        case 'record_sale': {
          const parsed = recordSaleArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en record_sale: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const allProducts = await listOwnerProducts(business.id);
          const activeProducts = allProducts.filter((p) => p.active);

          const resolvedItems: Array<{ productId: string; qty: number }> = [];
          for (const item of parsed.data.items) {
            const match = matchProductByName(activeProducts, item.productName);
            if (match.error || !match.product) {
              return match.error ?? `Error: Producto no encontrado "${item.productName}"`;
            }
            resolvedItems.push({
              productId: match.product.id,
              qty: item.qty,
            });
          }

          const order = await createOrder(user.id, {
            businessId: business.id,
            items: resolvedItems,
          });

          actions.push({
            type: 'order_created',
            orderId: order.id,
            totalCents: order.totalCents,
          });

          return JSON.stringify({
            orderId: order.id,
            totalCents: order.totalCents,
            display: formatCentsDisplay(order.totalCents),
          });
        }

        case 'adjust_stock': {
          const parsed = adjustStockArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en adjust_stock: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const allProducts = await listOwnerProducts(business.id);
          const activeProducts = allProducts.filter((p) => p.active);
          const match = matchProductByName(activeProducts, parsed.data.productName);
          if (match.error || !match.product) {
            return match.error ?? `Error: Producto no encontrado "${parsed.data.productName}"`;
          }

          const updated = await adjustProductStock(business.id, match.product.id, {
            delta: parsed.data.delta,
            reason: parsed.data.reason,
          });

          actions.push({
            type: 'stock_adjusted',
            productId: match.product.id,
            newStock: updated.stock,
          });

          return JSON.stringify({
            productId: match.product.id,
            name: match.product.name,
            newStock: updated.stock,
          });
        }

        case 'list_low_stock': {
          const parsed = listLowStockArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en list_low_stock: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const lowProducts = await listLowStockProducts(
            business.id,
            parsed.data.threshold ?? 5
          );
          return JSON.stringify({
            products: lowProducts.map((p) => ({
              productId: p.id,
              name: p.name,
              stock: p.stock,
              priceCents: p.priceCents,
              display: formatCentsDisplay(p.priceCents),
            })),
          });
        }

        case 'sales_summary': {
          const parsed = salesSummaryArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en sales_summary: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const startOfTodaySec = Math.floor(new Date().setUTCHours(0, 0, 0, 0) / 1000);
          const nowSec = Math.floor(Date.now() / 1000);
          const from = parsed.data.from ?? startOfTodaySec;
          const to = parsed.data.to ?? nowSec;

          const summary = await getSalesSummary(business.id, { from, to });
          return JSON.stringify({
            totalCents: summary.totalCents,
            display: formatCentsDisplay(summary.totalCents),
            orders: summary.orders,
            topProducts: summary.topProducts.map((p) => ({
              productId: p.productId,
              name: p.name,
              qty: p.qty,
              revenueCents: p.revenueCents,
              display: formatCentsDisplay(p.revenueCents),
            })),
          });
        }

        case 'create_product': {
          const parsed = createProductArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en create_product: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const product = await createOwnerProduct(business.id, parsed.data);
          actions.push({
            type: 'product_created',
            productId: product.id,
          });
          return JSON.stringify({
            productId: product.id,
            name: product.name,
            priceCents: product.priceCents,
            display: formatCentsDisplay(product.priceCents),
            trackStock: product.trackStock,
            stock: product.stock,
          });
        }

        default:
          return `Error: Herramienta "${toolName}" no disponible para dueno de negocio.`;
      }
    } else {
      switch (toolName) {
        case 'search_businesses': {
          const parsed = searchBusinessesArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en search_businesses: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const found = await listActiveBusinesses({
            q: parsed.data.query,
            category: parsed.data.category,
          });
          return JSON.stringify({
            businesses: found.slice(0, 5).map((b) => ({
              id: b.id,
              name: b.name,
              category: b.category,
              prepType: b.prepType,
            })),
          });
        }

        case 'reorder_last': {
          const parsed = reorderLastArgsSchema.safeParse(parsedJson);
          if (!parsed.success) {
            return `Error de validacion en reorder_last: ${parsed.error.issues[0]?.message ?? 'argumentos invalidos'}`;
          }
          const customerOrders = await listOrdersForUser(user.id, { role: 'customer' });
          const filtered = parsed.data.businessId
            ? customerOrders.filter((o) => o.businessId === parsed.data.businessId)
            : customerOrders;

          const lastOrder = filtered[0];
          if (!lastOrder) {
            return 'Error: No se encontro una orden anterior para repetir.';
          }

          const activeProducts = await listActiveBusinessProducts(lastOrder.businessId);
          const activeById = new Map(activeProducts.map((p) => [p.id, p]));

          const availableItems: Array<{ productId: string; qty: number }> = [];
          for (const item of lastOrder.items) {
            const prod = activeById.get(item.productId);
            if (!prod || !prod.active) {
              continue;
            }
            if (prod.trackStock && prod.stock < item.qty) {
              continue;
            }
            availableItems.push({
              productId: prod.id,
              qty: item.qty,
            });
          }

          if (availableItems.length === 0) {
            return 'Error: Ninguno de los productos de la ultima orden esta disponible actualmente.';
          }

          const newOrder = await createOrder(user.id, {
            businessId: lastOrder.businessId,
            items: availableItems,
          });

          actions.push({
            type: 'order_created',
            orderId: newOrder.id,
            totalCents: newOrder.totalCents,
          });

          return JSON.stringify({
            orderId: newOrder.id,
            totalCents: newOrder.totalCents,
            display: formatCentsDisplay(newOrder.totalCents),
          });
        }

        default:
          return `Error: Herramienta "${toolName}" no permitida para clientes sin negocio.`;
      }
    }
  } catch (err) {
    return err instanceof Error ? `Error: ${err.message}` : 'Error al ejecutar la herramienta.';
  }
}

export async function runAiAssist(input: AssistInput): Promise<AssistResult> {
  const [business] = await db
    .select()
    .from(businesses)
    .where(eq(businesses.ownerId, input.user.id))
    .limit(1);

  const userBusiness = business ?? null;
  const tools = userBusiness ? OWNER_TOOLS : CUSTOMER_TOOLS;
  const actions: Action[] = [];

  const messages: LlmMessage[] = [
    {
      role: 'system',
      content: buildSystemPrompt(userBusiness),
    },
  ];

  for (const entry of input.history ?? []) {
    messages.push({
      role: entry.role,
      content: entry.content,
    });
  }

  messages.push({
    role: 'user',
    content: input.message,
  });

  let lastContent: string | null = null;

  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const response = await input.llm.chat(messages, tools);
    if (response.content) {
      lastContent = response.content;
    }

    if (!response.toolCalls || response.toolCalls.length === 0) {
      return {
        reply: sanitizeReply(response.content ?? ''),
        actions,
      };
    }

    messages.push({
      role: 'assistant',
      content: response.content,
      tool_calls: response.toolCalls.map((tc) => ({
        id: tc.id,
        type: 'function',
        function: {
          name: tc.name,
          arguments: tc.arguments,
        },
      })),
    });

    for (const tc of response.toolCalls) {
      const toolOutput = await executeToolCall({
        toolName: tc.name,
        rawArguments: tc.arguments,
        user: input.user,
        business: userBusiness,
        actions,
      });

      messages.push({
        role: 'tool',
        tool_call_id: tc.id,
        name: tc.name,
        content: toolOutput,
      });
    }
  }

  return {
    reply: sanitizeReply(lastContent ?? '') || 'Listo.',
    actions,
  };
}
