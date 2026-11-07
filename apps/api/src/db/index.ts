import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createClient, type Client } from '@libsql/client';
import { drizzle, type LibSQLDatabase } from 'drizzle-orm/libsql';
import { config } from '../config.js';
import * as schema from './schema.js';

export type AppDatabase = LibSQLDatabase<typeof schema>;

function resolveLibsqlUrl(url: string): string {
  if (url === 'file::memory:' || url === ':memory:') {
    const tmpFile = path.join(
      os.tmpdir(),
      `paydmewx-mem-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    process.on('exit', () => {
      for (const suffix of ['', '-wal', '-shm', '-journal']) {
        try {
          fs.unlinkSync(`${tmpFile}${suffix}`);
        } catch {
          // ignore cleanup errors
        }
      }
    });
    return `file:${tmpFile}`;
  }
  return url;
}

export function createDbClient(
  url = config.DATABASE_URL,
  authToken = config.DATABASE_AUTH_TOKEN
): {
  client: Client;
  db: AppDatabase;
} {
  const client = createClient({
    url: resolveLibsqlUrl(url),
    authToken: authToken || undefined,
  });
  const db = drizzle(client, { schema });
  return { client, db };
}

const defaultInstance = createDbClient();

export const client: Client = defaultInstance.client;
export const db: AppDatabase = defaultInstance.db;
