import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/bag.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/models/item_category.dart';
import 'package:packmate/models/trip.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late int tripId;

  setUp(() async {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    final trip = await db.createTrip(Trip(
      name: 'Ladakh',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 6, 10),
    ));
    tripId = trip.id!;
  });

  tearDown(() async => db.close());

  Future<Item> addItem(String name, {int? bagId, ItemCategory? category}) {
    return db.createItem(Item(
      tripId: tripId,
      name: name,
      category: category ?? ItemCategory.other,
      bagId: bagId,
    ));
  }

  test('items start out in no bag', () async {
    final item = await addItem('Passport');
    expect(item.bagId, isNull);

    final stored = (await db.getItemsForTrip(tripId)).single;
    expect(stored.bagId, isNull);
  });

  test('an item can be put in a bag and taken back out', () async {
    final bag = await db.createBag(Bag(tripId: tripId, name: 'Cabin bag'));
    final item = await addItem('Charger');

    await db.setItemBag(item.id!, bag.id);
    expect((await db.getItemsForTrip(tripId)).single.bagId, bag.id);

    await db.setItemBag(item.id!, null);
    expect((await db.getItemsForTrip(tripId)).single.bagId, isNull);
  });

  test('bags are listed per trip, oldest first', () async {
    final cabin = await db.createBag(Bag(tripId: tripId, name: 'Cabin bag'));
    final check = await db.createBag(Bag(tripId: tripId, name: 'Check-in'));

    final other = await db.createTrip(Trip(
      name: 'Goa',
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 5),
    ));
    await db.createBag(Bag(tripId: other.id!, name: 'Rucksack'));

    final bags = await db.getBagsForTrip(tripId);
    expect(bags.map((b) => b.id), [cabin.id, check.id]);
    expect(bags.map((b) => b.name), ['Cabin bag', 'Check-in']);
  });

  test('renaming a bag leaves its items where they are', () async {
    final bag = await db.createBag(Bag(tripId: tripId, name: 'Bag'));
    final item = await addItem('Socks', bagId: bag.id);

    await db.renameBag(bag.id!, 'Rucksack');

    expect((await db.getBagsForTrip(tripId)).single.name, 'Rucksack');
    expect((await db.getItemsForTrip(tripId)).single.bagId, item.bagId);
  });

  test('deleting a bag keeps its items, unassigned', () async {
    final bag = await db.createBag(Bag(tripId: tripId, name: 'Cabin bag'));
    final kept = await db.createBag(Bag(tripId: tripId, name: 'Check-in'));
    await addItem('Toothbrush', bagId: bag.id);
    await addItem('Boots', bagId: kept.id);

    await db.deleteBag(bag.id!);

    final items = await db.getItemsForTrip(tripId);
    // The bag is gone; nothing that was inside it is.
    expect(items.map((i) => i.name), ['Toothbrush', 'Boots']);
    expect(items.firstWhere((i) => i.name == 'Toothbrush').bagId, isNull);
    // And a different bag is untouched.
    expect(items.firstWhere((i) => i.name == 'Boots').bagId, kept.id);
  });

  test('deleting a trip takes its bags with it', () async {
    await db.createBag(Bag(tripId: tripId, name: 'Cabin bag'));
    await db.deleteTrip(tripId);
    expect(await db.getBagsForTrip(tripId), isEmpty);
  });

  test('packing a bag packs only what is in it', () async {
    final cabin = await db.createBag(Bag(tripId: tripId, name: 'Cabin bag'));
    final hold = await db.createBag(Bag(tripId: tripId, name: 'Check-in'));
    await addItem('Passport', bagId: cabin.id);
    await addItem('Laptop', bagId: cabin.id);
    await addItem('Boots', bagId: hold.id);
    await addItem('Hat');

    final changed = await db.setBagItemsPacked(tripId, true, bagId: cabin.id);
    expect(changed, 2);

    final packed = (await db.getItemsForTrip(tripId))
        .where((i) => i.packed)
        .map((i) => i.name);
    expect(packed, ['Passport', 'Laptop']);
  });

  test('packing the unassigned group leaves bagged items alone', () async {
    final cabin = await db.createBag(Bag(tripId: tripId, name: 'Cabin bag'));
    await addItem('Passport', bagId: cabin.id);
    await addItem('Hat');
    await addItem('Sunglasses');

    final changed = await db.setBagItemsPacked(tripId, true, bagId: null);
    expect(changed, 2);

    final items = await db.getItemsForTrip(tripId);
    expect(items.firstWhere((i) => i.name == 'Passport').packed, isFalse);
    expect(items.where((i) => i.packed).map((i) => i.name),
        ['Hat', 'Sunglasses']);
  });

  test('packing by category still ignores bags', () async {
    final cabin = await db.createBag(Bag(tripId: tripId, name: 'Cabin bag'));
    await addItem('Passport',
        bagId: cabin.id, category: ItemCategory.documents);
    await addItem('Visa letter', category: ItemCategory.documents);
    await addItem('Shirt', bagId: cabin.id, category: ItemCategory.clothes);

    final changed = await db.setAllItemsPacked(
      tripId,
      true,
      category: ItemCategory.documents,
    );
    expect(changed, 2);

    final items = await db.getItemsForTrip(tripId);
    expect(items.firstWhere((i) => i.name == 'Shirt').packed, isFalse);
  });
}
