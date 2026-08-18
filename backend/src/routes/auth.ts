/**
 * Account endpoints.
 *
 * Sign-up does not return a session: the address has to be confirmed first,
 * which is the whole point of requiring a verified email. Everything that takes
 * a credential is rate limited, because these are the endpoints worth guessing
 * at.
 */
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';

import {
  AuthError,
  rotate,
  signIn,
  signOut,
  signUp,
  issueSession,
} from '../lib/auth.js';
import type { Mailer } from '../lib/mailer.js';
import { prisma } from '../lib/prisma.js';
import { ACCESS_TOKEN_TTL_SECONDS } from '../lib/tokens.js';
import {
  confirmEmail,
  requestPasswordReset,
  resetPassword,
  sendEmailVerification,
} from '../lib/verification.js';
import { requireUser } from './require-user.js';

const email = z.string().trim().toLowerCase().email().max(254);
// Long rather than complicated: length is what actually resists guessing, and
// composition rules mostly produce "Password1!".
const password = z.string().min(10).max(200);
const code = z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code');

const signUpBody = z.object({
  email,
  password,
  displayName: z.string().trim().min(1).max(80).optional(),
});
const signInBody = z.object({ email, password });
const confirmBody = z.object({ email, code });
const resendBody = z.object({ email });
const refreshBody = z.object({ refreshToken: z.string().min(1) });
const forgotBody = z.object({ email });
const resetBody = z.object({ email, code, password });

const agentOf = (request: FastifyRequest): string | undefined =>
  request.headers['user-agent'];

const sessionResponse = (session: Awaited<ReturnType<typeof issueSession>>) => ({
  ...session,
  expiresIn: ACCESS_TOKEN_TTL_SECONDS,
});

export async function authRoutes(
  app: FastifyInstance,
  opts: { mailer: Mailer },
): Promise<void> {
  const { mailer } = opts;

  app.post('/signup', async (request, reply) => {
    const body = signUpBody.parse(request.body);
    const user = await signUp(body.email, body.password, body.displayName);

    try {
      await sendEmailVerification(user.id, user.email, mailer);
    } catch (error) {
      // The account exists but the code never went out. Say so plainly instead
      // of a bare 500: the caller can retry, and signing up again with an
      // unconfirmed address resends rather than colliding.
      request.log.error({ err: error }, 'Verification email failed');
      throw new AuthError(
        502,
        'email_send_failed',
        'We could not send your confirmation email. Please try again.',
      );
    }

    return reply.status(201).send({
      status: 'verification_required',
      email: user.email,
    });
  });

  app.post('/verify-email', async (request) => {
    const body = confirmBody.parse(request.body);
    await confirmEmail(body.email, body.code);
    return { status: 'verified' };
  });

  app.post('/resend-verification', async (request) => {
    const body = resendBody.parse(request.body);
    const user = await prisma.user.findUnique({ where: { email: body.email } });
    // Always the same answer, whether or not the address is registered.
    if (user && !user.emailVerified) {
      await sendEmailVerification(user.id, user.email, mailer);
    }
    return { status: 'sent' };
  });

  app.post('/signin', async (request) => {
    const body = signInBody.parse(request.body);
    const session = await signIn(body.email, body.password, agentOf(request));
    return sessionResponse(session);
  });

  app.post('/refresh', async (request) => {
    const body = refreshBody.parse(request.body);
    const session = await rotate(body.refreshToken, agentOf(request));
    return sessionResponse(session);
  });

  app.post('/signout', async (request) => {
    const body = refreshBody.parse(request.body);
    await signOut(body.refreshToken);
    return { status: 'signed_out' };
  });

  app.post('/forgot-password', async (request) => {
    const body = forgotBody.parse(request.body);
    await requestPasswordReset(body.email, mailer);
    // Deliberately identical for known and unknown addresses.
    return { status: 'sent' };
  });

  app.post('/reset-password', async (request) => {
    const body = resetBody.parse(request.body);
    await resetPassword(body.email, body.code, body.password);
    return { status: 'reset' };
  });

  app.get('/me', async (request) => {
    const userId = await requireUser(request);
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new AuthError(401, 'unauthorized', 'Please sign in again');

    return {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
      createdAt: user.createdAt.toISOString(),
    };
  });
}
