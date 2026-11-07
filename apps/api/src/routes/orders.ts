import crypto from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { orderStatusSchema, type OrderStatus } from '../db/schema.js';
import { requireAuth } from '../lib/auth.js';
import { AppError } from '../lib/errors.js';
import { defaultPeyClient, type PeyClient } from '../lib/pey.js';
import {
  createOrder,
  getOrderForUser,
  listOrdersForUser,
  payOrder,
  processPeyWebhookEvent,
  simulateOrderPaid,
  updateOrderStatus,
} from '../services/order.service.js';

const WEBHOOK_TOLERANCE_SECONDS = 5 * 60;

const createOrderBodySchema = z.object({
  businessId: z.string().min(1),
  items: z
    .array(
      z.object({
        productId: z.string().min(1),
        qty: z.number().int().positive(),
      })
    )
    .min(1),
  note: z.string().nullable().optional(),
});

const orderIdParamSchema = z.object({
  id: z.string().min(1),
});

const listOrdersQuerySchema = z.object({
  role: z.enum(['customer', 'business']).optional(),
  status: z
    .string()
    .optional()
    .transform((v) => (v === undefined || v === '' ? undefined : v))
    .pipe(orderStatusSchema.optional()),
});

const updateStatusBodySchema = z.object({
  status: z.string().min(1),
});

export function verifyStandardWebhookSignature(params: {
  webhookId: string | undefined;
  webhookTimestamp: string | undefined;
  webhookSignature: string | undefined;
  rawBody: string;
  secret: string | undefined;
  nowSec?: number;
}): { webhookId: string } {
  const secret = params.secret?.trim();
  if (!secret) {
    throw new AppError(503, 'WEBHOOK_NOT_CONFIGURED', 'PEY_WEBHOOK_SECRET is not configured');
  }

  const webhookId = params.webhookId?.trim();
  const webhookTimestamp = params.webhookTimestamp?.trim();
  const webhookSignature = params.webhookSignature?.trim();

  if (!webhookId || !webhookTimestamp || !webhookSignature) {
    throw new AppError(401, 'INVALID_SIGNATURE', 'Missing Standard Webhooks headers');
  }

  if (!/^\d+$/.test(webhookTimestamp)) {
    throw new AppError(401, 'INVALID_SIGNATURE', 'Invalid webhook-timestamp header');
  }

  const timestampSec = Number(webhookTimestamp);
  const nowSec = params.nowSec ?? Math.floor(Date.now() / 1000);
  if (
    !Number.isFinite(timestampSec) ||
    Math.abs(nowSec - timestampSec) > WEBHOOK_TOLERANCE_SECONDS
  ) {
    throw new AppError(401, 'INVALID_SIGNATURE', 'Webhook timestamp outside 5-minute tolerance');
  }

  const rawSecret = secret.startsWith('whsec_') ? secret.slice('whsec_'.length) : secret;
  const secretBytes = Buffer.from(rawSecret, 'base64');

  const signedContent = `${webhookId}.${webhookTimestamp}.${params.rawBody}`;
  const expectedBase64 = crypto
    .createHmac('sha256', secretBytes)
    .update(signedContent, 'utf8')
    .digest('base64');
  const expectedBuffer = Buffer.from(expectedBase64, 'utf8');

  const parts = webhookSignature.split(/\s+/);
  let matched = false;

  for (const part of parts) {
    if (!part.startsWith('v1,')) {
      continue;
    }
    const candidateSig = part.slice(3);
    if (!candidateSig) {
      continue;
    }
    const candidateBuffer = Buffer.from(candidateSig, 'utf8');
    if (
      candidateBuffer.length === expectedBuffer.length &&
      crypto.timingSafeEqual(candidateBuffer, expectedBuffer)
    ) {
      matched = true;
      break;
    }
  }

  if (!matched) {
    throw new AppError(401, 'INVALID_SIGNATURE', 'Webhook signature verification failed');
  }

  return { webhookId };
}

export interface OrderRoutesOptions {
  pey?: PeyClient;
}

export async function orderRoutes(
  app: FastifyInstance,
  options: OrderRoutesOptions = {}
): Promise<void> {
  const peyClient = options.pey ?? defaultPeyClient;

  app.post('/orders', { preHandler: [requireAuth] }, async (request, reply) => {
    const body = createOrderBodySchema.parse(request.body);
    const order = await createOrder(request.user!.id, body);
    return reply.status(201).send(order);
  });

  app.get('/orders', { preHandler: [requireAuth] }, async (request) => {
    const query = listOrdersQuerySchema.parse(request.query ?? {});
    return listOrdersForUser(request.user!.id, query);
  });

  app.get('/orders/:id', { preHandler: [requireAuth] }, async (request) => {
    const { id } = orderIdParamSchema.parse(request.params);
    return getOrderForUser(request.user!.id, id);
  });

  app.patch('/orders/:id/status', { preHandler: [requireAuth] }, async (request) => {
    const { id } = orderIdParamSchema.parse(request.params);
    const { status } = updateStatusBodySchema.parse(request.body);
    const parsedStatus = orderStatusSchema.safeParse(status);
    if (!parsedStatus.success) {
      throw new AppError(409, 'INVALID_TRANSITION', `Invalid order status: ${status}`);
    }
    return updateOrderStatus(request.user!.id, id, parsedStatus.data as OrderStatus);
  });

  app.post('/orders/:id/pay', { preHandler: [requireAuth] }, async (request) => {
    const { id } = orderIdParamSchema.parse(request.params);
    return payOrder(request.user!.id, id, peyClient);
  });

  // Dev-only helper: explicit opt-in (never enabled by default), never in production.
  const devRoutesEnabled =
    process.env.NODE_ENV !== 'production' &&
    (process.env.ENABLE_DEV_ROUTES === 'true' ||
      process.env.NODE_ENV === 'test' ||
      Boolean(process.env.VITEST));

  if (devRoutesEnabled) {
    app.post('/dev/orders/:id/simulate-paid', async (request) => {
      const { id } = orderIdParamSchema.parse(request.params);
      return simulateOrderPaid(id);
    });
  }

  await app.register(async function peyWebhookPlugin(webhookApp) {
    webhookApp.addContentTypeParser(
      'application/json',
      { parseAs: 'string' },
      (_req, body, done) => {
        done(null, typeof body === 'string' ? body : String(body));
      }
    );

    webhookApp.post('/webhooks/pey', async (request) => {
      const rawBody = typeof request.body === 'string' ? request.body : '';
      const secret = process.env.PEY_WEBHOOK_SECRET ?? config.PEY_WEBHOOK_SECRET;

      const webhookIdHeader =
        typeof request.headers['webhook-id'] === 'string'
          ? request.headers['webhook-id']
          : undefined;
      const webhookTimestampHeader =
        typeof request.headers['webhook-timestamp'] === 'string'
          ? request.headers['webhook-timestamp']
          : undefined;
      const webhookSignatureHeader =
        typeof request.headers['webhook-signature'] === 'string'
          ? request.headers['webhook-signature']
          : undefined;

      const { webhookId } = verifyStandardWebhookSignature({
        webhookId: webhookIdHeader,
        webhookTimestamp: webhookTimestampHeader,
        webhookSignature: webhookSignatureHeader,
        rawBody,
        secret,
      });

      let payload: Record<string, unknown>;
      try {
        const parsed = JSON.parse(rawBody);
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
          throw new Error('Webhook payload must be a JSON object');
        }
        payload = parsed as Record<string, unknown>;
      } catch {
        throw new AppError(400, 'BAD_REQUEST', 'Invalid JSON webhook body');
      }

      return processPeyWebhookEvent(webhookId, payload);
    });
  });
}
