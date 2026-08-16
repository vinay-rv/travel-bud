import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/models/stay.dart';
import 'package:packmate/models/transport_leg.dart';
import 'package:packmate/models/item.dart';
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
