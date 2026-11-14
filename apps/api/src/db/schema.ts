import { sqliteTable, text, integer, real } from 'drizzle-orm/sqlite-core';
import { z } from 'zod';

export const BUSINESS_CATEGORIES = [
  'food',
  'tailoring',
  'footwear',
  'clothing',
  'department',
  'grocery',
  'services',
  'other',
] as const;

export const PREP_TYPES = ['instant', 'made_to_order'] as const;

export const ORDER_STATUSES = [
  'pending_payment',
  'paid',
  'preparing',
  'ready',
  'delivered',
  'cancelled',
  'expired',
] as const;

export const categorySchema = z.enum(BUSINESS_CATEGORIES);
export const prepTypeSchema = z.enum(PREP_TYPES);
export const orderStatusSchema = z.enum(ORDER_STATUSES);

export type BusinessCategory = z.infer<typeof categorySchema>;
export type PrepType = z.infer<typeof prepTypeSchema>;
export type OrderStatus = z.infer<typeof orderStatusSchema>;

export const users = sqliteTable('users', {
  id: text('id').primaryKey(),
  email: text('email').notNull().unique(),
  passwordHash: text('passwordHash').notNull(),
  name: text('name').notNull(),
  createdAt: integer('createdAt').notNull(),
});

export const businesses = sqliteTable('businesses', {
  id: text('id').primaryKey(),
  ownerId: text('ownerId')
    .notNull()
    .unique()
    .references(() => users.id),
  name: text('name').notNull(),
  description: text('description'),
  category: text('category').$type<BusinessCategory>().notNull(),
  prepType: text('prepType').$type<PrepType>().notNull(),
  address: text('address'),
  lat: real('lat'),
  lng: real('lng'),
  active: integer('active', { mode: 'boolean' }).notNull().default(true),
  peyBankAccountId: text('peyBankAccountId'),
  clabe: text('clabe'),
  codiStatus: text('codiStatus'),
  createdAt: integer('createdAt').notNull(),
});

export const products = sqliteTable('products', {
  id: text('id').primaryKey(),
  businessId: text('businessId')
    .notNull()
    .references(() => businesses.id),
  name: text('name').notNull(),
  priceCents: integer('priceCents').notNull(),
  trackStock: integer('trackStock', { mode: 'boolean' }).notNull().default(true),
  stock: integer('stock').notNull().default(0),
  prepMinutes: integer('prepMinutes'),
  imageUrl: text('imageUrl'),
  active: integer('active', { mode: 'boolean' }).notNull().default(true),
  createdAt: integer('createdAt').notNull(),
});

export const stockMovements = sqliteTable('stock_movements', {
  id: text('id').primaryKey(),
  productId: text('productId')
    .notNull()
    .references(() => products.id),
  delta: integer('delta').notNull(),
  reason: text('reason').notNull(),
  createdAt: integer('createdAt').notNull(),
});

export const stock_movements = stockMovements;

export const orders = sqliteTable('orders', {
  id: text('id').primaryKey(),
  businessId: text('businessId')
    .notNull()
    .references(() => businesses.id),
  customerId: text('customerId').references(() => users.id),
  status: text('status').$type<OrderStatus>().notNull(),
  totalCents: integer('totalCents').notNull(),
  note: text('note'),
  createdAt: integer('createdAt').notNull(),
  paidAt: integer('paidAt'),
});

export const orderItems = sqliteTable('order_items', {
  id: text('id').primaryKey(),
  orderId: text('orderId')
    .notNull()
    .references(() => orders.id),
  productId: text('productId')
    .notNull()
    .references(() => products.id),
  name: text('name').notNull(),
  priceCents: integer('priceCents').notNull(),
  qty: integer('qty').notNull(),
});

export const order_items = orderItems;

export const payments = sqliteTable('payments', {
  id: text('id').primaryKey(),
  orderId: text('orderId')
    .notNull()
    .references(() => orders.id),
  codiQrId: text('codiQrId'),
  qrString: text('qrString'),
  expiresAt: integer('expiresAt'),
  transactionId: text('transactionId'),
  status: text('status').notNull(),
  amountCents: integer('amountCents').notNull(),
  createdAt: integer('createdAt').notNull(),
});

export const webhookEvents = sqliteTable('webhook_events', {
  id: text('id').primaryKey(),
  receivedAt: integer('receivedAt').notNull(),
});

export const webhook_events = webhookEvents;

export type UserRow = typeof users.$inferSelect;
export type BusinessRow = typeof businesses.$inferSelect;
export type ProductRow = typeof products.$inferSelect;
export type StockMovementRow = typeof stockMovements.$inferSelect;
export type OrderRow = typeof orders.$inferSelect;
export type OrderItemRow = typeof orderItems.$inferSelect;
export type PaymentRow = typeof payments.$inferSelect;
export type WebhookEventRow = typeof webhookEvents.$inferSelect;
