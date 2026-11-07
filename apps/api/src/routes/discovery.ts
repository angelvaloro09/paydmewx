import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { categorySchema, prepTypeSchema } from '../db/schema.js';
import {
  getActiveBusinessById,
  listActiveBusinesses,
  listActiveBusinessProducts,
} from '../services/business.service.js';

const discoveryQuerySchema = z.object({
  category: z
    .string()
    .optional()
    .transform((v) => (v === '' ? undefined : v))
    .pipe(categorySchema.optional()),
  prepType: z
    .string()
    .optional()
    .transform((v) => (v === '' ? undefined : v))
    .pipe(prepTypeSchema.optional()),
  q: z.string().optional(),
});

const idParamSchema = z.object({
  id: z.string().min(1),
});

export async function discoveryRoutes(app: FastifyInstance): Promise<void> {
  app.get('/businesses', async (request) => {
    const query = discoveryQuerySchema.parse(request.query ?? {});
    return listActiveBusinesses(query);
  });

  app.get('/businesses/:id', async (request) => {
    const { id } = idParamSchema.parse(request.params);
    return getActiveBusinessById(id);
  });

  app.get('/businesses/:id/products', async (request) => {
    const { id } = idParamSchema.parse(request.params);
    return listActiveBusinessProducts(id);
  });
}
