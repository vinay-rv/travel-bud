import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/models/stay.dart';
import 'package:packmate/models/transport_leg.dart';
import 'package:packmate/models/bag.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/models/item_category.dart';
import 'package:packmate/models/document.dart';

void main() {
  // Run sqflite against the FFI implementation so tests work on the host.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;

  setUp(() {
    // Fresh in-memory database per test.
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Trip> seedTrip() {
    return db.createTrip(Trip(
      name: 'Northeast India',
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 3, 8),
    ));
  }

  group('Trip CRUD', () {
    test('create assigns an id and reads back', () async {
      final trip = await seedTrip();
      expect(trip.id, isNotNull);

      final fetched = await db.getTrip(trip.id!);
      expect(fetched, isNotNull);
      expect(fetched!.name, 'Northeast India');
      expect(fetched.startDate, DateTime(2026, 3, 1));
      expect(fetched.endDate, DateTime(2026, 3, 8));
    });

    test('update and delete', () async {
      final trip = await seedTrip();
      final rows = await db.updateTrip(trip.copyWith(name: 'Renamed'));
      expect(rows, 1);
      expect((await db.getTrip(trip.id!))!.name, 'Renamed');

      await db.deleteTrip(trip.id!);
      expect(await db.getTrip(trip.id!), isNull);
      expect(await db.getTrips(), isEmpty);
    });
  });

  group('Stay CRUD', () {
    test('create, list ordered by checkout, delete', () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Second Hotel',
        checkInAt: DateTime(2026, 3, 4, 14),
        checkOutAt: DateTime(2026, 3, 6, 11),
      ));
      final first = await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'First Hotel',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 4, 11),
      ));

      final stays = await db.getStaysForTrip(trip.id!);
      expect(stays.length, 2);
      // Ordered by checkOutAt ASC.
      expect(stays.first.hotelName, 'First Hotel');

      await db.deleteStay(first.id!);
      expect((await db.getStaysForTrip(trip.id!)).length, 1);
    });
  });

  group('TransportLeg CRUD', () {
    test('type round-trips through enum name', () async {
      final trip = await seedTrip();
      final leg = await db.createTransportLeg(TransportLeg(
        tripId: trip.id!,
        type: TransportType.train,
        departureAt: DateTime(2026, 3, 4, 9),
        fromLocation: 'Guwahati',
        toLocation: 'Shillong',
      ));

      final fetched = await db.getTransportLeg(leg.id!);
      expect(fetched!.type, TransportType.train);
      expect(fetched.fromLocation, 'Guwahati');
      expect(fetched.toLocation, 'Shillong');
    });
  });

  group('Item CRUD and scoping', () {
    test('starts unpacked and toggles packed', () async {
      final trip = await seedTrip();
      final item = await db.createItem(Item(
        tripId: trip.id!,
        name: 'Passport',
      ));
      expect(item.packed, isFalse);

      await db.setItemPacked(item.id!, true);
      final items = await db.getItemsForTrip(trip.id!);
      expect(items.single.packed, isTrue);
    });

    test('getUnpackedItemsForTrip excludes packed items', () async {
      final trip = await seedTrip();
      await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
      await db.createItem(Item(tripId: trip.id!, name: 'Room key deposit'));
      final packed =
          await db.createItem(Item(tripId: trip.id!, name: 'Sunglasses'));
      await db.setItemPacked(packed.id!, true);

      final unpacked = await db.getUnpackedItemsForTrip(trip.id!);
      final names = unpacked.map((i) => i.name).toList();
      expect(names, containsAll(['Charger', 'Room key deposit']));
      expect(names, isNot(contains('Sunglasses')));
    });

    test('items are not tied to a stay, so every stay sees the full list',
        () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'A',
        checkInAt: DateTime(2026, 3, 1),
        checkOutAt: DateTime(2026, 3, 4),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
      await db.createItem(Item(tripId: trip.id!, name: 'Room key'));

      final unpacked = await db.getUnpackedItemsForTrip(trip.id!);
      expect(unpacked.length, 2);
    });
  });

  group('Document CRUD', () {
    test('create and list', () async {
      final trip = await seedTrip();
      await db.createDocument(Document(
        tripId: trip.id!,
        photoPath: '/local/path/passport.jpg',
        label: 'Passport',
      ));
      final docs = await db.getDocumentsForTrip(trip.id!);
      expect(docs.single.label, 'Passport');
      expect(docs.single.photoPath, '/local/path/passport.jpg');
    });
  });

  group('Categories and quantities', () {
    test('round-trip through the database', () async {
      final trip = await seedTrip();
      final item = await db.createItem(Item(
        tripId: trip.id!,
        name: 'T-shirts',
        category: ItemCategory.clothes,
        quantity: 3,
      ));

      final fetched = (await db.getItemsForTrip(trip.id!)).single;
      expect(fetched.category, ItemCategory.clothes);
      expect(fetched.quantity, 3);
      expect(fetched.displayName, 'T-shirts ×3');

      await db.setItemQuantity(item.id!, 5);
      expect((await db.getItemsForTrip(trip.id!)).single.quantity, 5);
    });

    test('defaults to Other and a quantity of one', () async {
      final trip = await seedTrip();
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));

      final fetched = (await db.getItemsForTrip(trip.id!)).single;
      expect(fetched.category, ItemCategory.other);
      expect(fetched.quantity, 1);
      expect(fetched.displayName, 'Passport');
    });

    test('quantity never drops below one', () async {
      final trip = await seedTrip();
      final item =
          await db.createItem(Item(tripId: trip.id!, name: 'Charger'));

      await db.setItemQuantity(item.id!, 0);
      expect((await db.getItemsForTrip(trip.id!)).single.quantity, 1);

      await db.setItemQuantity(item.id!, -4);
      expect((await db.getItemsForTrip(trip.id!)).single.quantity, 1);
    });
  });

  group('Bulk pack and unpack', () {
    Future<Trip> seedMixedItems() async {
      final trip = await seedTrip();
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'T-shirts',
        category: ItemCategory.clothes,
      ));
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'Jacket',
        category: ItemCategory.clothes,
      ));
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'Charger',
        category: ItemCategory.electronics,
      ));
      return trip;
    }

    test('packs and unpacks every item on the trip', () async {
      final trip = await seedMixedItems();

      final changed = await db.setAllItemsPacked(trip.id!, true);
      expect(changed, 3);
      expect(
        (await db.getItemsForTrip(trip.id!)).every((i) => i.packed),
        isTrue,
      );
      expect(await db.getUnpackedItemsForTrip(trip.id!), isEmpty);

      await db.setAllItemsPacked(trip.id!, false);
      expect(
        (await db.getItemsForTrip(trip.id!)).every((i) => !i.packed),
        isTrue,
      );
    });

    test('packs a single category, leaving the rest alone', () async {
      final trip = await seedMixedItems();

      final changed = await db.setAllItemsPacked(
        trip.id!,
        true,
        category: ItemCategory.clothes,
      );
      expect(changed, 2);

      final items = await db.getItemsForTrip(trip.id!);
      final packedNames =
          items.where((i) => i.packed).map((i) => i.name).toList();
      expect(packedNames, containsAll(['T-shirts', 'Jacket']));
      expect(packedNames, isNot(contains('Charger')));
    });

    test('leaves other trips untouched', () async {
      final trip = await seedMixedItems();
      final other = await db.createTrip(Trip(
        name: 'Goa',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 3),
      ));
      await db.createItem(Item(tripId: other.id!, name: 'Sunscreen'));

      await db.setAllItemsPacked(trip.id!, true);

      expect((await db.getItemsForTrip(other.id!)).single.packed, isFalse);
    });
  });

  group('Saved packing lists', () {
    Future<Trip> seedTripWithItems() async {
      final trip = await seedTrip();
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'T-shirts',
        category: ItemCategory.clothes,
        quantity: 3,
        packed: true,
      ));
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'Passport',
        category: ItemCategory.documents,
      ));
      return trip;
    }

    test('saving keeps names, categories and quantities but not packed state',
        () async {
      final trip = await seedTripWithItems();
      final items = await db.getItemsForTrip(trip.id!);

      final saved = await db.savePackingList('Hill trek', items);
      expect(saved.id, isNotNull);
      expect(saved.itemCount, 2);

      final entries = await db.getPackingListEntries(saved.id!);
      expect(entries.map((e) => e.name), ['T-shirts', 'Passport']);
      expect(entries.first.category, ItemCategory.clothes);
      expect(entries.first.quantity, 3);
      expect(entries.last.category, ItemCategory.documents);
    });

    test('lists come back newest first with their item counts', () async {
      final trip = await seedTripWithItems();
      final items = await db.getItemsForTrip(trip.id!);
      await db.savePackingList('Older', items.take(1).toList());
      await db.savePackingList('Newer', items);

      final lists = await db.getPackingLists();
      expect(lists.map((l) => l.name), ['Newer', 'Older']);
      expect(lists.first.itemCount, 2);
      expect(lists.last.itemCount, 1);
    });

    test('applying a list adds its items to another trip, unpacked', () async {
      final source = await seedTripWithItems();
      final saved = await db.savePackingList(
        'Hill trek',
        await db.getItemsForTrip(source.id!),
      );

      final next = await db.createTrip(Trip(
        name: 'Next trip',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 5),
      ));
      final added = await db.applyPackingListToTrip(saved.id!, next.id!);
      expect(added, 2);

      final items = await db.getItemsForTrip(next.id!);
      expect(items.map((i) => i.name), ['T-shirts', 'Passport']);
      expect(items.first.quantity, 3);
      expect(items.first.category, ItemCategory.clothes);
      // The source item was packed; the copy starts fresh.
      expect(items.every((i) => !i.packed), isTrue);
    });

    test('applying twice does not duplicate items', () async {
      final source = await seedTripWithItems();
      final saved = await db.savePackingList(
        'Hill trek',
        await db.getItemsForTrip(source.id!),
      );
      final next = await db.createTrip(Trip(
        name: 'Next trip',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 5),
      ));

      expect(await db.applyPackingListToTrip(saved.id!, next.id!), 2);
      expect(await db.applyPackingListToTrip(saved.id!, next.id!), 0);
      expect((await db.getItemsForTrip(next.id!)).length, 2);
    });

    test('a same-named item in another category is still added', () async {
      final trip = await seedTrip();
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'Charger',
        category: ItemCategory.electronics,
      ));
      final saved = await db.savePackingList('Chargers', [
        Item(
          tripId: trip.id!,
          name: 'charger',
          category: ItemCategory.electronics,
        ),
        Item(tripId: trip.id!, name: 'Charger', category: ItemCategory.other),
      ]);

      // The electronics one matches case-insensitively and is skipped; the
      // "other" one is a different line and lands.
      expect(await db.applyPackingListToTrip(saved.id!, trip.id!), 1);
      expect((await db.getItemsForTrip(trip.id!)).length, 2);
    });

    test('deleting a list removes its entries but not any trip items',
        () async {
      final trip = await seedTripWithItems();
      final saved = await db.savePackingList(
        'Hill trek',
        await db.getItemsForTrip(trip.id!),
      );

      await db.deletePackingList(saved.id!);

      expect(await db.getPackingLists(), isEmpty);
      expect(await db.getPackingListEntries(saved.id!), isEmpty);
      expect((await db.getItemsForTrip(trip.id!)).length, 2);
    });
  });

  group('Schema migration', () {
    test('v1 items survive the upgrade that drops stayId', () async {
      final dir = await Directory.systemTemp.createTemp('trip_db_migration');
      final path = join(dir.path, 'v1.db');
      addTearDown(() => dir.delete(recursive: true));

      // Build a v1 database by hand: items still carry a stayId.
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 1),
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
        CREATE TABLE items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          stayId INTEGER,
          name TEXT NOT NULL,
          packed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE,
          FOREIGN KEY (stayId) REFERENCES stays (id) ON DELETE CASCADE
        )
      ''');
      final tripId = await legacy.insert('trips', {
        'name': 'Northeast India',
        'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
      });
      final stayId = await legacy.insert('stays', {
        'tripId': tripId,
        'hotelName': 'Hotel Polo Towers',
        'checkInAt': DateTime(2026, 3, 1, 14).millisecondsSinceEpoch,
        'checkOutAt': DateTime(2026, 3, 4, 11).millisecondsSinceEpoch,
      });
      await legacy.insert('items', {
        'tripId': tripId,
        'stayId': null,
        'name': 'Passport',
        'packed': 0,
      });
      await legacy.insert('items', {
        'tripId': tripId,
        'stayId': stayId,
        'name': 'Room key deposit',
        'packed': 1,
      });
      await legacy.close();

      // Reopening through the helper runs the v2 upgrade.
      final upgraded = DatabaseHelper.forTesting(path);
      addTearDown(upgraded.close);

      final items = await upgraded.getItemsForTrip(tripId);
      expect(items.map((i) => i.name), ['Passport', 'Room key deposit']);
      // The formerly stay-scoped item is now a plain trip item, still packed.
      expect(items.last.packed, isTrue);
      // Deleting the stay no longer takes any item with it.
      await upgraded.deleteStay(stayId);
      expect((await upgraded.getItemsForTrip(tripId)).length, 2);

      // The same pass also brought items up to v3.
      expect(items.every((i) => i.category == ItemCategory.other), isTrue);
      expect(items.every((i) => i.quantity == 1), isTrue);

      // ...and on to v4. Worth asserting on this table specifically: the v1
      // step *rebuilds* `items` with pre-sync DDL, so the v4 step has to run
      // after it and catch the replacement.
      final database = await upgraded.database;
      final rows = await database.query('items');
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row['uuid'], isNotNull);
        expect(row['dirty'], 1);
      }
    });

    test('a database stamped current but missing v3 tables repairs itself',
        () async {
      // Reproduces "table items has no column named category": the file says
      // it is version 3, so onUpgrade will never run for it, but it was never
      // actually migrated (e.g. it was open across the version bump).
      final dir = await Directory.systemTemp.createTemp('trip_db_stale');
      final path = join(dir.path, 'stale.db');
      addTearDown(() => dir.delete(recursive: true));

      final stale = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 3),
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
          packed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      final tripId = await stale.insert('trips', {
        'name': 'Northeast India',
        'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
      });
      await stale
          .insert('items', {'tripId': tripId, 'name': 'Passport', 'packed': 0});
      await stale.close();

      final repaired = DatabaseHelper.forTesting(path);
      addTearDown(repaired.close);

      // Writing an item with the new columns now works.
      await repaired.createItem(Item(
        tripId: tripId,
        name: 'T-shirts',
        category: ItemCategory.clothes,
        quantity: 3,
      ));
      final items = await repaired.getItemsForTrip(tripId);
      expect(items.map((i) => i.name), ['Passport', 'T-shirts']);
      expect(items.first.category, ItemCategory.other);
      expect(items.last.quantity, 3);

      // The missing saved-list tables were rebuilt too.
      expect(await repaired.getPackingLists(), isEmpty);
      await repaired.savePackingList('Rebuilt', items);
      expect((await repaired.getPackingLists()).single.itemCount, 2);
    });

    test('v2 items gain a category and quantity, and saved lists appear',
        () async {
      final dir = await Directory.systemTemp.createTemp('trip_db_v2');
      final path = join(dir.path, 'v2.db');
      addTearDown(() => dir.delete(recursive: true));

      // A v2 database: items are trip-scoped but have no category/quantity,
      // and there are no packing-list tables at all.
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 2),
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
        CREATE TABLE items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          name TEXT NOT NULL,
          packed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
        )
      ''');
      final tripId = await legacy.insert('trips', {
        'name': 'Northeast India',
        'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
      });
      await legacy
          .insert('items', {'tripId': tripId, 'name': 'Passport', 'packed': 0});
      await legacy
          .insert('items', {'tripId': tripId, 'name': 'Charger', 'packed': 1});
      await legacy.close();

      final upgraded = DatabaseHelper.forTesting(path);
      addTearDown(upgraded.close);

      final items = await upgraded.getItemsForTrip(tripId);
      expect(items.map((i) => i.name), ['Passport', 'Charger']);
      expect(items.every((i) => i.category == ItemCategory.other), isTrue);
      expect(items.every((i) => i.quantity == 1), isTrue);
      // Packed state is preserved across the upgrade.
      expect(items.last.packed, isTrue);

      // The new tables exist and work.
      expect(await upgraded.getPackingLists(), isEmpty);
      final saved = await upgraded.savePackingList('Reusable', items);
      expect((await upgraded.getPackingLists()).single.itemCount, 2);
      expect((await upgraded.getPackingListEntries(saved.id!)).length, 2);

      // A v2 file lands on v4 in the same pass, including the packing tables
      // that step 3 created moments earlier.
      final database = await upgraded.database;
      for (final table in ['items', 'packing_lists', 'packing_list_items']) {
        final rows = await database.query(table);
        expect(rows, isNotEmpty, reason: table);
        for (final row in rows) {
          expect(row['uuid'], isNotNull, reason: table);
        }
      }
    });

    test('v5 items gain a bag column and the bags table appears', () async {
      final dir = await Directory.systemTemp.createTemp('trip_db_v5');
      final path = join(dir.path, 'v5.db');
      addTearDown(() => dir.delete(recursive: true));

      // A v5 database: items know about categories and quantities, but there
      // are no bags and nothing to point at one.
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 5),
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
      final tripId = await legacy.insert('trips', {
        'name': 'Northeast India',
        'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
        'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
      });
      await legacy.insert('items', {
        'tripId': tripId,
        'name': 'Passport',
        'category': 'documents',
        'quantity': 1,
        'packed': 1,
      });
      await legacy.close();

      final upgraded = DatabaseHelper.forTesting(path);
      addTearDown(upgraded.close);

      // The existing item survives intact, in no bag — which is the truth
      // about a list written before bags existed.
      final before = await upgraded.getItemsForTrip(tripId);
      expect(before.single.name, 'Passport');
      expect(before.single.category, ItemCategory.documents);
      expect(before.single.packed, isTrue);
      expect(before.single.bagId, isNull);

      // And bags now work on the upgraded file.
      expect(await upgraded.getBagsForTrip(tripId), isEmpty);
      final bag = await upgraded.createBag(Bag(tripId: tripId, name: 'Cabin'));
      await upgraded.setItemBag(before.single.id!, bag.id);
      expect((await upgraded.getItemsForTrip(tripId)).single.bagId, bag.id);

      // Bags carry sync metadata like every other table.
      final database = await upgraded.database;
      final rows = await database.query('bags');
      expect(rows.single['uuid'], isNotNull);
    });

    test('a database stamped current but missing bags repairs itself',
        () async {
      // The same failure mode as the v3 case above: the file claims to be
      // current, so onUpgrade will never run for it again.
      final dir = await Directory.systemTemp.createTemp('trip_db_stale_bags');
      final path = join(dir.path, 'stale.db');
      addTearDown(() => dir.delete(recursive: true));

      final stale = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 6),
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
      await stale.close();

      final repaired = DatabaseHelper.forTesting(path);
      addTearDown(repaired.close);

      final bag = await repaired.createBag(Bag(tripId: tripId, name: 'Cabin'));
      final item = await repaired.createItem(Item(
        tripId: tripId,
        name: 'Charger',
        bagId: bag.id,
      ));
      expect((await repaired.getItemsForTrip(tripId)).single.bagId, item.bagId);
    });
  });

  group('Cascade delete', () {
    test('deleting a trip removes its stays, legs, items, documents',
        () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'A',
        checkInAt: DateTime(2026, 3, 1),
        checkOutAt: DateTime(2026, 3, 4),
      ));
      await db.createTransportLeg(TransportLeg(
        tripId: trip.id!,
        type: TransportType.flight,
        departureAt: DateTime(2026, 3, 8, 6),
        fromLocation: 'GAU',
        toLocation: 'DEL',
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
      await db.createItem(Item(tripId: trip.id!, name: 'Room key'));
      await db.createDocument(Document(
        tripId: trip.id!,
        photoPath: '/p.jpg',
        label: 'ID',
      ));

      await db.deleteTrip(trip.id!);

      expect(await db.getStaysForTrip(trip.id!), isEmpty);
      expect(await db.getTransportLegsForTrip(trip.id!), isEmpty);
      expect(await db.getItemsForTrip(trip.id!), isEmpty);
      expect(await db.getDocumentsForTrip(trip.id!), isEmpty);
    });

    test('deleting a stay leaves the packing list untouched', () async {
      final trip = await seedTrip();
      final stay = await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'A',
        checkInAt: DateTime(2026, 3, 1),
        checkOutAt: DateTime(2026, 3, 4),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
      await db.createItem(Item(tripId: trip.id!, name: 'Room key'));

      await db.deleteStay(stay.id!);

      final items = await db.getItemsForTrip(trip.id!);
      expect(items.map((i) => i.name), containsAll(['Passport', 'Room key']));
    });
  });
}
