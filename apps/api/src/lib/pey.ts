import { config } from '../config.js';
import { AppError } from './errors.js';

export interface CreateCodiQrInput {
  amountCents: number;
  concept: string;
  numRef: string;
  expirationSec: number;
  bankAccountId?: string;
  metadata?: Record<string, unknown>;
}

export interface CreateCodiQrResult {
  id: string;
  qrString: string;
}

export interface PeyClient {
  createCodiQr(input: CreateCodiQrInput): Promise<CreateCodiQrResult>;
}

export interface PeyClientOptions {
  baseUrl?: string;
  apiKey?: string;
  testAmountOverride?: string;
}

export function resolvePesosAmount(amountCents: number, overrideRaw?: string): number {
  const trimmed = overrideRaw?.trim();
  if (trimmed) {
    const parsed = Number(trimmed);
    if (Number.isFinite(parsed) && parsed > 0) {
      return Number(parsed.toFixed(2));
    }
  }
  return Number((amountCents / 100).toFixed(2));
}

export function createPeyClient(options: PeyClientOptions = {}): PeyClient {
  return {
    async createCodiQr(input: CreateCodiQrInput): Promise<CreateCodiQrResult> {
      const apiKey = (options.apiKey ?? process.env.PEY_API_KEY ?? config.PEY_API_KEY ?? '').trim();
      if (!apiKey) {
        throw new AppError(503, 'PEY_NOT_CONFIGURED', 'pey API key is not configured');
      }

      const baseUrl = (
        options.baseUrl ??
        process.env.PEY_BASE_URL ??
        config.PEY_BASE_URL ??
        'https://api.pey.mx'
      ).replace(/\/+$/, '');

      const overrideRaw =
        options.testAmountOverride ??
        process.env.PEY_TEST_AMOUNT_OVERRIDE ??
        config.PEY_TEST_AMOUNT_OVERRIDE;

      const amount = resolvePesosAmount(input.amountCents, overrideRaw);

      const payload: Record<string, unknown> = {
        amount,
        concept: input.concept,
        expiration: input.expirationSec,
        numRef: input.numRef,
        generateImage: false,
        metadata: input.metadata ?? {},
      };

      if (input.bankAccountId) {
        payload.bankAccountId = input.bankAccountId;
      }

      let response: Response;
      try {
        response = await fetch(`${baseUrl}/codi/qr`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${apiKey}`,
          },
          body: JSON.stringify(payload),
        });
      } catch (err) {
        throw new AppError(
          502,
          'PEY_ERROR',
          err instanceof Error ? `pey request failed: ${err.message}` : 'pey request failed'
        );
      }

      let body: unknown = null;
      try {
        body = await response.json();
      } catch {
        body = null;
      }

      const peyError = (
        body as { error?: { message?: string; type?: string; requestId?: string } } | null
      )?.error;

      if (!response.ok || peyError) {
        const message = peyError?.message
          ? `${peyError.message}${peyError.requestId ? ` [${peyError.requestId}]` : ''}`
          : `pey error (HTTP ${response.status})`;
        throw new AppError(502, 'PEY_ERROR', message);
      }

      const data = body as { id?: unknown; qrString?: unknown } | null;
      if (!data || typeof data.id !== 'string' || typeof data.qrString !== 'string') {
        throw new AppError(502, 'PEY_ERROR', 'Invalid response payload from pey');
      }

      return {
        id: data.id,
        qrString: data.qrString,
      };
    },
  };
}

export const defaultPeyClient: PeyClient = createPeyClient();

export async function createCodiQr(input: CreateCodiQrInput): Promise<CreateCodiQrResult> {
  return defaultPeyClient.createCodiQr(input);
}
