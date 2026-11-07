import { SignJWT, jwtVerify } from 'jose';
import { config } from '../config.js';
import { AppError } from './errors.js';

export interface JwtUserPayload {
  sub: string;
  email: string;
}

function getSecretKey(secret = config.JWT_SECRET): Uint8Array {
  return new TextEncoder().encode(secret);
}

export async function signToken(
  payload: JwtUserPayload,
  secret = config.JWT_SECRET
): Promise<string> {
  return new SignJWT({ email: payload.email })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(payload.sub)
    .setIssuedAt()
    .setExpirationTime('7d')
    .sign(getSecretKey(secret));
}

export async function verifyToken(
  token: string,
  secret = config.JWT_SECRET
): Promise<JwtUserPayload> {
  try {
    const { payload } = await jwtVerify(token, getSecretKey(secret), {
      algorithms: ['HS256'],
    });
    if (!payload.sub || typeof payload.email !== 'string') {
      throw new AppError(401, 'UNAUTHORIZED', 'Invalid token payload');
    }
    return {
      sub: payload.sub,
      email: payload.email,
    };
  } catch (err) {
    if (err instanceof AppError) {
      throw err;
    }
    throw new AppError(401, 'UNAUTHORIZED', 'Invalid or expired token');
  }
}
