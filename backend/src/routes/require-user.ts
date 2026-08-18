import type { FastifyRequest } from 'fastify';

import { AuthError } from '../lib/auth.js';
import { verifyAccessToken } from '../lib/tokens.js';

/**
 * The caller's user id, from the bearer token.
 *
 * Every data route starts here, and every query is then scoped by what it
 * returns. There is no row level security underneath this service: a route that
 * forgets to filter by this id serves one user another's trips.
 */
export async function requireUser(request: FastifyRequest): Promise<string> {
  const header = request.headers.authorization;
  const token = header?.startsWith('Bearer ') ? header.slice(7) : null;
  const userId = token ? await verifyAccessToken(token) : null;

  if (!userId) {
    throw new AuthError(401, 'unauthorized', 'Please sign in again');
  }
  return userId;
}
