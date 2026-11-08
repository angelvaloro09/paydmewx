import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../lib/auth.js';
import { AppError } from '../lib/errors.js';
import { defaultLlmClient, type LlmClient } from '../lib/llm.js';
import { runAiAssist } from '../services/ai.service.js';

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 20;

const assistBodySchema = z.object({
  message: z.string().trim().min(1).max(1000),
  history: z
    .array(
      z.object({
        role: z.enum(['user', 'assistant']),
        content: z.string(),
      })
    )
    .max(10)
    .optional(),
});

export interface AiRoutesOptions {
  llm?: LlmClient;
}

export async function aiRoutes(
  app: FastifyInstance,
  options: AiRoutesOptions = {}
): Promise<void> {
  const llmClient = options.llm ?? defaultLlmClient;
  const userRequestTimestamps = new Map<string, number[]>();

  function checkRateLimit(userId: string): void {
    const now = Date.now();
    const cutoff = now - RATE_LIMIT_WINDOW_MS;
    const recent = (userRequestTimestamps.get(userId) ?? []).filter((ts) => ts > cutoff);

    if (recent.length >= RATE_LIMIT_MAX_REQUESTS) {
      userRequestTimestamps.set(userId, recent);
      throw new AppError(
        429,
        'RATE_LIMITED',
        'Demasiadas solicitudes al asistente. Intenta de nuevo en un minuto.'
      );
    }

    recent.push(now);
    userRequestTimestamps.set(userId, recent);
  }

  app.post('/ai/assist', { preHandler: [requireAuth] }, async (request) => {
    const user = request.user!;
    checkRateLimit(user.id);
    const body = assistBodySchema.parse(request.body ?? {});

    return runAiAssist({
      user,
      message: body.message,
      history: body.history,
      llm: llmClient,
    });
  });
}
