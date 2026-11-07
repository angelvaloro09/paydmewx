import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import { z } from 'zod';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const isTest =
  process.env.NODE_ENV === 'test' ||
  process.env.VITEST === 'true' ||
  Boolean(process.env.VITEST);

if (!isTest) {
  const envCandidates = [
    path.resolve(process.cwd(), '.env'),
    path.resolve(__dirname, '../.env'),
    path.resolve(__dirname, '../../../.env'),
  ];

  for (const candidate of envCandidates) {
    if (fs.existsSync(candidate)) {
      dotenv.config({ path: candidate });
    }
  }
}

const envSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8787),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z
    .string()
    .min(1)
    .default(isTest ? 'file::memory:' : 'file:./dev.db'),
  DATABASE_AUTH_TOKEN: z.string().optional(),
  JWT_SECRET: z
    .string()
    .min(1)
    .default('paydmewx-test-jwt-secret-do-not-use-in-prod'),
  PEY_BASE_URL: z.string().default('https://api.pey.mx'),
  PEY_API_KEY: z.string().optional(),
  PEY_WEBHOOK_SECRET: z.string().optional(),
  PEY_TEST_AMOUNT_OVERRIDE: z.string().optional(),
  LLM_BASE_URL: z.string().default('https://openrouter.ai/api/v1'),
  LLM_API_KEY: z.string().optional(),
  LLM_MODEL: z.string().optional(),
});

export type AppConfig = z.infer<typeof envSchema>;

const INSECURE_JWT_SECRETS = new Set([
  'change-me',
  'paydmewx-test-jwt-secret-do-not-use-in-prod',
]);

export function loadConfig(overrides?: Record<string, string | undefined>): AppConfig {
  const merged: Record<string, string | undefined> = {
    ...process.env,
    ...(isTest && !process.env.TEST_DATABASE_URL ? { DATABASE_URL: 'file::memory:' } : {}),
    ...overrides,
  };
  const parsed = envSchema.parse(merged);

  if (
    merged.NODE_ENV === 'production' &&
    (INSECURE_JWT_SECRETS.has(parsed.JWT_SECRET) || parsed.JWT_SECRET.length < 32)
  ) {
    throw new Error('JWT_SECRET must be set to a random value of at least 32 chars in production');
  }

  return parsed;
}

export const config: AppConfig = loadConfig();
