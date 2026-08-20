import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/data/remote_store.dart';
import 'package:packmate/models/bag.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/models/item_category.dart';
import 'package:packmate/models/stay.dart';
import 'package:packmate/models/trip.dart';

/// Records what reached the server, and can refuse to accept anything.
class FakeRemoteStore implements RemoteStore {
  final List<({String table, Map<String, Object?> row})> upserts = [];
  final List<({String table, String uuid})> removals = [];
  final Map<String, List<Map<String, Object?>>> contents = {};

  bool offline = false;

  @override
  Future<void> upsert(String table, Map<String, Object?> row) async {
    if (offline) throw const RemoteUnavailable('offline');
    upserts.add((table: table, row: row));
  }

  @override
  Future<void> remove(String table, String uuid) async {
    if (offline) throw const RemoteUnavailable('offline');
    removals.add((table: table, uuid: uuid));
  }

  @override
  Future<List<Map<String, Object?>>> fetchAll(String table) async {
    if (offline) throw const RemoteUnavailable('offline');
    return contents[table] ?? const [];
  }

  Map<String, Object?>? lastUpsertTo(String table) {
    for (final entry in upserts.reversed) {
      if (entry.table == table) return entry.row;
    }
    return null;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late FakeRemoteStore remote;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    remote = FakeRemoteStore();
    db.remote = remote;
  });

  tearDown(() async {
    await db.close();
  });

  Future<Trip> seedTrip() => db.createTrip(Trip(
    name: 'Northeast India',
    startDate: DateTime(2026, 3, 1),
    endDate: DateTime(2026, 3, 8),
  ));

  group('Bags travel as uuids', () {
    test('an item carries its bag as a uuid, not a local id', () async {
      final trip = await seedTrip();
      final bag = await db.createBag(Bag(tripId: trip.id!, name: 'Cabin bag'));
      await db.createItem(Item(
        tripId: trip.id!,
        name: 'Passport',
        bagId: bag.id,
      ));

      final bagSent = remote.lastUpsertTo('bags')!;
      expect(bagSent['name'], 'Cabin bag');
      expect(bagSent['tripUuid'], isNotNull);

      final sent = remote.lastUpsertTo('items')!;
      expect(sent['bagUuid'], bagSent['uuid']);
      // The local integer key means nothing off this device.
      expect(sent.containsKey('bagId'), isFalse);
    });

    test('an item in no bag sends an empty reference', () async {
      final trip = await seedTrip();
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));

      final sent = remote.lastUpsertTo('items')!;
      expect(sent.containsKey('bagUuid'), isTrue);
      expect(sent['bagUuid'], isNull);
    });

    test('moving an item between bags is sent', () async {
      final trip = await seedTrip();
      final cabin = await db.createBag(Bag(tripId: trip.id!, name: 'Cabin'));
      final hold = await db.createBag(Bag(tripId: trip.id!, name: 'Check-in'));
      final item = await db.createItem(Item(
        tripId: trip.id!,
        name: 'Boots',
        bagId: cabin.id,
      ));

      await db.setItemBag(item.id!, hold.id);

      final holdUuid = remote.lastUpsertTo('bags')!['uuid'];
      expect(remote.lastUpsertTo('items')!['bagUuid'], holdUuid);

      // And taking it out again clears the reference rather than leaving the
      // old bag behind.
      await db.setItemBag(item.id!, null);
      expect(remote.lastUpsertTo('items')!['bagUuid'], isNull);
    });

    test('a refresh rebuilds bag references from uuids', () async {
      remote.contents['trips'] = [
        {
          'uuid': 'trip-1',
          'name': 'Northeast India',
          'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
        },
      ];
      remote.contents['bags'] = [
        {'uuid': 'bag-1', 'tripUuid': 'trip-1', 'name': 'Cabin bag'},
      ];
      remote.contents['items'] = [
        {
          'uuid': 'item-1',
          'tripUuid': 'trip-1',
          'bagUuid': 'bag-1',
          'name': 'Passport',
          'category': 'documents',
          'quantity': 1,
          'packed': 0,
        },
        {
          'uuid': 'item-2',
          'tripUuid': 'trip-1',
          'bagUuid': null,
          'name': 'Hat',
          'category': 'other',
          'quantity': 1,
          'packed': 0,
        },
      ];

      await db.refreshFromServer();

      final trip = (await db.getTrips()).single;
      final bag = (await db.getBagsForTrip(trip.id!)).single;
      expect(bag.name, 'Cabin bag');

      final items = await db.getItemsForTrip(trip.id!);
      // The server's uuid became this device's local id.
      expect(items.firstWhere((i) => i.name == 'Passport').bagId, bag.id);
      expect(items.firstWhere((i) => i.name == 'Hat').bagId, isNull);
    });

    test('an item whose bag is missing is still kept, without one', () async {
      remote.contents['trips'] = [
        {
          'uuid': 'trip-1',
          'name': 'Northeast India',
          'startDate': DateTime(2026, 3, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 3, 8).millisecondsSinceEpoch,
        },
      ];
      remote.contents['items'] = [
        {
          'uuid': 'item-1',
          'tripUuid': 'trip-1',
          'bagUuid': 'bag-that-never-arrived',
          'name': 'Passport',
          'category': 'documents',
          'quantity': 1,
          'packed': 0,
        },
      ];

      await db.refreshFromServer();

      // Unlike a missing parent, a missing bag must not drop the item: an
      // unsorted thing to pack still has to be packed.
      final trip = (await db.getTrips()).single;
      final item = (await db.getItemsForTrip(trip.id!)).single;
      expect(item.name, 'Passport');
      expect(item.bagId, isNull);
    });

    test('deleting a bag sends the unassignments before the delete', () async {
      final trip = await seedTrip();
      final bag = await db.createBag(Bag(tripId: trip.id!, name: 'Cabin'));
      await db.createItem(
          Item(tripId: trip.id!, name: 'Passport', bagId: bag.id));
      remote.upserts.clear();

      await db.deleteBag(bag.id!);

      // The item is emptied out on the server first; if the bag went first the
      // server would be free to cascade the item away with it.
      expect(remote.upserts.map((u) => u.table), contains('items'));
      expect(remote.lastUpsertTo('items')!['bagUuid'], isNull);
      expect(remote.removals.single.table, 'bags');
    });
  });

  group('Writes reach the server', () {
    test('creating a trip sends it, without local-only columns', () async {
      await seedTrip();

      final sent = remote.lastUpsertTo('trips')!;
      expect(sent['name'], 'Northeast India');
      expect(sent['uuid'], isNotNull);
      // The local integer key and the cache bookkeeping never leave the device.
      expect(sent.containsKey('id'), isFalse);
      expect(sent.containsKey('dirty'), isFalse);
    });

    test('a child is sent referencing its parent by uuid', () async {
      final trip = await seedTrip();
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Hotel Polo Towers',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 4, 11),
      ));

      final tripUuid = remote.lastUpsertTo('trips')!['uuid'];
      final stay = remote.lastUpsertTo('stays')!;
      expect(stay['tripUuid'], tripUuid);
      expect(stay.containsKey('tripId'), isFalse);
    });

    test('an edit sends the whole row, not just what changed', () async {
      final trip = await seedTrip();
      remote.upserts.clear();

      await db.updateTrip(trip.copyWith(name: 'Renamed'));

      final sent = remote.lastUpsertTo('trips')!;
      expect(sent['name'], 'Renamed');
      // A partial row would blank the columns left out, because the server
      // upserts rather than patches.
      expect(sent['startDate'], isNotNull);
      expect(sent['endDate'], isNotNull);
    });

    test('deleting sends the removal', () async {
      final trip = await seedTrip();
      final uuid = remote.lastUpsertTo('trips')!['uuid'];

      await db.deleteTrip(trip.id!);

      expect(remote.removals.single.table, 'trips');
      expect(remote.removals.single.uuid, uuid);
    });

    test('the bulk pack-all sends every row it changed', () async {
      final trip = await seedTrip();
      await db.createItem(Item(
        tripId: trip.id!, name: 'T-shirts', category: ItemCategory.clothes));
      await db.createItem(Item(
        tripId: trip.id!, name: 'Jacket', category: ItemCategory.clothes));
      remote.upserts.clear();

      // One statement locally; the server has no bulk verb, so each row must
      // still go up or the change is lost on the next refresh.
      await db.setAllItemsPacked(trip.id!, true);

      final sentItems = remote.upserts.where((u) => u.table == 'items');
      expect(sentItems.length, 2);
      expect(sentItems.every((u) => u.row['packed'] == 1), isTrue);
    });

    test('saving a packing list sends the list and every entry', () async {
      final trip = await seedTrip();
      final items = [
        Item(tripId: trip.id!, name: 'Passport'),
        Item(tripId: trip.id!, name: 'Charger'),
      ];
      remote.upserts.clear();

      await db.savePackingList('Hill trek', items);

      expect(remote.upserts.where((u) => u.table == 'packing_lists').length, 1);
      expect(
        remote.upserts.where((u) => u.table == 'packing_list_items').length,
        2,
      );
    });
  });

  group('When the server cannot be reached', () {
    test('a write fails rather than caching something the server never saw',
        () async {
      remote.offline = true;

      await expectLater(seedTrip(), throwsA(isA<RemoteUnavailable>()));

      // Nothing cached: a row the server never accepted would simply vanish at
      // the next refresh, which is worse than an honest failure.
      expect(await db.getTrips(), isEmpty);
    });

    test('reading still works, because the cache is local', () async {
      await seedTrip();
      remote.offline = true;

      expect((await db.getTrips()).single.name, 'Northeast India');
    });
  });

  group('Refreshing from the server', () {
    test('replaces the cache, parents before children', () async {
      remote.contents['trips'] = [
        {
          'uuid': 'trip-1',
          'name': 'Kerala Backwaters',
          'startDate': DateTime(2026, 5, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 5, 6).millisecondsSinceEpoch,
          'userId': 'user-1',
        },
      ];
      remote.contents['items'] = [
        {
          'uuid': 'item-1',
          'tripUuid': 'trip-1',
          'name': 'Sunscreen',
          'category': 'hygiene',
          'quantity': 2,
          'packed': 0,
          'userId': 'user-1',
        },
      ];

      // Something stale on the device first, to prove it is replaced.
      remote.offline = false;
      await seedTrip();
      await db.refreshFromServer();

      final trips = await db.getTrips();
      expect(trips.single.name, 'Kerala Backwaters');
      final items = await db.getItemsForTrip(trips.single.id!);
      expect(items.single.name, 'Sunscreen');
      expect(items.single.category, ItemCategory.hygiene);
      expect(items.single.quantity, 2);
    });

    test('a failed fetch leaves the cache alone', () async {
      await seedTrip();
      remote.offline = true;

      await expectLater(
        db.refreshFromServer(),
        throwsA(isA<RemoteUnavailable>()),
      );

      // Half a refresh must not leave the phone with less than it had.
      expect((await db.getTrips()).single.name, 'Northeast India');
    });
  });
}
