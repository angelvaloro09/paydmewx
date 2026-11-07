import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import { ZodError } from 'zod';
import { runMigrations } from './db/migrate.js';
import { AppError } from './lib/errors.js';
import type { PeyClient } from './lib/pey.js';
import { authRoutes } from './routes/auth.js';
import { businessRoutes } from './routes/business.js';
import { discoveryRoutes } from './routes/discovery.js';
import { healthRoutes } from './routes/health.js';
import { orderRoutes } from './routes/orders.js';

export interface BuildAppOptions {
  pey?: PeyClient;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  await runMigrations();

  const app = Fastify({
    logger: false,
  });

  await app.register(cors, {
    origin: true,
    credentials: true,
  });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof AppError) {
      return reply.status(error.statusCode).send({
        error: {
          code: error.code,
          message: error.message,
        },
      });
    }

    if (error instanceof ZodError) {
      const firstIssue = error.issues[0];
      const pathStr = firstIssue?.path.length ? `${firstIssue.path.join('.')}: ` : '';
      const message = firstIssue
        ? `${pathStr}${firstIssue.message}`
        : 'Invalid request payload';
      return reply.status(400).send({
        error: {
          code: 'VALIDATION_ERROR',
          message,
        },
      });
    }

    const statusCode =
      typeof (error as { statusCode?: number }).statusCode === 'number'
        ? (error as { statusCode: number }).statusCode
        : 500;

    if (statusCode >= 500) {
      console.error(error);
      return reply.status(statusCode).send({
        error: { code: 'INTERNAL_ERROR', message: 'Internal server error' },
      });
    }

    return reply.status(statusCode).send({
      error: {
        code: statusCode === 400 ? 'BAD_REQUEST' : 'REQUEST_ERROR',
        message: error instanceof Error ? error.message : 'Bad request',
      },
    });
  });

  app.setNotFoundHandler((_request, reply) => {
    return reply.status(404).send({
      error: {
        code: 'NOT_FOUND',
        message: 'Route not found',
      },
    });
  });

  await app.register(healthRoutes);
  await app.register(authRoutes);
  await app.register(discoveryRoutes);
  await app.register(businessRoutes);
  await app.register(orderRoutes, { pey: options.pey });

  return app;
}
