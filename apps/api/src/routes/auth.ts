import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { categorySchema, prepTypeSchema } from '../db/schema.js';
import { requireAuth } from '../lib/auth.js';
import { getProfile, loginUser, registerUser } from '../services/auth.service.js';
import {
  createBusinessForUser,
  updateBusinessForUser,
} from '../services/business.service.js';

const registerBodySchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  name: z.string().min(1),
});

const loginBodySchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const createBusinessBodySchema = z.object({
  name: z.string().min(1),
  category: categorySchema,
  prepType: prepTypeSchema,
  description: z.string().nullable().optional(),
  address: z.string().nullable().optional(),
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
});

const updateBusinessBodySchema = z.object({
  name: z.string().min(1).optional(),
  category: categorySchema.optional(),
  prepType: prepTypeSchema.optional(),
  description: z.string().nullable().optional(),
  address: z.string().nullable().optional(),
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
  active: z.boolean().optional(),
  clabe: z.string().optional(),
});

export async function authRoutes(app: FastifyInstance): Promise<void> {
  app.post('/auth/register', async (request, reply) => {
    const body = registerBodySchema.parse(request.body);
    const result = await registerUser(body);
    return reply.status(201).send(result);
  });

  app.post('/auth/login', async (request) => {
    const body = loginBodySchema.parse(request.body);
    return loginUser(body);
  });

  app.get('/me', { preHandler: [requireAuth] }, async (request) => {
    return getProfile(request.user!.id);
  });

  app.post('/me/business', { preHandler: [requireAuth] }, async (request, reply) => {
    const body = createBusinessBodySchema.parse(request.body);
    const business = await createBusinessForUser(request.user!.id, body);
    return reply.status(201).send(business);
  });

  app.patch('/me/business', { preHandler: [requireAuth] }, async (request) => {
    const body = updateBusinessBodySchema.parse(request.body);
    return updateBusinessForUser(request.user!.id, body);
  });
}
