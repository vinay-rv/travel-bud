/**
 * Proving an email address, and recovering an account.
 *
 * Both flows are the same shape: mint a short numeric code, store only its
 * hash, email the plaintext, and accept it once. Codes are six digits because
 * people type them from a phone; the short expiry and single use are what keep
 * that from being weak.
 */
import { createHash, randomInt } from 'node:crypto';

import { hash } from '@node-rs/argon2';

import { AuthError, normaliseEmail, signOutEverywhere } from './auth.js';
import type { Mailer } from './mailer.js';
import { prisma } from './prisma.js';

export const PURPOSE_VERIFY = 'verify_email';
export const PURPOSE_RESET = 'reset_password';

const VERIFY_TTL_MINUTES = 30;
const RESET_TTL_MINUTES = 30;

/** Six digits, uniformly random. `randomInt` is CSPRNG-backed. */
function generateCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, '0');
}

const hashCode = (code: string): string =>
  createHash('sha256').update(code).digest('hex');

const expiryIn = (minutes: number): Date =>
  new Date(Date.now() + minutes * 60_000);

async function issueCode(
  userId: string,
  purpose: string,
  ttlMinutes: number,
): Promise<string> {
  // Any earlier code for the same purpose stops working the moment a new one is
  // requested, so a forwarded old email is useless.
  await prisma.verificationToken.updateMany({
    where: { userId, purpose, consumedAt: null },
    data: { consumedAt: new Date() },
  });

  const code = generateCode();
  await prisma.verificationToken.create({
    data: {
      userId,
      purpose,
      codeHash: hashCode(code),
      expiresAt: expiryIn(ttlMinutes),
    },
  });
  return code;
}

/**
 * Finds a usable code, or throws. Never says which of "wrong", "expired" or
 * "already used" it was — that distinction only helps someone guessing.
 */
async function consumeCode(
  userId: string,
  purpose: string,
  code: string,
): Promise<void> {
  const record = await prisma.verificationToken.findFirst({
    where: {
      userId,
      purpose,
      codeHash: hashCode(code),
      consumedAt: null,
      expiresAt: { gt: new Date() },
    },
  });

  if (!record) {
    throw new AuthError(400, 'invalid_code', 'That code is not valid');
  }

  await prisma.verificationToken.update({
    where: { id: record.id },
    data: { consumedAt: new Date() },
  });
}

export async function sendEmailVerification(
  userId: string,
  email: string,
  mailer: Mailer,
): Promise<void> {
  const code = await issueCode(userId, PURPOSE_VERIFY, VERIFY_TTL_MINUTES);
  await mailer.send({
    to: email,
    subject: 'Confirm your Packmate email',
    text:
      `Your Packmate confirmation code is ${code}\n\n` +
      `It expires in ${VERIFY_TTL_MINUTES} minutes. ` +
      `If you didn't create an account, you can ignore this.`,
  });
}

export async function confirmEmail(
  emailInput: string,
  code: string,
): Promise<void> {
  const email = normaliseEmail(emailInput);
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    // Same error as a wrong code, so this cannot be used to test which
    // addresses are registered.
    throw new AuthError(400, 'invalid_code', 'That code is not valid');
  }
  if (user.emailVerified) return;

  await consumeCode(user.id, PURPOSE_VERIFY, code);
  await prisma.user.update({
    where: { id: user.id },
    data: { emailVerified: true },
  });
}

/**
 * Starts a password reset. Returns silently for unknown addresses: telling a
 * caller "no such account" turns this endpoint into an email checker.
 */
export async function requestPasswordReset(
  emailInput: string,
  mailer: Mailer,
): Promise<void> {
  const email = normaliseEmail(emailInput);
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) return;

  const code = await issueCode(user.id, PURPOSE_RESET, RESET_TTL_MINUTES);
  await mailer.send({
    to: email,
    subject: 'Reset your Packmate password',
    text:
      `Your Packmate password reset code is ${code}\n\n` +
      `It expires in ${RESET_TTL_MINUTES} minutes. ` +
      `If you didn't ask to reset your password, you can ignore this — ` +
      `your password has not changed.`,
  });
}

export async function resetPassword(
  emailInput: string,
  code: string,
  newPassword: string,
): Promise<void> {
  const email = normaliseEmail(emailInput);
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    throw new AuthError(400, 'invalid_code', 'That code is not valid');
  }

  await consumeCode(user.id, PURPOSE_RESET, code);
  await prisma.user.update({
    where: { id: user.id },
    data: {
      passwordHash: await hash(newPassword),
      // Reaching a code sent to the address proves ownership of it, so this
      // doubles as verification for an account that never confirmed.
      emailVerified: true,
    },
  });

  // Whoever knew the old password is no longer welcome: if the reset happened
  // because the account was compromised, leaving their sessions alive would
  // defeat the point.
  await signOutEverywhere(user.id);
}
