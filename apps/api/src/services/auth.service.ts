import bcrypt from 'bcryptjs';
import { eq } from 'drizzle-orm';
import { ulid } from 'ulid';
import { db } from '../db/index.js';
import { businesses, users, type BusinessRow } from '../db/schema.js';
import { toPublicUser, type PublicUser } from '../lib/auth.js';
import { AppError } from '../lib/errors.js';
import { signToken } from '../lib/jwt.js';

const BCRYPT_COST = 10;

export interface AuthResult {
  token: string;
  user: PublicUser;
}

export async function registerUser(input: {
  email: string;
  password: string;
  name: string;
}): Promise<AuthResult> {
  const normalizedEmail = input.email.trim().toLowerCase();
  const [existing] = await db
    .select({ id: users.id })
    .from(users)
    .where(eq(users.email, normalizedEmail))
    .limit(1);

  if (existing) {
    throw new AppError(409, 'EMAIL_EXISTS', 'Email is already registered');
  }

  const passwordHash = await bcrypt.hash(input.password, BCRYPT_COST);
  const now = Math.floor(Date.now() / 1000);
  const newUser = {
    id: ulid(),
    email: normalizedEmail,
    passwordHash,
    name: input.name.trim(),
    createdAt: now,
  };

  await db.insert(users).values(newUser);

  const publicUser = toPublicUser(newUser);
  const token = await signToken({ sub: publicUser.id, email: publicUser.email });

  return { token, user: publicUser };
}

export async function loginUser(input: {
  email: string;
  password: string;
}): Promise<AuthResult> {
  const normalizedEmail = input.email.trim().toLowerCase();
  const [userRow] = await db
    .select()
    .from(users)
    .where(eq(users.email, normalizedEmail))
    .limit(1);

  if (!userRow) {
    throw new AppError(401, 'INVALID_CREDENTIALS', 'Invalid email or password');
  }

  const valid = await bcrypt.compare(input.password, userRow.passwordHash);
  if (!valid) {
    throw new AppError(401, 'INVALID_CREDENTIALS', 'Invalid email or password');
  }

  const publicUser = toPublicUser(userRow);
  const token = await signToken({ sub: publicUser.id, email: publicUser.email });

  return { token, user: publicUser };
}

export async function getProfile(userId: string): Promise<{
  user: PublicUser;
  business: BusinessRow | null;
}> {
  const [userRow] = await db
    .select()
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);

  if (!userRow) {
    throw new AppError(404, 'USER_NOT_FOUND', 'User not found');
  }

  const [businessRow] = await db
    .select()
    .from(businesses)
    .where(eq(businesses.ownerId, userId))
    .limit(1);

  return {
    user: toPublicUser(userRow),
    business: businessRow ?? null,
  };
}
