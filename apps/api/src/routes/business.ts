import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, requireBusiness } from '../lib/auth.js';
import {
  adjustProductStock,
  createOwnerProduct,
  getSalesSummary,
  listLowStockProducts,
  listOwnerProducts,
  softDeleteOwnerProduct,
  updateOwnerProduct,
} from '../services/product.service.js';

const createProductBodySchema = z.object({
  name: z.string().min(1),
  priceCents: z.number().int().nonnegative(),
  trackStock: z.boolean().optional().default(true),
  stock: z.number().int().nonnegative().optional().default(0),
  prepMinutes: z.number().int().positive().nullable().optional(),
  imageUrl: z.string().nullable().optional(),
});

const updateProductBodySchema = z.object({
  name: z.string().min(1).optional(),
  priceCents: z.number().int().nonnegative().optional(),
  trackStock: z.boolean().optional(),
  stock: z.number().int().nonnegative().optional(),
  prepMinutes: z.number().int().positive().nullable().optional(),
  imageUrl: z.string().nullable().optional(),
  active: z.boolean().optional(),
});

const adjustStockBodySchema = z.object({
  delta: z.number().int(),
  reason: z.string().min(1),
});

const idParamSchema = z.object({
  id: z.string().min(1),
});

const lowStockQuerySchema = z.object({
  threshold: z
    .union([z.string(), z.number()])
    .optional()
    .transform((v) => (v === undefined || v === '' ? 5 : Number(v)))
    .pipe(z.number().int().nonnegative()),
});

const salesSummaryQuerySchema = z.object({
  from: z
    .union([z.string(), z.number()])
    .optional()
    .transform((v) => (v === undefined || v === '' ? undefined : Number(v)))
    .pipe(z.number().int().optional()),
  to: z
    .union([z.string(), z.number()])
    .optional()
    .transform((v) => (v === undefined || v === '' ? undefined : Number(v)))
    .pipe(z.number().int().optional()),
});

export async function businessRoutes(app: FastifyInstance): Promise<void> {
  const ownerGuard = [requireAuth, requireBusiness];

  app.get('/business/products', { preHandler: ownerGuard }, async (request) => {
    return listOwnerProducts(request.business!.id);
  });

  app.post('/business/products', { preHandler: ownerGuard }, async (request, reply) => {
    const body = createProductBodySchema.parse(request.body);
    const product = await createOwnerProduct(request.business!.id, body);
    return reply.status(201).send(product);
  });

  app.patch('/business/products/:id', { preHandler: ownerGuard }, async (request) => {
    const { id } = idParamSchema.parse(request.params);
    const body = updateProductBodySchema.parse(request.body);
    return updateOwnerProduct(request.business!.id, id, body);
  });

  app.delete('/business/products/:id', { preHandler: ownerGuard }, async (request) => {
    const { id } = idParamSchema.parse(request.params);
    return softDeleteOwnerProduct(request.business!.id, id);
  });

  app.post('/business/products/:id/stock', { preHandler: ownerGuard }, async (request) => {
    const { id } = idParamSchema.parse(request.params);
    const body = adjustStockBodySchema.parse(request.body);
    return adjustProductStock(request.business!.id, id, body);
  });

  app.get('/business/inventory/low', { preHandler: ownerGuard }, async (request) => {
    const { threshold } = lowStockQuerySchema.parse(request.query ?? {});
    return listLowStockProducts(request.business!.id, threshold);
  });

  app.get('/business/sales/summary', { preHandler: ownerGuard }, async (request) => {
    const query = salesSummaryQuerySchema.parse(request.query ?? {});
    return getSalesSummary(request.business!.id, query);
  });
}
