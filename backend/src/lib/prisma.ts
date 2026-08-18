import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();

/**
 * Epoch milliseconds from the *server* clock.
 *
 * Every `updatedAt` in this service comes from here and never from a client.
 * The client uses these values as a sync cursor, so a device with a clock set
 * to next year could otherwise write a timestamp that suppresses its own future
 * pulls — and everyone else's.
 */
export const nowMs = (): bigint => BigInt(Date.now());
