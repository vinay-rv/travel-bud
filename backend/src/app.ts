/**
 * The Fastify app, built as a function so tests can construct one with a
 * capturing mailer and no network listener.
 */
import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import { ZodError } from 'zod';

import { AuthError } from './lib/auth.js';
import type { Mailer } from './lib/mailer.js';
import { authRoutes } from './routes/auth.js';
import { syncRoutes } from './routes/sync.js';

export type AppOptions = {
  mailer: Mailer;
  logger?: boolean;
};

export async function buildApp({
  mailer,
  logger = false,
}: AppOptions): Promise<FastifyInstance> {
  const app = Fastify({ logger });

  await app.register(cors, { origin: true });

  // One error shape for the whole API, so the client has exactly one thing to
  // parse. Unexpected errors are logged in full but reported as a bare 500:
  // stack traces and database messages are not the client's business.
  app.setErrorHandler((error: unknown, request, reply) => {
    if (error instanceof AuthError) {
      return reply
        .status(error.status)
        .send({ error: error.code, message: error.message });
    }
    if (error instanceof ZodError) {
      return reply.status(400).send({
        error: 'invalid_request',
        message: 'Some fields are missing or invalid',
        fields: error.issues.map((issue) => ({
          path: issue.path.join('.'),
          message: issue.message,
        })),
      });
    }
    const statusCode =
      typeof error === 'object' && error !== null && 'statusCode' in error
        ? (error as { statusCode?: number }).statusCode
        : undefined;

    if (statusCode === 429) {
      return reply.status(429).send({
        error: 'too_many_requests',
        message: 'Too many attempts. Try again shortly.',
      });
    }

    request.log.error({ err: error }, 'Unhandled error');
    return reply
      .status(statusCode && statusCode < 500 ? statusCode : 500)
      .send({ error: 'server_error', message: 'Something went wrong' });
  });

  app.get('/health', async () => ({ ok: true }));

  await app.register(authRoutes, { prefix: '/auth', mailer });
  await app.register(syncRoutes, { prefix: '/sync' });

  return app;
}
