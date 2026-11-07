import { fileURLToPath } from 'node:url';
import type { Client } from '@libsql/client';
import { client as defaultClient } from './index.js';

const MIGRATION_STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY NOT NULL,
    email TEXT NOT NULL UNIQUE,
    passwordHash TEXT NOT NULL,
    name TEXT NOT NULL,
    createdAt INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS businesses (
    id TEXT PRIMARY KEY NOT NULL,
    ownerId TEXT NOT NULL UNIQUE REFERENCES users(id),
    name TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL,
    prepType TEXT NOT NULL,
    address TEXT,
    lat REAL,
    lng REAL,
    active INTEGER NOT NULL DEFAULT 1,
    peyBankAccountId TEXT,
    clabe TEXT,
    codiStatus TEXT,
    createdAt INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY NOT NULL,
    businessId TEXT NOT NULL REFERENCES businesses(id),
    name TEXT NOT NULL,
    priceCents INTEGER NOT NULL,
    trackStock INTEGER NOT NULL DEFAULT 1,
    stock INTEGER NOT NULL DEFAULT 0,
    prepMinutes INTEGER,
    imageUrl TEXT,
    active INTEGER NOT NULL DEFAULT 1,
    createdAt INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS stock_movements (
    id TEXT PRIMARY KEY NOT NULL,
    productId TEXT NOT NULL REFERENCES products(id),
    delta INTEGER NOT NULL,
    reason TEXT NOT NULL,
    createdAt INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS orders (
    id TEXT PRIMARY KEY NOT NULL,
    businessId TEXT NOT NULL REFERENCES businesses(id),
    customerId TEXT REFERENCES users(id),
    status TEXT NOT NULL,
    totalCents INTEGER NOT NULL,
    note TEXT,
    createdAt INTEGER NOT NULL,
    paidAt INTEGER
  )`,
  `CREATE TABLE IF NOT EXISTS order_items (
    id TEXT PRIMARY KEY NOT NULL,
    orderId TEXT NOT NULL REFERENCES orders(id),
    productId TEXT NOT NULL REFERENCES products(id),
    name TEXT NOT NULL,
    priceCents INTEGER NOT NULL,
    qty INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS payments (
    id TEXT PRIMARY KEY NOT NULL,
    orderId TEXT NOT NULL REFERENCES orders(id),
    codiQrId TEXT,
    qrString TEXT,
    expiresAt INTEGER,
    transactionId TEXT,
    status TEXT NOT NULL,
    amountCents INTEGER NOT NULL,
    createdAt INTEGER NOT NULL
  )`,
  `CREATE TABLE IF NOT EXISTS webhook_events (
    id TEXT PRIMARY KEY NOT NULL,
    receivedAt INTEGER NOT NULL
  )`,
  `CREATE INDEX IF NOT EXISTS idx_businesses_category ON businesses(category)`,
  `CREATE INDEX IF NOT EXISTS idx_businesses_prepType ON businesses(prepType)`,
  `CREATE INDEX IF NOT EXISTS idx_products_businessId ON products(businessId)`,
  `CREATE INDEX IF NOT EXISTS idx_stock_movements_productId ON stock_movements(productId)`,
  `CREATE INDEX IF NOT EXISTS idx_orders_businessId ON orders(businessId)`,
  `CREATE INDEX IF NOT EXISTS idx_orders_customerId ON orders(customerId)`,
  `CREATE INDEX IF NOT EXISTS idx_order_items_orderId ON order_items(orderId)`,
  `CREATE INDEX IF NOT EXISTS idx_payments_orderId ON payments(orderId)`,
];

export async function runMigrations(dbClient: Client = defaultClient): Promise<void> {
  for (const statement of MIGRATION_STATEMENTS) {
    await dbClient.execute(statement);
  }

  const paymentCols = await dbClient.execute(`PRAGMA table_info(payments)`);
  const existingColNames = new Set(
    paymentCols.rows.map((r) => String((r as Record<string, unknown>).name))
  );
  if (!existingColNames.has('qrString')) {
    await dbClient.execute(`ALTER TABLE payments ADD COLUMN qrString TEXT`);
  }
  if (!existingColNames.has('expiresAt')) {
    await dbClient.execute(`ALTER TABLE payments ADD COLUMN expiresAt INTEGER`);
  }
}

const isMain =
  process.argv[1] &&
  fileURLToPath(import.meta.url).toLowerCase() === process.argv[1].toLowerCase();

if (isMain) {
  runMigrations()
    .then(() => {
      console.log('Database migrations completed.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Migration failed:', err);
      process.exit(1);
    });
}
