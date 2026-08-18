/**
 * Session tokens.
 *
 * Two kinds, doing different jobs:
 *
 * - **Access token**: a short-lived signed JWT. Carries the user id, is checked
 *   on every request with no database round trip, and expires quickly so a
 *   stolen one is worth little.
 * - **Refresh token**: a long-lived opaque random string. Stored only as a
 *   SHA-256 hash, so a dumped database cannot be used to mint sessions. Rotated
 *   on every use, which is what makes theft detectable — see `rotate`.
 *
 * The split exists because a travel app is offline constantly: the access token
 * has to be verifiable without a network, and the refresh token has to survive
 * weeks of no connectivity.
 */
import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';

import { env } from './env.js';

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const REFRESH_TOKEN_TTL_DAYS = 60;

const secret = new TextEncoder().encode(env.ACCESS_TOKEN_SECRET);

export async function signAccessToken(userId: string): Promise<string> {
  return new SignJWT({ sub: userId })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setIssuer('packmate-api')
    .setAudience('packmate-app')
    .setExpirationTime(`${ACCESS_TOKEN_TTL_SECONDS}s`)
    .sign(secret);
}

/** The user id inside a valid token, or null for anything unacceptable. */
export async function verifyAccessToken(token: string): Promise<string | null> {
  try {
    const { payload } = await jwtVerify(token, secret, {
      issuer: 'packmate-api',
      audience: 'packmate-app',
    });
    return typeof payload.sub === 'string' ? payload.sub : null;
  } catch {
    // Expired, tampered with, wrong audience — all the same to a caller, and
    // none of them worth telling an attacker apart.
    return null;
  }
}

/** 256 bits of randomness. Never stored; only its hash is. */
export function generateRefreshToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export function refreshTokenExpiry(from = new Date()): Date {
  const expires = new Date(from);
  expires.setUTCDate(expires.getUTCDate() + REFRESH_TOKEN_TTL_DAYS);
  return expires;
}
