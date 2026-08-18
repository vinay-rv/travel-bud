import { randomUUID } from 'node:crypto';

import { beforeEach, describe, expect, it } from 'vitest';

import { createVerifiedUser, get, post, prisma, resetDatabase } from './helpers.js';

const ALICE = 'alice@example.com';
const BOB = 'bob@example.com';

let alice: Awaited<ReturnType<typeof createVerifiedUser>>;
let bob: Awaited<ReturnType<typeof createVerifiedUser>>;

beforeEach(async () => {
  await resetDatabase();
  alice = await createVerifiedUser(ALICE);
  bob = await createVerifiedUser(BOB);
});

const trip = (uuid: string, name = 'Northeast India') => ({
  uuid,
  name,
  startDate: 1772323200000,
  endDate: 1772928000000,
});

const pushTrip = (token: string, uuid: string, name?: string) =>
  post('/sync/push', { table: 'trips', rows: [trip(uuid, name)] }, token);

const pull = (token: string, table: string, since = 0) =>
  get(`/sync/pull?table=${table}&since=${since}`, token);

describe('Push and pull', () => {
  it('round-trips a trip', async () => {
    const uuid = randomUUID();
    const pushed = await pushTrip(alice.accessToken, uuid);

    expect(pushed.statusCode).toBe(200);
    expect(pushed.json().rows[0]).toMatchObject({ uuid });
    // The server assigns the timestamp; it is the client's cursor.
    expect(pushed.json().rows[0].updatedAt).toBeGreaterThan(0);

    const pulled = await pull(alice.accessToken, 'trips');
    expect(pulled.json().rows).toHaveLength(1);
    expect(pulled.json().rows[0]).toMatchObject({ uuid, name: 'Northeast India' });
  });

  it('ignores a client-supplied updatedAt so a bad clock cannot poison the cursor',
    async () => {
      const uuid = randomUUID();
      await post('/sync/push', {
        table: 'trips',
        // A device that believes it is the year 2099.
        rows: [{ ...trip(uuid), updatedAt: 4102444800000 }],
      }, alice.accessToken);

      const row = (await pull(alice.accessToken, 'trips')).json().rows[0];
      expect(row.updatedAt).toBeLessThan(4102444800000);
      expect(row.updatedAt).toBeGreaterThan(1700000000000);
    });

  it('only returns rows changed since the cursor', async () => {
    await pushTrip(alice.accessToken, randomUUID(), 'First');
    const cursor = (await pull(alice.accessToken, 'trips')).json().rows[0].updatedAt;

    await pushTrip(alice.accessToken, randomUUID(), 'Second');

    const since = await pull(alice.accessToken, 'trips', cursor);
    expect(since.json().rows.map((r: { name: string }) => r.name)).toEqual(['Second']);
  });

  it('updates an existing row rather than duplicating it', async () => {
    const uuid = randomUUID();
    await pushTrip(alice.accessToken, uuid, 'Original');
    await pushTrip(alice.accessToken, uuid, 'Renamed');

    const rows = (await pull(alice.accessToken, 'trips')).json().rows;
    expect(rows).toHaveLength(1);
    expect(rows[0].name).toBe('Renamed');
  });

  it('soft-deletes so other devices can learn about it', async () => {
    const uuid = randomUUID();
    await pushTrip(alice.accessToken, uuid);

    const deleted = await post('/sync/deletes', {
      deletes: [{ table: 'trips', uuid, deletedAt: Date.now() }],
    }, alice.accessToken);
    expect(deleted.statusCode).toBe(200);

    const rows = (await pull(alice.accessToken, 'trips')).json().rows;
    expect(rows).toHaveLength(1);
    expect(rows[0].deletedAt).toBeGreaterThan(0);
  });

  it('rejects a row whose shape is wrong', async () => {
    const bad = await post('/sync/push', {
      table: 'items',
      rows: [{ uuid: randomUUID(), tripUuid: randomUUID(), name: 'x', quantity: 0 }],
    }, alice.accessToken);

    expect(bad.statusCode).toBe(400);
  });

  it('refuses an unknown table', async () => {
    const response = await post('/sync/push', {
      table: 'users',
      rows: [],
    }, alice.accessToken);
    expect(response.statusCode).toBe(400);
  });
});

// Without row level security underneath, these are the tests standing between
// one user and another's data. They matter more than everything above.
describe('Isolation between accounts', () => {
  it('never returns another account\'s rows', async () => {
    await pushTrip(alice.accessToken, randomUUID(), 'Alice trip');

    const bobsPull = await pull(bob.accessToken, 'trips');
    expect(bobsPull.json().rows).toHaveLength(0);
  });

  it('refuses to overwrite a row belonging to someone else', async () => {
    const uuid = randomUUID();
    await pushTrip(alice.accessToken, uuid, 'Alice trip');

    // Bob knows the uuid and pushes over it.
    const attempt = await pushTrip(bob.accessToken, uuid, 'Hijacked');
    expect(attempt.statusCode).toBe(403);
    expect(attempt.json().error).toBe('row_not_yours');

    const alicesRow = (await pull(alice.accessToken, 'trips')).json().rows[0];
    expect(alicesRow.name).toBe('Alice trip');
  });

  it('refuses to delete a row belonging to someone else', async () => {
    const uuid = randomUUID();
    await pushTrip(alice.accessToken, uuid);

    const attempt = await post('/sync/deletes', {
      deletes: [{ table: 'trips', uuid, deletedAt: Date.now() }],
    }, bob.accessToken);
    // Scoped by user, so it matches nothing rather than erroring...
    expect(attempt.statusCode).toBe(200);
    // ...and Alice's trip is untouched.
    const alicesRow = (await pull(alice.accessToken, 'trips')).json().rows[0];
    expect(alicesRow.deletedAt).toBeNull();
  });

  it('refuses to hang a child off another account\'s trip', async () => {
    const tripUuid = randomUUID();
    await pushTrip(alice.accessToken, tripUuid);

    // The foreign key alone would allow this: keys know nothing about who owns
    // what, which is exactly why the route checks.
    const attempt = await post('/sync/push', {
      table: 'stays',
      rows: [{
        uuid: randomUUID(),
        tripUuid,
        hotelName: 'Bob was here',
        checkInAt: 1,
        checkOutAt: 2,
      }],
    }, bob.accessToken);

    expect(attempt.statusCode).toBe(403);
    expect(attempt.json().error).toBe('unknown_parent');
    expect(await prisma.stay.count()).toBe(0);
  });

  it('requires a token at all', async () => {
    expect((await post('/sync/push', { table: 'trips', rows: [] })).statusCode).toBe(401);
    expect((await get('/sync/pull?table=trips&since=0')).statusCode).toBe(401);
    expect((await post('/sync/deletes', { deletes: [] })).statusCode).toBe(401);
  });

  it('keeps two accounts fully separate across every table', async () => {
    const aliceTrip = randomUUID();
    const bobTrip = randomUUID();
    await pushTrip(alice.accessToken, aliceTrip, 'Alice');
    await pushTrip(bob.accessToken, bobTrip, 'Bob');

    await post('/sync/push', {
      table: 'items',
      rows: [{ uuid: randomUUID(), tripUuid: aliceTrip, name: 'Alice passport' }],
    }, alice.accessToken);
    await post('/sync/push', {
      table: 'items',
      rows: [{ uuid: randomUUID(), tripUuid: bobTrip, name: 'Bob charger' }],
    }, bob.accessToken);

    const alicesItems = (await pull(alice.accessToken, 'items')).json().rows;
    const bobsItems = (await pull(bob.accessToken, 'items')).json().rows;

    expect(alicesItems.map((r: { name: string }) => r.name)).toEqual(['Alice passport']);
    expect(bobsItems.map((r: { name: string }) => r.name)).toEqual(['Bob charger']);
  });
});

describe('The whole shape a client syncs', () => {
  it('accepts every syncable table', async () => {
    const tripUuid = randomUUID();
    const listUuid = randomUUID();
    await pushTrip(alice.accessToken, tripUuid);

    const pushes = [
      ['stays', { uuid: randomUUID(), tripUuid, hotelName: 'Hotel Polo Towers', checkInAt: 1, checkOutAt: 2 }],
      ['transport_legs', { uuid: randomUUID(), tripUuid, type: 'train', departureAt: 3, fromLocation: 'Guwahati', toLocation: 'Shillong' }],
      ['items', { uuid: randomUUID(), tripUuid, name: 'T-shirts', category: 'clothes', quantity: 3, packed: true }],
      ['packing_lists', { uuid: listUuid, name: 'Hill trek', createdAt: 4 }],
      ['packing_list_items', { uuid: randomUUID(), listUuid, name: 'Head torch', category: 'electronics', quantity: 2 }],
    ] as const;

    for (const [table, row] of pushes) {
      const response = await post('/sync/push', { table, rows: [row] }, alice.accessToken);
      expect(response.statusCode, `${table} push`).toBe(200);
    }

    const item = (await pull(alice.accessToken, 'items')).json().rows[0];
    expect(item).toMatchObject({ name: 'T-shirts', category: 'clothes', quantity: 3, packed: true });
  });
});
