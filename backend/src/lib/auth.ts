/**
 * Account and session operations.
 *
 * Two rules shape everything here:
 *
 * 1. **Never reveal whether an email exists.** Sign-up and sign-in return the
 *    same shaped failure for "no such user" and "wrong password", so the API
 *    can't be used to enumerate who has an account.
 * 2. **Refresh tokens rotate.** Presenting one consumes it and issues a
 *    replacement. Presenting an already-consumed one means either a race or a
 *    stolen token, and the safe reading is theft: the whole family is revoked.
 */
import { hash, verify } from '@node-rs/argon2';
import type { User } from '@prisma/client';

import { prisma } from './prisma.js';
import {
  generateRefreshToken,
  hashRefreshToken,
  refreshTokenExpiry,
  signAccessToken,
} from './tokens.js';

export class AuthError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export type Session = {
  accessToken: string;
  refreshToken: string;
  user: { id: string; email: string; displayName: string | null };
};

/** Emails are compared case-insensitively; people capitalise inconsistently. */
export const normaliseEmail = (email: string): string =>
  email.trim().toLowerCase();

export async function issueSession(
  user: User,
  userAgent?: string,
): Promise<Session> {
  const refreshToken = generateRefreshToken();
  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenHash: hashRefreshToken(refreshToken),
      expiresAt: refreshTokenExpiry(),
      userAgent: userAgent?.slice(0, 200),
    },
  });

  return {
    accessToken: await signAccessToken(user.id),
    refreshToken,
    user: { id: user.id, email: user.email, displayName: user.displayName },
  };
}

/**
 * Creates an account. Returns the user rather than a session: sign-up does not
 * sign you in, because the email still has to be confirmed.
 */
export async function signUp(
  emailInput: string,
  password: string,
  displayName: string | undefined,
): Promise<User> {
  const email = normaliseEmail(emailInput);
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    // Deliberately the same 409 whether or not a password is set, so this
    // cannot be used to discover which addresses are registered.
    throw new AuthError(409, 'email_taken', 'That email is already registered');
  }

  return prisma.user.create({
    data: {
      email,
      passwordHash: await hash(password),
      displayName: displayName?.trim() || null,
    },
  });
}

export async function signIn(
  emailInput: string,
  password: string,
  userAgent?: string,
): Promise<Session> {
  const email = normaliseEmail(emailInput);
  const user = await prisma.user.findUnique({ where: { email } });

  // Verify against a dummy hash when the user is absent so both paths cost the
  // same; skipping the work would make "no such account" measurably faster.
  const hashToCheck = user?.passwordHash ?? DUMMY_HASH;
  const ok = await verify(hashToCheck, password).catch(() => false);

  if (!user || !user.passwordHash || !ok) {
    throw new AuthError(401, 'invalid_credentials', 'Email or password is incorrect');
  }

  // Checked only after the password is confirmed correct. Reporting it earlier
  // would tell an attacker holding a wrong password that the account exists.
  if (!user.emailVerified) {
    throw new AuthError(
      403,
      'email_not_verified',
      'Confirm your email address to finish signing in',
    );
  }

  return issueSession(user, userAgent);
}

/**
 * Exchanges a refresh token for a new session, consuming the old one.
 *
 * A token that was already rotated is treated as compromised: if an attacker
 * copied it and used it, the legitimate holder's next attempt lands here (or
 * vice versa), and there is no way to tell which caller is which. Revoking
 * every token for that user is the only safe answer — it forces one sign-in
 * rather than leaving a thief with a valid session.
 */
export async function rotate(
  presented: string,
  userAgent?: string,
): Promise<Session> {
  const tokenHash = hashRefreshToken(presented);
  const record = await prisma.refreshToken.findUnique({
    where: { tokenHash },
    include: { user: true },
  });

  if (!record) {
    throw new AuthError(401, 'invalid_refresh_token', 'Please sign in again');
  }

  if (record.revokedAt || record.replacedById) {
    await prisma.refreshToken.updateMany({
      where: { userId: record.userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    throw new AuthError(
      401,
      'refresh_token_reused',
      'Session expired. Please sign in again.',
    );
  }

  if (record.expiresAt <= new Date()) {
    throw new AuthError(401, 'refresh_token_expired', 'Please sign in again');
  }

  const next = generateRefreshToken();
  const created = await prisma.refreshToken.create({
    data: {
      userId: record.userId,
      tokenHash: hashRefreshToken(next),
      expiresAt: refreshTokenExpiry(),
      userAgent: userAgent?.slice(0, 200),
    },
  });
  await prisma.refreshToken.update({
    where: { id: record.id },
    data: { revokedAt: new Date(), replacedById: created.id },
  });

  return {
    accessToken: await signAccessToken(record.userId),
    refreshToken: next,
    user: {
      id: record.user.id,
      email: record.user.email,
      displayName: record.user.displayName,
    },
  };
}

/** Signs out. Unknown tokens succeed: signing out is not worth an error. */
export async function signOut(presented: string): Promise<void> {
  await prisma.refreshToken.updateMany({
    where: { tokenHash: hashRefreshToken(presented), revokedAt: null },
    data: { revokedAt: new Date() },
  });
}

/** Ends every session for a user, e.g. after a password change. */
export async function signOutEverywhere(userId: string): Promise<void> {
  await prisma.refreshToken.updateMany({
    where: { userId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}

/**
 * A real argon2id hash of a random value, used only to keep the timing of a
 * failed sign-in independent of whether the account exists.
 */
const DUMMY_HASH =
  '$argon2id$v=19$m=19456,t=2,p=1$c29tZXNhbHRzb21lc2FsdA$' +
  'JbAqCFPPHfEiVBWCyPuOfHOFDgSGXR3xNjbWEOaLBUE';
