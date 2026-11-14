import type { FastifyReply, FastifyRequest } from 'fastify';
import { eq } from 'drizzle-orm';
import { db } from '../db/index.js';
import { businesses, users, type BusinessRow, type UserRow } from '../db/schema.js';
import { AppError } from './errors.js';
import { verifyToken } from './jwt.js';

export interface PublicUser {
  id: string;
  email: string;
  name: string;
  createdAt: number;
}

export function toPublicUser(user: UserRow): PublicUser {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    createdAt: user.createdAt,
  };
}

declare module 'fastify' {
  interface FastifyRequest {
    user?: PublicUser;
    business?: BusinessRow;
  }
}

export async function requireAuth(
  request: FastifyRequest,
  _reply: FastifyReply
): Promise<void> {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new AppError(401, 'UNAUTHORIZED', 'Missing or invalid Authorization header');
  }

  const token = authHeader.slice('Bearer '.length).trim();
  if (!token) {
    throw new AppError(401, 'UNAUTHORIZED', 'Missing Bearer token');
  }

  const payload = await verifyToken(token);
  const [userRow] = await db
    .select()
    .from(users)
    .where(eq(users.id, payload.sub))
    .limit(1);

  if (!userRow) {
    throw new AppError(401, 'UNAUTHORIZED', 'User not found');
  }

  request.user = toPublicUser(userRow);
}

export async function requireBusiness(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<void> {
  if (!request.user) {
    await requireAuth(request, reply);
  }

  const [businessRow] = await db
    .select()
    .from(businesses)
    .where(eq(businesses.ownerId, request.user!.id))
    .limit(1);

  if (!businessRow) {
    throw new AppError(404, 'BUSINESS_NOT_FOUND', 'User does not have a registered business');
  }

  request.business = businessRow;
}
