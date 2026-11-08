import { config } from '../config.js';
import { AppError } from './errors.js';

export interface LlmToolCall {
  id: string;
  name: string;
  arguments: string;
}

export interface LlmTool {
  type: 'function';
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
}

export type LlmMessage =
  | {
      role: 'system' | 'user';
      content: string;
    }
  | {
      role: 'assistant';
      content: string | null;
      tool_calls?: Array<{
        id: string;
        type: 'function';
        function: {
          name: string;
          arguments: string;
        };
      }>;
    }
  | {
      role: 'tool';
      tool_call_id: string;
      name?: string;
      content: string;
    };

export interface LlmChatResponse {
  content: string | null;
  toolCalls: LlmToolCall[];
}

export interface LlmClient {
  chat(messages: LlmMessage[], tools: LlmTool[]): Promise<LlmChatResponse>;
}

export interface LlmClientOptions {
  baseUrl?: string;
  apiKey?: string;
  model?: string;
  fetch?: typeof fetch;
}

const GENERIC_LLM_ERROR_MSG = 'No pudimos contactar al asistente';
const BUSY_LLM_ERROR_MSG = 'El asistente esta ocupado, intenta de nuevo en unos segundos';
const MAX_RETRY_MS = 2500;

function parseRetryDelayMs(response: Response, bodyText: string): number {
  const retryAfter = response.headers.get('retry-after');
  if (retryAfter) {
    const num = Number(retryAfter.trim());
    if (!Number.isNaN(num) && num >= 0) {
      return Math.min(Math.round(num * 1000), MAX_RETRY_MS);
    }
  }
  const match = bodyText.match(/try again in\s+(\d+(?:\.\d+)?)\s*(ms|s)/i);
  if (match) {
    const val = parseFloat(match[1]!);
    const unit = match[2]!.toLowerCase();
    const ms = unit === 's' ? val * 1000 : val;
    if (!Number.isNaN(ms) && ms >= 0) {
      return Math.min(Math.round(ms), MAX_RETRY_MS);
    }
  }
  return 500;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function createLlmClient(options: LlmClientOptions = {}): LlmClient {
  return {
    async chat(messages: LlmMessage[], tools: LlmTool[]): Promise<LlmChatResponse> {
      const baseUrl = (
        options.baseUrl ??
        process.env.LLM_BASE_URL ??
        config.LLM_BASE_URL
      ).replace(/\/+$/, '');
      const apiKey = (
        options.apiKey !== undefined
          ? options.apiKey
          : (process.env.LLM_API_KEY ?? config.LLM_API_KEY ?? '')
      ).trim();
      const model = (
        options.model !== undefined
          ? options.model
          : (process.env.LLM_MODEL ?? config.LLM_MODEL ?? '')
      ).trim();

      if (!apiKey || !model) {
        throw new AppError(503, 'AI_NOT_CONFIGURED', 'El asistente no esta configurado');
      }

      const fetchFn = options.fetch ?? globalThis.fetch;
      const requestInit = (): RequestInit => ({
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          messages,
          tools,
          tool_choice: 'auto',
          temperature: 0.2,
          max_completion_tokens: 400,
        }),
        signal: AbortSignal.timeout(20_000),
      });

      const doFetch = async (): Promise<Response> => {
        try {
          return await fetchFn(`${baseUrl}/chat/completions`, requestInit());
        } catch (err) {
          if (err instanceof AppError) {
            throw err;
          }
          console.error('LLM upstream error: network');
          throw new AppError(502, 'LLM_ERROR', GENERIC_LLM_ERROR_MSG);
        }
      };

      let response = await doFetch();

      if (response.status === 429) {
        let retryBodyText = '';
        try {
          retryBodyText = await response.text();
        } catch {
          retryBodyText = '';
        }
        const delayMs = parseRetryDelayMs(response, retryBodyText);
        if (delayMs > 0) {
          await sleep(delayMs);
        }
        response = await doFetch();
        if (response.status === 429) {
          throw new AppError(503, 'LLM_BUSY', BUSY_LLM_ERROR_MSG);
        }
      }

      if (!response.ok) {
        console.error(`LLM upstream error: HTTP ${response.status}`);
        throw new AppError(502, 'LLM_ERROR', GENERIC_LLM_ERROR_MSG);
      }

      let payload: unknown;
      try {
        payload = await response.json();
      } catch {
        console.error(`LLM upstream error: HTTP ${response.status}`);
        throw new AppError(502, 'LLM_ERROR', GENERIC_LLM_ERROR_MSG);
      }

      const choices =
        payload && typeof payload === 'object' && 'choices' in payload
          ? (payload as { choices?: unknown }).choices
          : undefined;

      if (!Array.isArray(choices) || choices.length === 0) {
        console.error(`LLM upstream error: HTTP ${response.status}`);
        throw new AppError(502, 'LLM_ERROR', GENERIC_LLM_ERROR_MSG);
      }

      const firstChoice = choices[0] as {
        message?: {
          content?: unknown;
          tool_calls?: unknown;
        };
      };

      const msg = firstChoice?.message;
      if (!msg || typeof msg !== 'object') {
        console.error(`LLM upstream error: HTTP ${response.status}`);
        throw new AppError(502, 'LLM_ERROR', GENERIC_LLM_ERROR_MSG);
      }

      const content = typeof msg.content === 'string' ? msg.content : null;
      const rawToolCalls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];

      const toolCalls: LlmToolCall[] = rawToolCalls.map((tc, index) => {
        const callObj = tc as {
          id?: unknown;
          function?: {
            name?: unknown;
            arguments?: unknown;
          };
        };
        const id =
          typeof callObj?.id === 'string' && callObj.id.length > 0
            ? callObj.id
            : `call_${index + 1}`;
        const name =
          typeof callObj?.function?.name === 'string' ? callObj.function.name : '';
        const rawArgs = callObj?.function?.arguments;
        const argsString =
          typeof rawArgs === 'string' ? rawArgs : JSON.stringify(rawArgs ?? {});

        return {
          id,
          name,
          arguments: argsString,
        };
      });

      return {
        content,
        toolCalls,
      };
    },
  };
}

export const defaultLlmClient: LlmClient = createLlmClient();
