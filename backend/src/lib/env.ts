/**
 * Configuration, read once and validated at startup.
 *
 * Deliberately fails fast: a server that boots without a token secret and only
 * discovers it on the first login is worse than one that refuses to start.
 */
import { z } from 'zod';

const schema = z.object({
  DATABASE_URL: z.string().min(1),
  // 32 bytes minimum. A short secret on a JWT signing key is the kind of thing
  // that looks fine forever and then doesn't.
  ACCESS_TOKEN_SECRET: z.string().min(32),
  PORT: z.coerce.number().int().positive().default(8080),
  // Guards the console mailer: it refuses to run when this says production.
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  // Comma-separated allowlists for federated sign-in. Empty disables it, which
  // is the right default: accepting an ID token without checking its audience
  // would let a token minted for any other app sign in here.
  // Email delivery. Absent in tests, which use a capturing mailer; required in
  // any process that actually signs people up.
  RESEND_API_KEY: z.string().optional(),
  MAIL_FROM: z.string().optional(),
  GOOGLE_CLIENT_IDS: z.string().default(''),
  APPLE_BUNDLE_IDS: z.string().default(''),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  const detail = parsed.error.issues
    .map((issue) => `  ${issue.path.join('.') || '(root)'}: ${issue.message}`)
    .join('\n');
  throw new Error(`Invalid environment:\n${detail}`);
}

const list = (raw: string): string[] =>
  raw.split(',').map((value) => value.trim()).filter(Boolean);

export const env = {
  ...parsed.data,
  googleClientIds: list(parsed.data.GOOGLE_CLIENT_IDS),
  appleBundleIds: list(parsed.data.APPLE_BUNDLE_IDS),
};

export type Env = typeof env;
