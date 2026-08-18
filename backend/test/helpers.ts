import { readFileSync } from 'node:fs';

// Load .env.test before anything reads process.env — importing the app pulls in
// env.ts, which validates and freezes configuration at import time.
for (const line of readFileSync(new URL('../.env.test', import.meta.url), 'utf8').split('\n')) {
  const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
  if (!match) continue;
  process.env[match[1]] = match[2].replace(/^["']|["']$/g, '');
}
process.env.ACCESS_TOKEN_SECRET ??= 'test-secret-that-is-long-enough-1234567890';

const { buildApp } = await import('../src/app.js');
const { CapturingMailer } = await import('../src/lib/mailer.js');
const { prisma } = await import('../src/lib/prisma.js');

export { prisma, CapturingMailer };

export const mailer = new CapturingMailer();
export const app = await buildApp({ mailer });

/** Every table, most-dependent first. */
export async function resetDatabase(): Promise<void> {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "verification_tokens", "refresh_tokens", "identities", ' +
      '"packing_list_items", "packing_lists", "documents", "items", ' +
      '"transport_legs", "stays", "trips", "users" CASCADE',
  );
  mailer.clear();
}

type Json = Record<string, unknown>;

export async function post(url: string, body: Json, token?: string) {
  return app.inject({
    method: 'POST',
    url,
    payload: body,
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
}

export async function get(url: string, token?: string) {
  return app.inject({
    method: 'GET',
    url,
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
}

/** The six-digit code from the most recent email to an address. */
export function codeFor(email: string): string {
  const mail = mailer.lastTo(email);
  if (!mail) throw new Error(`No email was sent to ${email}`);
  const match = mail.text.match(/\b(\d{6})\b/);
  if (!match) throw new Error(`No code in email to ${email}: ${mail.text}`);
  return match[1];
}

/** Signs up, confirms the email, and signs in. Returns a usable session. */
export async function createVerifiedUser(
  email: string,
  password = 'correct-horse-battery',
): Promise<{ accessToken: string; refreshToken: string; userId: string }> {
  await post('/auth/signup', { email, password });
  await post('/auth/verify-email', { email, code: codeFor(email) });
  const signin = await post('/auth/signin', { email, password });
  const body = signin.json();
  return {
    accessToken: body.accessToken,
    refreshToken: body.refreshToken,
    userId: body.user.id,
  };
}
