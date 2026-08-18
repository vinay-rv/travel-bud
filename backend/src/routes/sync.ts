/**
 * Sync endpoints, mirroring the Dart `SyncRemote` interface one for one.
 *
 * The single rule that matters here: **every statement is scoped by the caller's
 * user id.** There is no row level security under this service, so a forgotten
 * filter does not fail loudly — it quietly serves one person another person's
 * trips. That is why upserts never trust a uuid on its own, and why the tests
 * for this file are mostly about isolation rather than about syncing.
 *
 * Wire format is the app's own camelCase field names, which is also how these
 * columns are spelled in Postgres, so nothing has to be translated in between.
 */
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { AuthError } from '../lib/auth.js';
import { nowMs, prisma } from '../lib/prisma.js';
import { requireUser } from './require-user.js';

/** Rows returned by one pull. Enough to be useful, small enough to be quick. */
const PULL_LIMIT = 500;
const PUSH_LIMIT = 500;

const uuid = z.string().uuid();
const epochMs = z.coerce.number().int().nonnegative();

/**
 * What each syncable table accepts, and how it hangs off its parent.
 *
 * `delegate` is the Prisma model. `parent` is checked on every write: without
 * it, a client could attach its rows to somebody else's trip — the foreign key
 * would happily allow it, since keys know nothing about ownership.
 */
const tables = {
  trips: {
    delegate: () => prisma.trip,
    parent: null,
    schema: z.object({
      uuid,
      name: z.string().min(1).max(200),
      startDate: epochMs,
      endDate: epochMs,
    }),
  },
  stays: {
    delegate: () => prisma.stay,
    parent: { field: 'tripUuid', delegate: () => prisma.trip },
    schema: z.object({
      uuid,
      tripUuid: uuid,
      hotelName: z.string().min(1).max(200),
      checkInAt: epochMs,
      checkOutAt: epochMs,
    }),
  },
  transport_legs: {
    delegate: () => prisma.transportLeg,
    parent: { field: 'tripUuid', delegate: () => prisma.trip },
    schema: z.object({
      uuid,
      tripUuid: uuid,
      type: z.enum(['flight', 'train', 'bus']),
      departureAt: epochMs,
      fromLocation: z.string().min(1).max(200),
      toLocation: z.string().min(1).max(200),
    }),
  },
  items: {
    delegate: () => prisma.item,
    parent: { field: 'tripUuid', delegate: () => prisma.trip },
    schema: z.object({
      uuid,
      tripUuid: uuid,
      name: z.string().min(1).max(200),
      // Free text on purpose: an older server must not reject a category a
      // newer app knows about, because the app already falls back to "other".
      category: z.string().max(40).default('other'),
      quantity: z.coerce.number().int().min(1).max(999).default(1),
      packed: z.coerce.boolean().default(false),
    }),
  },
  packing_lists: {
    delegate: () => prisma.packingList,
    parent: null,
    schema: z.object({
      uuid,
      name: z.string().min(1).max(200),
      createdAt: epochMs,
    }),
  },
  packing_list_items: {
    delegate: () => prisma.packingListItem,
    parent: { field: 'listUuid', delegate: () => prisma.packingList },
    schema: z.object({
      uuid,
      listUuid: uuid,
      name: z.string().min(1).max(200),
      category: z.string().max(40).default('other'),
      quantity: z.coerce.number().int().min(1).max(999).default(1),
    }),
  },
} as const;

type TableName = keyof typeof tables;

const tableName = z.enum(
  Object.keys(tables) as [TableName, ...TableName[]],
);

const pushBody = z.object({
  table: tableName,
  rows: z.array(z.record(z.string(), z.unknown())).max(PUSH_LIMIT),
});

const deletesBody = z.object({
  deletes: z
    .array(z.object({ table: tableName, uuid, deletedAt: epochMs }))
    .max(PUSH_LIMIT),
});

const pullQuery = z.object({
  table: tableName,
  since: epochMs.default(0),
});

/** BigInt does not survive JSON.stringify, so timestamps go out as numbers. */
function serialise(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(row)) {
    out[key] = typeof value === 'bigint' ? Number(value) : value;
  }
  return out;
}

export async function syncRoutes(app: FastifyInstance): Promise<void> {
  app.post('/push', async (request) => {
    const userId = await requireUser(request);
    const body = pushBody.parse(request.body);
    const config = tables[body.table];
    const rows = body.rows.map((row) => config.schema.parse(row));

    // Every parent referenced in this batch, checked once and confirmed to
    // belong to the caller.
    if (config.parent && rows.length > 0) {
      const field = config.parent.field as 'tripUuid' | 'listUuid';
      const parentUuids = [
        ...new Set(
          rows.map((row) => (row as unknown as Record<string, string>)[field]),
        ),
      ];
      const owned = await (config.parent.delegate() as any).findMany({
        where: { uuid: { in: parentUuids }, userId },
        select: { uuid: true },
      });
      const ownedUuids = new Set(owned.map((row: { uuid: string }) => row.uuid));
      const stranger = parentUuids.find((value) => !ownedUuids.has(value));
      if (stranger) {
        throw new AuthError(
          403,
          'unknown_parent',
          'That trip or list does not belong to you',
        );
      }
    }

    const delegate = config.delegate() as any;
    const results: { uuid: string; updatedAt: number }[] = [];

    for (const row of rows) {
      const updatedAt = nowMs();
      const { uuid: rowUuid, ...fields } = row as Record<string, unknown> & {
        uuid: string;
      };

      // Scoped update first, then insert if it matched nothing. A plain upsert
      // keyed on uuid alone would let one user overwrite another's row simply
      // by guessing its id.
      const updated = await delegate.updateMany({
        where: { uuid: rowUuid, userId },
        data: { ...fields, updatedAt, deletedAt: null },
      });

      if (updated.count === 0) {
        const existing = await delegate.findUnique({
          where: { uuid: rowUuid },
          select: { userId: true },
        });
        if (existing) {
          throw new AuthError(
            403,
            'row_not_yours',
            'That row belongs to another account',
          );
        }
        await delegate.create({
          data: { ...fields, uuid: rowUuid, userId, updatedAt },
        });
      }

      results.push({ uuid: rowUuid, updatedAt: Number(updatedAt) });
    }

    return { rows: results };
  });

  app.post('/deletes', async (request) => {
    const userId = await requireUser(request);
    const body = deletesBody.parse(request.body);

    for (const entry of body.deletes) {
      const delegate = tables[entry.table].delegate() as any;
      // Soft delete: another device has to be able to learn about it. Scoped by
      // userId, so a uuid from elsewhere simply matches nothing.
      await delegate.updateMany({
        where: { uuid: entry.uuid, userId },
        data: { deletedAt: BigInt(entry.deletedAt), updatedAt: nowMs() },
      });
    }

    return { status: 'ok' };
  });

  app.get('/pull', async (request) => {
    const userId = await requireUser(request);
    const query = pullQuery.parse(request.query);
    const delegate = tables[query.table].delegate() as any;

    const rows = await delegate.findMany({
      where: { userId, updatedAt: { gt: BigInt(query.since) } },
      orderBy: { updatedAt: 'asc' },
      take: PULL_LIMIT,
    });

    return { rows: rows.map(serialise) };
  });
}
