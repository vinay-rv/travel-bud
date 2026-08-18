import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/models/item_category.dart';
import 'package:packmate/models/packing_list.dart';
import 'package:packmate/models/stay.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/sync/sync_engine.dart';
import 'package:packmate/sync/sync_remote.dart';

/// An in-memory stand-in for the server, in the same spirit as the hand-written
/// `FakePlatform` in reminder_scheduler_test.dart — no network, no plugin, and
/// every timestamp under the test's control.
class FakeRemote implements SyncRemote {
  FakeRemote({this.userId = 'user-1'});

  String? userId;

  /// table -> uuid -> stored row.
  final Map<String, Map<String, StoredRow>> tables = {};

  /// Stands in for the server's `now()`. Monotonic, so ordering is exact.
  int clock = 1000;

  bool offline = false;
  int pushUpsertCalls = 0;
  int pushDeleteCalls = 0;
  final List<int> upsertBatchSizes = [];

  int _tick() => ++clock;

  /// Ids handed out by [signInAnonymously], in order.
  final List<String> anonymousIds = ['anon-1', 'anon-2'];
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String?> currentUserId() async {
    if (offline) throw const SyncUnavailable('offline');
    return userId;
  }

  @override
  Future<String> signInAnonymously() async {
    if (offline) throw const SyncUnavailable('offline');
    final id = anonymousIds[signInCalls.clamp(0, anonymousIds.length - 1)];
    signInCalls++;
    userId = id;
    return id;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    userId = null;
  }

  @override
  Future<List<PushedRow>> pushUpserts(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    if (offline) throw const SyncUnavailable('offline');
    pushUpsertCalls++;
    upsertBatchSizes.add(rows.length);

    final store = tables.putIfAbsent(table, () => {});
    final pushed = <PushedRow>[];
    for (final row in rows) {
      final uuid = row['uuid'] as String;
      final at = _tick();
      store[uuid] = StoredRow(
        values: Map.of(row),
        serverUpdatedAt: at,
        // Postgres defaults user_id to auth.uid(); the client never sends it.
        userId: userId,
      );
      pushed.add(PushedRow(uuid: uuid, serverUpdatedAt: at));
    }
    return pushed;
  }

  @override
  Future<void> pushDeletes(List<Tombstone> deletes) async {
    if (offline) throw const SyncUnavailable('offline');
    pushDeleteCalls++;
    for (final tombstone in deletes) {
      final store = tables.putIfAbsent(tombstone.table, () => {});
      final at = _tick();
      final existing = store[tombstone.uuid];
      store[tombstone.uuid] = StoredRow(
        values: existing?.values ?? {'uuid': tombstone.uuid},
        serverUpdatedAt: at,
        deletedAt: tombstone.deletedAt,
        userId: existing?.userId ?? userId,
      );
    }
  }

  @override
  Future<List<RemoteRow>> pull(String table, {required int sinceMs}) async {
    if (offline) throw const SyncUnavailable('offline');
    final store = tables[table] ?? {};
    final rows =
        store.entries
            // Row level security: you only ever see your own rows.
            .where((e) => e.value.userId == userId)
            .where((e) => e.value.serverUpdatedAt > sinceMs)
            .map(
              (e) => RemoteRow(
                uuid: e.key,
                values: Map.of(e.value.values),
                serverUpdatedAt: e.value.serverUpdatedAt,
                deletedAt: e.value.deletedAt,
              ),
            )
            .toList()
          ..sort((a, b) => a.serverUpdatedAt.compareTo(b.serverUpdatedAt));
    return rows;
  }

  /// Simulates another device writing directly to the server. Defaults to the
  /// currently signed-in account.
  void seed(String table, Map<String, Object?> values, {String? owner}) {
    final store = tables.putIfAbsent(table, () => {});
    store[values['uuid'] as String] = StoredRow(
      values: Map.of(values),
      serverUpdatedAt: _tick(),
      userId: owner ?? userId,
    );
  }

  /// Live rows on the server across every account — deliberately not filtered
  /// by user, so tests can assert that one account's action left another
  /// account's data alone.
  int rowCount(String table) =>
      (tables[table] ?? {}).values.where((r) => r.deletedAt == null).length;
}

class StoredRow {
  final Map<String, Object?> values;
  final int serverUpdatedAt;
  final int? deletedAt;

  /// Who owns the row. The real server enforces this with row level security;
  /// without it here, a fake would hand every user everyone else's data and
  /// quietly hide bugs that production would expose.
  final String? userId;

  const StoredRow({
    required this.values,
    required this.serverUpdatedAt,
    this.deletedAt,
    this.userId,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late FakeRemote remote;
  late SyncEngine engine;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    remote = FakeRemote();
    engine = SyncEngine(db: db, remote: remote);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Trip> seedTrip([String name = 'Northeast India']) => db.createTrip(
    Trip(
      name: name,
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 3, 8),
    ),
  );

  Future<List<Map<String, Object?>>> rawRows(String table) async =>
      (await db.database).query(table, orderBy: 'id ASC');

  Future<Object?> dirtyOf(String table, int id) async {
    final rows = await (await db.database).query(
      table,
      columns: ['dirty'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.single['dirty'];
  }

  group('Guard rails', () {
    test('does nothing without an account', () async {
      await seedTrip();
      remote.userId = null;

      expect(await engine.sync(), SyncOutcome.noAccount);
      expect(remote.pushUpsertCalls, 0);
    });

    test('being offline is a quiet, ordinary outcome', () async {
      await seedTrip();
      remote.offline = true;

      // Notably: it returns rather than throwing, so a caller can fire and
      // forget without wrapping every call.
      expect(await engine.sync(), SyncOutcome.unavailable);
    });

    test('refuses to run for a different account than the data belongs to',
        () async {
      await seedTrip();
      expect(await engine.sync(), SyncOutcome.ok);
      expect(await engine.claimedUserId(), 'user-1');

      remote.userId = 'someone-else';
      final before = remote.rowCount(DatabaseHelper.tableTrip);

      expect(await engine.sync(), SyncOutcome.accountMismatch);
      // The important part: it did NOT push this device's trips into the
      // other account.
      expect(remote.rowCount(DatabaseHelper.tableTrip), before);
    });
  });

  group('Push', () {
    test('uploads local rows and marks them clean', () async {
      final trip = await seedTrip();

      expect(await engine.sync(), SyncOutcome.ok);

      expect(remote.rowCount(DatabaseHelper.tableTrip), 1);
      expect(await dirtyOf(DatabaseHelper.tableTrip, trip.id!), 0);
      final row = (await rawRows(DatabaseHelper.tableTrip)).single;
      expect(row['serverUpdatedAt'], isNotNull);
    });

    test('a second sync pushes nothing', () async {
      await seedTrip();
      await engine.sync();
      final callsAfterFirst = remote.pushUpsertCalls;

      expect(await engine.sync(), SyncOutcome.ok);
      expect(remote.pushUpsertCalls, callsAfterFirst);
    });

    test('an edit re-queues just that row', () async {
      final trip = await seedTrip();
      await engine.sync();

      await db.updateTrip(trip.copyWith(name: 'Renamed'));
      expect(await dirtyOf(DatabaseHelper.tableTrip, trip.id!), 1);

      await engine.sync();
      expect(await dirtyOf(DatabaseHelper.tableTrip, trip.id!), 0);
      final stored =
          remote.tables[DatabaseHelper.tableTrip]!.values.single.values;
      expect(stored['name'], 'Renamed');
    });

    test('children go up referencing their parent by uuid, not local id',
        () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Hotel Polo Towers',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 4, 11),
      ));

      await engine.sync();

      final tripUuid =
          (await rawRows(DatabaseHelper.tableTrip)).single['uuid'];
      final stay = remote.tables[DatabaseHelper.tableStay]!.values.single.values;
      expect(stay['tripUuid'], tripUuid);
      // The local integer key must never leave the device.
      expect(stay.containsKey('tripId'), isFalse);
      expect(stay.containsKey('id'), isFalse);
      expect(stay.containsKey('dirty'), isFalse);
    });

    test('large pushes are chunked', () async {
      final trip = await seedTrip();
      for (var i = 0; i < 25; i++) {
        await db.createItem(Item(tripId: trip.id!, name: 'Item $i'));
      }
      engine = SyncEngine(db: db, remote: remote, chunkSize: 10);

      await engine.sync();

      final itemBatches = remote.upsertBatchSizes.where((n) => n > 1).toList();
      expect(itemBatches, containsAllInOrder([10, 10, 5]));
      expect(remote.rowCount(DatabaseHelper.tableItem), 25);
    });
  });

  group('Pull', () {
    test('applies a row created elsewhere', () async {
      remote.seed(DatabaseHelper.tableTrip, {
        'uuid': 'trip-from-elsewhere',
        'name': 'Kerala Backwaters',
        'startDate': DateTime(2026, 5, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 5, 6).millisecondsSinceEpoch,
      });

      expect(await engine.sync(), SyncOutcome.ok);

      final trips = await db.getTrips();
      expect(trips.single.name, 'Kerala Backwaters');
      // Arrived from the server, so it must not be queued straight back.
      expect(await dirtyOf(DatabaseHelper.tableTrip, trips.single.id!), 0);
    });

    test('resolves a pulled child onto the local parent id', () async {
      final trip = await seedTrip();
      await engine.sync();
      final tripUuid =
          (await rawRows(DatabaseHelper.tableTrip)).single['uuid'] as String;

      remote.seed(DatabaseHelper.tableItem, {
        'uuid': 'item-from-elsewhere',
        'tripUuid': tripUuid,
        'name': 'Sunscreen',
        'category': 'hygiene',
        'quantity': 2,
        'packed': 0,
      });

      await engine.sync();

      final items = await db.getItemsForTrip(trip.id!);
      expect(items.single.name, 'Sunscreen');
      expect(items.single.category, ItemCategory.hygiene);
      expect(items.single.quantity, 2);
    });

    test('a child whose parent has not arrived is retried, not dropped',
        () async {
      // Item references a trip the server hasn't given us yet.
      remote.seed(DatabaseHelper.tableItem, {
        'uuid': 'orphan-item',
        'tripUuid': 'trip-not-here-yet',
        'name': 'Orphan',
        'category': 'other',
        'quantity': 1,
        'packed': 0,
      });

      await engine.sync();
      expect(await rawRows(DatabaseHelper.tableItem), isEmpty);

      // The parent shows up; the child must still land rather than having been
      // skipped past by an advanced cursor.
      remote.seed(DatabaseHelper.tableTrip, {
        'uuid': 'trip-not-here-yet',
        'name': 'Late Trip',
        'startDate': DateTime(2026, 5, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 5, 6).millisecondsSinceEpoch,
      });

      await engine.sync();

      final trips = await db.getTrips();
      final items = await db.getItemsForTrip(trips.single.id!);
      expect(items.single.name, 'Orphan');
    });

    test('a local edit outranks the version on the server', () async {
      final trip = await seedTrip();
      await engine.sync();
      final uuid =
          (await rawRows(DatabaseHelper.tableTrip)).single['uuid'] as String;

      // Someone else's change lands on the server...
      remote.tables[DatabaseHelper.tableTrip]![uuid] = StoredRow(
        values: {
          'uuid': uuid,
          'name': 'Server Name',
          'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
        },
        serverUpdatedAt: remote.clock + 500,
        userId: remote.userId,
      );
      // ...but this device has an unpushed edit of its own.
      await db.updateTrip(trip.copyWith(name: 'Local Name'));

      await engine.sync();

      // Local wins, and is what ends up on the server.
      expect((await db.getTrips()).single.name, 'Local Name');
      expect(
        remote.tables[DatabaseHelper.tableTrip]![uuid]!.values['name'],
        'Local Name',
      );
    });

    test('columns the local table does not have are ignored', () async {
      // The server carries things the app doesn't — user_id, the generated
      // timestamp twins — and a newer server may add more. An older client has
      // to shrug those off rather than failing on "no such column".
      remote.seed(DatabaseHelper.tableTrip, {
        'uuid': 'trip-with-extras',
        'name': 'Kerala Backwaters',
        'startDate': DateTime(2026, 5, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 5, 6).millisecondsSinceEpoch,
        'userId': 'user-1',
        'startAt': '2026-05-01T00:00:00Z',
        'somethingFromTheFuture': 'ignore me',
      });

      expect(await engine.sync(), SyncOutcome.ok);
      expect((await db.getTrips()).single.name, 'Kerala Backwaters');
    });

    test('re-pulling the same rows changes nothing', () async {
      final trip = await seedTrip();
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
      await engine.sync();

      // Rewind the cursor so everything is seen again.
      await (await db.database).delete(DatabaseHelper.tableSyncState);
      await engine.sync();

      expect((await db.getTrips()).length, 1);
      expect((await db.getItemsForTrip(trip.id!)).length, 1);
    });
  });

  group('Deletes', () {
    test('a local delete reaches the server', () async {
      final trip = await seedTrip();
      final item = await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
      await engine.sync();
      expect(remote.rowCount(DatabaseHelper.tableItem), 1);

      await db.deleteItem(item.id!);
      await engine.sync();

      expect(remote.rowCount(DatabaseHelper.tableItem), 0);
    });

    test('a cascaded delete reaches the server for the children too', () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Hotel Polo Towers',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 4, 11),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
      await engine.sync();

      await db.deleteTrip(trip.id!);
      await engine.sync();

      expect(remote.rowCount(DatabaseHelper.tableTrip), 0);
      expect(remote.rowCount(DatabaseHelper.tableStay), 0);
      expect(remote.rowCount(DatabaseHelper.tableItem), 0);
    });

    test('applying a remote delete does not echo it back forever', () async {
      final trip = await seedTrip();
      await engine.sync();
      final uuid =
          (await rawRows(DatabaseHelper.tableTrip)).single['uuid'] as String;

      // Deleted on another device.
      await remote.pushDeletes([
        Tombstone(
          table: DatabaseHelper.tableTrip,
          uuid: uuid,
          deletedAt: DateTime(2026, 2, 1).millisecondsSinceEpoch,
        ),
      ]);
      remote.pushDeleteCalls = 0;

      await engine.sync();
      expect(await db.getTrips(), isEmpty);
      expect(trip.id, isNotNull);

      // The local delete trigger fired while applying it. If that tombstone
      // stayed dirty we'd push the same deletion on every sync, forever.
      await engine.sync();
      expect(remote.pushDeleteCalls, 0);
    });

    test('a remote update does not manufacture a delete', () async {
      // Guards the INSERT OR REPLACE trap: replace deletes the row first, which
      // fires the tombstone trigger and invents a deletion out of an update.
      final trip = await seedTrip();
      await engine.sync();
      final uuid =
          (await rawRows(DatabaseHelper.tableTrip)).single['uuid'] as String;

      remote.tables[DatabaseHelper.tableTrip]![uuid] = StoredRow(
        values: {
          'uuid': uuid,
          'name': 'Renamed Elsewhere',
          'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
        },
        serverUpdatedAt: remote.clock + 500,
        userId: remote.userId,
      );

      await engine.sync();

      expect((await db.getTrips()).single.name, 'Renamed Elsewhere');
      final tombstones =
          await (await db.database).query(DatabaseHelper.tableTombstone);
      expect(tombstones, isEmpty);
      // And the local row keeps its identity rather than being re-created.
      expect(
        (await rawRows(DatabaseHelper.tableTrip)).single['id'],
        trip.id,
      );
    });
  });

  group('Two devices', () {
    /// Two genuinely separate databases.
    ///
    /// They have to be files: sqflite opens databases `singleInstance` by
    /// default, so two helpers pointed at `:memory:` share one handle and any
    /// "two device" test against them silently passes by testing one device.
    Future<(DatabaseHelper, DatabaseHelper)> twoDevices() async {
      final dir = await Directory.systemTemp.createTemp('packmate_devices');
      addTearDown(() => dir.delete(recursive: true));
      final phone = DatabaseHelper.forTesting(join(dir.path, 'phone.db'));
      final tablet = DatabaseHelper.forTesting(join(dir.path, 'tablet.db'));
      addTearDown(phone.close);
      addTearDown(tablet.close);
      return (phone, tablet);
    }

    test('converge on the same content with different local ids', () async {
      final (phone, tablet) = await twoDevices();

      final phoneSync = SyncEngine(db: phone, remote: remote);
      final tabletSync = SyncEngine(db: tablet, remote: remote);

      // Give the tablet a head start on local ids, so a row means a different
      // integer on each device — which is the whole point of the uuid column.
      for (var i = 0; i < 5; i++) {
        final throwaway = await tablet.createTrip(Trip(
          name: 'Scratch $i',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 2),
        ));
        await tablet.deleteTrip(throwaway.id!);
      }
      await (await tablet.database).delete(DatabaseHelper.tableTombstone);

      final phoneTrip = await phone.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      ));
      await phone.createItem(Item(
        tripId: phoneTrip.id!,
        name: 'Passport',
        category: ItemCategory.documents,
      ));

      await phoneSync.sync();
      await tabletSync.sync();

      final tabletTrips = await tablet.getTrips();
      expect(tabletTrips.single.name, 'Northeast India');
      final tabletItems = await tablet.getItemsForTrip(tabletTrips.single.id!);
      expect(tabletItems.single.name, 'Passport');
      expect(tabletItems.single.category, ItemCategory.documents);

      // Same row, same uuid, different local integer id — proof the identity
      // design actually holds.
      final phoneRow =
          (await (await phone.database).query(DatabaseHelper.tableTrip)).single;
      final tabletRow = (await (await tablet.database)
              .query(DatabaseHelper.tableTrip))
          .single;
      expect(tabletRow['uuid'], phoneRow['uuid']);
      expect(tabletRow['id'], isNot(phoneRow['id']));

      // Now the tablet edits and the phone picks it up.
      await tablet.updateTrip(
        tabletTrips.single.copyWith(name: 'Northeast India 2026'),
      );
      await tabletSync.sync();
      await phoneSync.sync();

      expect((await phone.getTrips()).single.name, 'Northeast India 2026');
    });

    test('a saved list and its entries survive the trip between devices',
        () async {
      final (phone, tablet) = await twoDevices();

      final list = await phone.createPackingList('Hill trek');
      await phone.addPackingListEntry(PackingListEntry(
        listId: list.id!,
        name: 'Head torch',
        category: ItemCategory.electronics,
        quantity: 2,
      ));

      await SyncEngine(db: phone, remote: remote).sync();
      await SyncEngine(db: tablet, remote: remote).sync();

      final lists = await tablet.getPackingLists();
      expect(lists.single.name, 'Hill trek');
      expect(lists.single.itemCount, 1);
      final entries = await tablet.getPackingListEntries(lists.single.id!);
      expect(entries.single.name, 'Head torch');
      expect(entries.single.quantity, 2);
      expect(entries.single.category, ItemCategory.electronics);
    });
  });

  group('Opting in', () {
    setUp(() {
      // Nobody is signed in until the user asks for backup.
      remote.userId = null;
    });

    test('creates an account and uploads what is already on the device',
        () async {
      final trip = await seedTrip();
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));

      expect(await engine.isBackingUp, isFalse);
      expect(await engine.enableBackup(), SyncOutcome.ok);

      expect(remote.signInCalls, 1);
      expect(await engine.claimedUserId(), 'anon-1');
      expect(remote.rowCount(DatabaseHelper.tableTrip), 1);
      expect(remote.rowCount(DatabaseHelper.tableItem), 1);
      expect(await engine.isBackingUp, isTrue);
      expect(await engine.lastSyncedAt(), isNotNull);
    });

    test('opting in with no connection leaves no half-finished state',
        () async {
      await seedTrip();
      remote.offline = true;

      expect(await engine.enableBackup(), SyncOutcome.unavailable);

      // No account, nothing uploaded, and the data is still queued for when
      // it does work.
      expect(await engine.claimedUserId(), isNull);
      expect(await engine.isBackingUp, isFalse);
      expect(remote.rowCount(DatabaseHelper.tableTrip), 0);
      final row = (await rawRows(DatabaseHelper.tableTrip)).single;
      expect(row['dirty'], 1);
    });

    test('opting in twice does not create a second account', () async {
      await seedTrip();
      await engine.enableBackup();
      await engine.enableBackup();

      expect(remote.signInCalls, 1);
    });
  });

  group('Opting out', () {
    test('keeps the data and re-queues it for whatever account comes next',
        () async {
      final trip = await seedTrip();
      await engine.sync();
      expect(await dirtyOf(DatabaseHelper.tableTrip, trip.id!), 0);

      await engine.disableBackup();

      expect(remote.signOutCalls, 1);
      expect(await engine.claimedUserId(), isNull);
      expect(await engine.lastSyncedAt(), isNull);
      // The phone is the source of truth: the trip is still here...
      expect((await db.getTrips()).single.name, 'Northeast India');
      // ...and is queued, so a future account receives it rather than the row
      // sitting there looking as though it had already been uploaded.
      expect(await dirtyOf(DatabaseHelper.tableTrip, trip.id!), 1);
    });
  });

  group('Signing into a different account', () {
    /// A device holding data claimed by 'user-1' where 'user-2' has now
    /// signed in, and 'user-2' already has a trip of their own on the server.
    Future<void> setUpMismatch() async {
      await seedTrip('This Device Trip');
      await engine.sync();

      remote.seed(DatabaseHelper.tableTrip, {
        'uuid': 'other-account-trip',
        'name': 'Account Trip',
        'startDate': DateTime(2026, 5, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 5, 6).millisecondsSinceEpoch,
      }, owner: 'user-2');
      remote.userId = 'user-2';
    }

    test('keeping this device hands its trips to the new account', () async {
      await setUpMismatch();
      expect(await engine.sync(), SyncOutcome.accountMismatch);

      await engine.resolveAccountMismatch(MismatchResolution.keepThisDevice);
      expect(await engine.sync(), SyncOutcome.ok);

      expect(await engine.claimedUserId(), 'user-2');
      final names = (await db.getTrips()).map((t) => t.name);
      expect(names, contains('This Device Trip'));
    });

    test('using the account discards the local copy without destroying the '
        'account data', () async {
      await setUpMismatch();
      expect(await engine.sync(), SyncOutcome.accountMismatch);

      final serverTripsBefore = remote.rowCount(DatabaseHelper.tableTrip);
      expect(serverTripsBefore, 2);

      await engine.resolveAccountMismatch(MismatchResolution.useTheAccount);

      // The local wipe fires every delete trigger. If those tombstones were
      // left queued, the next sync would push them and delete the very account
      // data the user just chose to keep — so this is the assertion that
      // matters most in the whole file.
      final tombstones =
          await (await db.database).query(DatabaseHelper.tableTombstone);
      expect(tombstones, isEmpty);

      expect(await engine.sync(), SyncOutcome.ok);

      expect(remote.rowCount(DatabaseHelper.tableTrip), serverTripsBefore);
      final names = (await db.getTrips()).map((t) => t.name);
      expect(names, contains('Account Trip'));
      expect(names, isNot(contains('This Device Trip')));
    });
  });

  group('Default wiring', () {
    test('the app-wide engine is inert until an account exists', () async {
      // Sync.instance must stay harmless: it is live in every existing test and
      // in the shipped app before anyone opts in.
      expect(await Sync.instance.sync(), SyncOutcome.noAccount);
    });
  });
}
