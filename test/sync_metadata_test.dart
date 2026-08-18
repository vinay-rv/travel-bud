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

/// Covers the v4 sync groundwork: every row carries a uuid and a dirty flag,
/// every delete leaves a tombstone, and an existing database picks all of that
/// up without losing anything — including its integer ids, which notification
/// ids are derived from.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Trip> seedTrip() => db.createTrip(Trip(
    name: 'Northeast India',
    startDate: DateTime(2026, 3, 1),
    endDate: DateTime(2026, 3, 8),
  ));

  /// Raw row read, so tests can see the sync columns the models deliberately
  /// don't carry.
  Future<List<Map<String, Object?>>> rawRows(String table) async {
    final database = await db.database;
    return database.query(table, orderBy: 'id ASC');
  }

  Future<List<Map<String, Object?>>> tombstones() async {
    final database = await db.database;
    return database.query(
      DatabaseHelper.tableTombstone,
      orderBy: 'tableName ASC, uuid ASC',
    );
  }

  final uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  group('Stamping', () {
    test('a new row gets a uuid, a timestamp, and is dirty', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await seedTrip();

      final row = (await rawRows(DatabaseHelper.tableTrip)).single;
      expect(row['uuid'], matches(uuidPattern));
      expect(row['dirty'], 1);
      expect(row['updatedAt'], greaterThanOrEqualTo(before));
      expect(row['serverUpdatedAt'], isNull);
    });

    test('every table stamps its inserts', () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Hotel Polo Towers',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 4, 11),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
      final list = await db.createPackingList('Hill trek');
      await db.addPackingListEntry(
        PackingListEntry(listId: list.id!, name: 'Fleece'),
      );

      for (final table in [
        DatabaseHelper.tableTrip,
        DatabaseHelper.tableStay,
        DatabaseHelper.tableItem,
        DatabaseHelper.tablePackingList,
        DatabaseHelper.tablePackingListItem,
      ]) {
        final rows = await rawRows(table);
        expect(rows, isNotEmpty, reason: '$table should have a row');
        for (final row in rows) {
          expect(row['uuid'], matches(uuidPattern), reason: table);
          expect(row['dirty'], 1, reason: table);
        }
      }
    });

    test('uuids are unique across rows', () async {
      final trip = await seedTrip();
      for (var i = 0; i < 10; i++) {
        await db.createItem(Item(tripId: trip.id!, name: 'Item $i'));
      }

      final uuids = (await rawRows(DatabaseHelper.tableItem))
          .map((row) => row['uuid'])
          .toSet();
      expect(uuids.length, 10);
    });

    test('an update re-dirties the row but keeps its uuid', () async {
      final trip = await seedTrip();
      final original = (await rawRows(DatabaseHelper.tableTrip)).single;

      // Simulate the row having been pushed already.
      final database = await db.database;
      await database.update(
        DatabaseHelper.tableTrip,
        {'dirty': 0, 'serverUpdatedAt': 1},
        where: 'id = ?',
        whereArgs: [trip.id],
      );

      await db.updateTrip(trip.copyWith(name: 'Renamed'));

      final updated = (await rawRows(DatabaseHelper.tableTrip)).single;
      expect(updated['name'], 'Renamed');
      expect(updated['dirty'], 1);
      // Identity to the server must survive an edit, or other devices would
      // see a delete followed by an insert.
      expect(updated['uuid'], original['uuid']);
    });

    test('partial-column writes stamp too', () async {
      final trip = await seedTrip();
      final item = await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
      final database = await db.database;

      Future<void> markClean() => database.update(
        DatabaseHelper.tableItem,
        {'dirty': 0},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      Future<Object?> dirtyFlag() async =>
          (await rawRows(DatabaseHelper.tableItem)).single['dirty'];

      await markClean();
      await db.setItemPacked(item.id!, true);
      expect(await dirtyFlag(), 1, reason: 'setItemPacked');

      await markClean();
      await db.setItemQuantity(item.id!, 3);
      expect(await dirtyFlag(), 1, reason: 'setItemQuantity');

      await markClean();
      await db.setAllItemsPacked(trip.id!, false);
      expect(await dirtyFlag(), 1, reason: 'setAllItemsPacked');
    });

    // These two build rows from raw column maps in a batch, bypassing the
    // per-row create methods — the easiest place for stamping to be forgotten.
    test('savePackingList stamps the list and its entries', () async {
      final trip = await seedTrip();
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'T-shirts',
        category: ItemCategory.clothes,
        quantity: 3,
      ));

      await db.savePackingList('Hill trek', await db.getItemsForTrip(trip.id!));

      final list = (await rawRows(DatabaseHelper.tablePackingList)).single;
      expect(list['uuid'], matches(uuidPattern));
      expect(list['dirty'], 1);

      final entry = (await rawRows(DatabaseHelper.tablePackingListItem)).single;
      expect(entry['uuid'], matches(uuidPattern));
      expect(entry['dirty'], 1);
    });

    test('applyPackingListToTrip stamps the items it creates', () async {
      final trip = await seedTrip();
      final list = await db.createPackingList('Hill trek');
      await db.addPackingListEntry(
        PackingListEntry(listId: list.id!, name: 'Head torch', quantity: 2),
      );

      final added = await db.applyPackingListToTrip(list.id!, trip.id!);
      expect(added, 1);

      final item = (await rawRows(DatabaseHelper.tableItem)).single;
      expect(item['uuid'], matches(uuidPattern));
      expect(item['dirty'], 1);
    });
  });

  group('Tombstones', () {
    test('deleting a row records it', () async {
      final trip = await seedTrip();
      final item = await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
      final uuid =
          (await rawRows(DatabaseHelper.tableItem)).single['uuid'] as String;

      await db.deleteItem(item.id!);

      final stones = await tombstones();
      final forItem = stones.firstWhere(
        (row) => row['tableName'] == DatabaseHelper.tableItem,
      );
      expect(forItem['uuid'], uuid);
      expect(forItem['dirty'], 1);
      expect(forItem['deletedAt'], isNotNull);
      // The row itself is really gone — no SELECT anywhere needs a filter.
      expect(await rawRows(DatabaseHelper.tableItem), isEmpty);
    });

    test('a cascaded delete tombstones the children too', () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Hotel Polo Towers',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 4, 11),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));

      await db.deleteTrip(trip.id!);

      final byTable = (await tombstones())
          .map((row) => row['tableName'])
          .toSet();
      // The children are removed by the foreign key cascade, not by us, so
      // this is really asserting that triggers fire for cascaded deletes.
      expect(
        byTable,
        containsAll([
          DatabaseHelper.tableTrip,
          DatabaseHelper.tableStay,
          DatabaseHelper.tableItem,
        ]),
      );
    });

    test('deleting a saved list tombstones its entries', () async {
      final list = await db.createPackingList('Hill trek');
      await db.addPackingListEntry(
        PackingListEntry(listId: list.id!, name: 'Fleece'),
      );

      await db.deletePackingList(list.id!);

      final byTable = (await tombstones())
          .map((row) => row['tableName'])
          .toSet();
      expect(
        byTable,
        containsAll([
          DatabaseHelper.tablePackingList,
          DatabaseHelper.tablePackingListItem,
        ]),
      );
    });

    test('re-deleting the same uuid updates rather than duplicating', () async {
      final database = await db.database;
      Future<void> tombstone(int at) => database.rawInsert('''
        INSERT INTO ${DatabaseHelper.tableTombstone}
          (tableName, uuid, deletedAt, dirty)
        VALUES ('trips', 'fixed-uuid', ?, 1)
        ON CONFLICT(tableName, uuid) DO UPDATE SET
          deletedAt = excluded.deletedAt, dirty = 1
      ''', [at]);

      await tombstone(1000);
      await tombstone(2000);

      final stones = await tombstones();
      expect(stones.length, 1);
      expect(stones.single['deletedAt'], 2000);
    });
  });

  group('Sync bookkeeping tables', () {
    test('a fresh database has them, empty', () async {
      // Force the schema to be created.
      await seedTrip();
      final database = await db.database;

      expect(await database.query(DatabaseHelper.tableSyncState), isEmpty);
      expect(await database.query(DatabaseHelper.tableSyncMeta), isEmpty);
      expect(await database.query(DatabaseHelper.tableTombstone), isEmpty);
    });
  });

  group('v3 to v4 migration', () {
    /// Builds a real v3 database on disk — the shape shipped before sync
    /// existed — and returns its path.
    Future<String> buildV3Database(Directory dir) async {
      final path = join(dir.path, 'v3.db');
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        ),
      );
      await legacy.execute('''
        CREATE TABLE trips (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          startDate INTEGER NOT NULL,
          endDate INTEGER NOT NULL
        )
      ''');
      await legacy.execute('''
        CREATE TABLE stays (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          hotelName TEXT NOT NULL,
          checkInAt INTEGER NOT NULL,
          checkOutAt INTEGER NOT NULL,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      await legacy.execute('''
        CREATE TABLE transport_legs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          type TEXT NOT NULL,
          departureAt INTEGER NOT NULL,
          fromLocation TEXT NOT NULL,
          toLocation TEXT NOT NULL,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      await legacy.execute('''
        CREATE TABLE items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'other',
          quantity INTEGER NOT NULL DEFAULT 1,
          packed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      await legacy.execute('''
        CREATE TABLE documents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          photoPath TEXT NOT NULL,
          label TEXT NOT NULL,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      await legacy.execute('''
        CREATE TABLE packing_lists (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          createdAt INTEGER NOT NULL
        )
      ''');
      await legacy.execute('''
        CREATE TABLE packing_list_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          listId INTEGER NOT NULL,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'other',
          quantity INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (listId) REFERENCES packing_lists (id) ON DELETE CASCADE
        )
      ''');

      final tripId = await legacy.insert('trips', {
        'name': 'Northeast India',
        'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
      });
      await legacy.insert('stays', {
        'tripId': tripId,
        'hotelName': 'Hotel Polo Towers',
        'checkInAt': DateTime(2026, 3, 1, 14).millisecondsSinceEpoch,
        'checkOutAt': DateTime(2026, 3, 4, 11).millisecondsSinceEpoch,
      });
      await legacy.insert('stays', {
        'tripId': tripId,
        'hotelName': 'Cherrapunji Homestay',
        'checkInAt': DateTime(2026, 3, 4, 15).millisecondsSinceEpoch,
        'checkOutAt': DateTime(2026, 3, 6, 10).millisecondsSinceEpoch,
      });
      await legacy.insert('items', {
        'tripId': tripId,
        'name': 'Passport',
        'category': 'documents',
        'quantity': 1,
        'packed': 1,
      });
      final listId = await legacy.insert('packing_lists', {
        'name': 'Hill trek',
        'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      });
      await legacy.insert('packing_list_items', {
        'listId': listId,
        'name': 'Fleece',
        'category': 'clothes',
        'quantity': 2,
      });
      await legacy.close();
      return path;
    }

    test('existing rows gain sync metadata and keep everything else', () async {
      final dir = await Directory.systemTemp.createTemp('packmate_v4');
      addTearDown(() => dir.delete(recursive: true));
      final path = await buildV3Database(dir);

      // Capture the pre-migration ids so we can prove they don't move.
      final before = await databaseFactory.openDatabase(path);
      final staysBefore = await before.query('stays', orderBy: 'id ASC');
      final idsBefore = staysBefore.map((row) => row['id']).toList();
      await before.close();

      final upgraded = DatabaseHelper.forTesting(path);
      addTearDown(upgraded.close);
      final database = await upgraded.database;

      for (final table in DatabaseHelper.syncedTables) {
        final rows = await database.query(table);
        for (final row in rows) {
          expect(row['uuid'], matches(uuidPattern), reason: table);
          // Everything predating sync is queued for the first push, which is
          // what makes claiming existing data free.
          expect(row['dirty'], 1, reason: table);
        }
      }

      // Integer ids must be untouched: notification ids are derived from stay
      // ids, so a shifted id would orphan every scheduled reminder.
      final staysAfter = await database.query('stays', orderBy: 'id ASC');
      expect(staysAfter.map((row) => row['id']).toList(), idsBefore);

      // Content and relationships survive.
      final trips = await upgraded.getTrips();
      expect(trips.single.name, 'Northeast India');
      final stays = await upgraded.getStaysForTrip(trips.single.id!);
      expect(stays.map((s) => s.hotelName), [
        'Hotel Polo Towers',
        'Cherrapunji Homestay',
      ]);
      final items = await upgraded.getItemsForTrip(trips.single.id!);
      expect(items.single.name, 'Passport');
      expect(items.single.category, ItemCategory.documents);
      expect(items.single.packed, isTrue);

      // And the bookkeeping the sync engine will need is in place.
      final catalogue = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type IN ('table','trigger')",
      );
      final names = catalogue.map((row) => row['name']).toSet();
      expect(names, contains(DatabaseHelper.tableSyncState));
      expect(names, contains(DatabaseHelper.tableTombstone));
      expect(names, contains(DatabaseHelper.tableSyncMeta));
      for (final table in DatabaseHelper.syncedTables) {
        expect(names, contains('trg_${table}_tombstone'));
      }
    });

    test('uuids assigned by the migration are unique', () async {
      final dir = await Directory.systemTemp.createTemp('packmate_v4_uniq');
      addTearDown(() => dir.delete(recursive: true));
      final path = await buildV3Database(dir);

      final upgraded = DatabaseHelper.forTesting(path);
      addTearDown(upgraded.close);
      final database = await upgraded.database;

      final stays = await database.query('stays');
      expect(stays.map((row) => row['uuid']).toSet().length, stays.length);
    });

    test('a migrated database still tombstones deletes', () async {
      final dir = await Directory.systemTemp.createTemp('packmate_v4_del');
      addTearDown(() => dir.delete(recursive: true));
      final path = await buildV3Database(dir);

      final upgraded = DatabaseHelper.forTesting(path);
      addTearDown(upgraded.close);

      final trip = (await upgraded.getTrips()).single;
      await upgraded.deleteTrip(trip.id!);

      final database = await upgraded.database;
      final stones = await database.query(DatabaseHelper.tableTombstone);
      expect(
        stones.map((row) => row['tableName']).toSet(),
        containsAll(['trips', 'stays', 'items']),
      );
    });

    test('a database stamped v4 but never migrated repairs itself', () async {
      // The failure mode that bit us on v3: the file claims to be current, so
      // onUpgrade will never run for it, but the columns aren't there.
      final dir = await Directory.systemTemp.createTemp('packmate_v4_stale');
      addTearDown(() => dir.delete(recursive: true));
      final path = join(dir.path, 'stale.db');

      final stale = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 4),
      );
      await stale.execute('''
        CREATE TABLE trips (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          startDate INTEGER NOT NULL,
          endDate INTEGER NOT NULL
        )
      ''');
      await stale.execute('''
        CREATE TABLE items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'other',
          quantity INTEGER NOT NULL DEFAULT 1,
          packed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      final tripId = await stale.insert('trips', {
        'name': 'Northeast India',
        'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
      });
      await stale.insert('items', {'tripId': tripId, 'name': 'Passport'});
      await stale.close();

      final repaired = DatabaseHelper.forTesting(path);
      addTearDown(repaired.close);

      // Writing works — this is the exact statement that failed in production.
      await repaired.createItem(Item(tripId: tripId, name: 'Charger'));

      final database = await repaired.database;
      final items = await database.query('items', orderBy: 'id ASC');
      expect(items.map((row) => row['name']), ['Passport', 'Charger']);
      for (final row in items) {
        expect(row['uuid'], matches(uuidPattern));
      }
    });
  });
}
