import { and, eq, like, or, sql } from 'drizzle-orm';
import { ulid } from 'ulid';
import { db } from '../db/index.js';
import {
  businesses,
  products,
  type BusinessCategory,
  type BusinessRow,
  type PrepType,
  type ProductRow,
} from '../db/schema.js';
import { isValidClabe } from '../lib/clabe.js';
import { AppError } from '../lib/errors.js';

export interface CreateBusinessInput {
  name: string;
  category: BusinessCategory;
  prepType: PrepType;
  description?: string | null;
  address?: string | null;
  lat?: number | null;
  lng?: number | null;
}

export interface UpdateBusinessInput {
  name?: string;
  category?: BusinessCategory;
  prepType?: PrepType;
  description?: string | null;
  address?: string | null;
  lat?: number | null;
  lng?: number | null;
  active?: boolean;
  clabe?: string;
}

export async function createBusinessForUser(
  ownerId: string,
  input: CreateBusinessInput
): Promise<BusinessRow> {
  const [existing] = await db
    .select({ id: businesses.id })
    .from(businesses)
    .where(eq(businesses.ownerId, ownerId))
    .limit(1);

  if (existing) {
    throw new AppError(409, 'BUSINESS_ALREADY_EXISTS', 'User already has a business');
  }

  const now = Math.floor(Date.now() / 1000);
  const row: BusinessRow = {
    id: ulid(),
    ownerId,
    name: input.name.trim(),
    description: input.description ?? null,
    category: input.category,
    prepType: input.prepType,
    address: input.address ?? null,
    lat: input.lat ?? null,
    lng: input.lng ?? null,
    active: true,
    peyBankAccountId: null,
    clabe: null,
    codiStatus: null,
    createdAt: now,
  };

  await db.insert(businesses).values(row);
  return row;
}

export async function updateBusinessForUser(
  ownerId: string,
  input: UpdateBusinessInput
): Promise<BusinessRow> {
  const [existing] = await db
    .select()
    .from(businesses)
    .where(eq(businesses.ownerId, ownerId))
    .limit(1);

  if (!existing) {
    throw new AppError(404, 'BUSINESS_NOT_FOUND', 'User does not have a business');
  }

  if (input.clabe !== undefined) {
    if (!isValidClabe(input.clabe)) {
      throw new AppError(400, 'INVALID_CLABE', 'CLABE must be 18 digits with a valid check digit');
    }
  }

  const updates: Partial<BusinessRow> = {};
  if (input.name !== undefined) updates.name = input.name.trim();
  if (input.category !== undefined) updates.category = input.category;
  if (input.prepType !== undefined) updates.prepType = input.prepType;
  if (input.description !== undefined) updates.description = input.description;
  if (input.address !== undefined) updates.address = input.address;
  if (input.lat !== undefined) updates.lat = input.lat;
  if (input.lng !== undefined) updates.lng = input.lng;
  if (input.active !== undefined) updates.active = input.active;
  if (input.clabe !== undefined) updates.clabe = input.clabe;

  if (Object.keys(updates).length > 0) {
    await db.update(businesses).set(updates).where(eq(businesses.id, existing.id));
  }

  const [updated] = await db
    .select()
    .from(businesses)
    .where(eq(businesses.id, existing.id))
    .limit(1);

  return updated!;
}

/** Business as exposed on unauthenticated discovery routes: no bank data. */
export type PublicBusiness = Omit<BusinessRow, 'clabe' | 'peyBankAccountId'>;

function toPublicBusiness(row: BusinessRow): PublicBusiness {
  const { clabe: _clabe, peyBankAccountId: _peyBankAccountId, ...rest } = row;
  return rest;
}

export async function listActiveBusinesses(filters: {
  category?: BusinessCategory;
  prepType?: PrepType;
  q?: string;
}): Promise<PublicBusiness[]> {
  const conditions = [eq(businesses.active, true)];

  if (filters.category) {
    conditions.push(eq(businesses.category, filters.category));
  }
  if (filters.prepType) {
    conditions.push(eq(businesses.prepType, filters.prepType));
  }
  if (filters.q && filters.q.trim() !== '') {
    const pattern = `%${filters.q.trim()}%`;
    conditions.push(
      or(
        like(businesses.name, pattern),
        like(sql`COALESCE(${businesses.description}, '')`, pattern),
        like(sql`COALESCE(${businesses.address}, '')`, pattern)
      )!
    );
  }

  const rows = await db
    .select()
    .from(businesses)
    .where(and(...conditions));
  return rows.map(toPublicBusiness);
}

export async function getActiveBusinessById(id: string): Promise<PublicBusiness> {
  const [business] = await db
    .select()
    .from(businesses)
    .where(and(eq(businesses.id, id), eq(businesses.active, true)))
    .limit(1);

  if (!business) {
    throw new AppError(404, 'BUSINESS_NOT_FOUND', 'Business not found');
  }

  return toPublicBusiness(business);
}

export async function listActiveBusinessProducts(businessId: string): Promise<ProductRow[]> {
  await getActiveBusinessById(businessId);
  return db
    .select()
    .from(products)
    .where(and(eq(products.businessId, businessId), eq(products.active, true)));
}
