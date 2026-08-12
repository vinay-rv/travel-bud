import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:trip_inventory_tracker/data/database_helper.dart';
import 'package:trip_inventory_tracker/models/trip.dart';
import 'package:trip_inventory_tracker/models/stay.dart';
import 'package:trip_inventory_tracker/models/transport_leg.dart';
import 'package:trip_inventory_tracker/models/item.dart';
import 'package:trip_inventory_tracker/models/document.dart';

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
    test('defaults to whole-trip (stayId null) and toggles packed', () async {
      final trip = await seedTrip();
      final item = await db.createItem(Item(
        tripId: trip.id!,
        name: 'Passport',
      ));
      expect(item.stayId, isNull);
      expect(item.isWholeTrip, isTrue);
      expect(item.packed, isFalse);

      await db.setItemPacked(item.id!, true);
      final items = await db.getItemsForTrip(trip.id!);
      expect(items.single.packed, isTrue);
    });

    test('getUnpackedItemsForStay returns whole-trip + this-stay unpacked',
        () async {
      final trip = await seedTrip();
      final stayA = await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'A',
        checkInAt: DateTime(2026, 3, 1),
        checkOutAt: DateTime(2026, 3, 4),
      ));
      final stayB = await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'B',
        checkInAt: DateTime(2026, 3, 4),
        checkOutAt: DateTime(2026, 3, 6),
      ));

      // Whole-trip unpacked.
      await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
      // Stay A unpacked -> should appear for A, not B.
      await db.createItem(
          Item(tripId: trip.id!, stayId: stayA.id, name: 'Room key deposit'));
      // Stay B unpacked -> should not appear for A.
      await db.createItem(
          Item(tripId: trip.id!, stayId: stayB.id, name: 'Spa slippers'));
      // Whole-trip but already packed -> excluded.
      final packed =
          await db.createItem(Item(tripId: trip.id!, name: 'Sunglasses'));
      await db.setItemPacked(packed.id!, true);

      final unpackedA = await db.getUnpackedItemsForStay(trip.id!, stayA.id!);
      final names = unpackedA.map((i) => i.name).toList();
      expect(names, containsAll(['Charger', 'Room key deposit']));
      expect(names, isNot(contains('Spa slippers')));
      expect(names, isNot(contains('Sunglasses')));
    });

    test('getUnpackedItemsForTrip returns every unpacked item', () async {
      final trip = await seedTrip();
      final stay = await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'A',
        checkInAt: DateTime(2026, 3, 1),
        checkOutAt: DateTime(2026, 3, 4),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
      await db.createItem(
          Item(tripId: trip.id!, stayId: stay.id, name: 'Room key'));

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

  group('Cascade delete', () {
    test('deleting a trip removes its stays, legs, items, documents',
        () async {
      final trip = await seedTrip();
      final stay = await db.createStay(Stay(
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
      await db.createItem(
          Item(tripId: trip.id!, stayId: stay.id, name: 'Room key'));
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

    test('deleting a stay removes its items but keeps whole-trip items',
        () async {
      final trip = await seedTrip();
      final stay = await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'A',
        checkInAt: DateTime(2026, 3, 1),
        checkOutAt: DateTime(2026, 3, 4),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
      await db.createItem(
          Item(tripId: trip.id!, stayId: stay.id, name: 'Room key'));

      await db.deleteStay(stay.id!);

      final items = await db.getItemsForTrip(trip.id!);
      expect(items.length, 1);
      expect(items.single.name, 'Passport');
    });
  });
}
