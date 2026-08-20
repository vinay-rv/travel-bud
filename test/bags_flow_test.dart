import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/bag.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/models/item_category.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/screens/trip_detail_screen.dart';
import 'package:packmate/theme/app_theme.dart';
import 'package:packmate/widgets/app_bottom_bar.dart';

// See trip_flow_test.dart for why DB work runs inside runAsync and why we avoid
// pumpAndSettle.
Future<T> real<T>(WidgetTester tester, Future<T> Function() op) async {
  late T result;
  await tester.runAsync(() async {
    result = await op();
  });
  return result;
}

// Ten passes rather than the usual six: deleting a bag is several round trips
// (unassign each item, then remove the bag), and the list only rebuilds once
// they have all landed.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

const _timeout = Timeout(Duration(seconds: 30));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late Trip trip;

  setUp(() async {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    trip = await db.createTrip(Trip(
      name: 'Northeast India',
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 3, 8),
    ));
  });

  tearDown(() async => db.close());

  Future<void> openItemsTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: TripDetailScreen(trip: trip, db: db),
    ));
    await settle(tester);
    await tester.tap(find.text('Items'));
    await settle(tester);
  }

  Future<void> groupByBag(WidgetTester tester) async {
    await tester.tap(find.text('Bag'));
    await settle(tester);
  }

  Future<Item> seedItem(
    WidgetTester tester,
    String name, {
    int? bagId,
    ItemCategory category = ItemCategory.other,
  }) {
    return real(
      tester,
      () => db.createItem(Item(
        tripId: trip.id!,
        name: name,
        category: category,
        bagId: bagId,
      )),
    );
  }

  Future<Bag> seedBag(WidgetTester tester, String name) {
    return real(tester, () => db.createBag(Bag(tripId: trip.id!, name: name)));
  }

  testWidgets('the list can be regrouped from categories to bags',
      (tester) async {
    final bag = await seedBag(tester, 'Cabin bag');
    await seedItem(tester, 'Jacket',
        bagId: bag.id, category: ItemCategory.clothes);
    await openItemsTab(tester);

    // Categories to begin with.
    expect(find.text('Clothes'), findsOneWidget);
    expect(find.text('Cabin bag'), findsOneWidget); // the row's bag tag

    await groupByBag(tester);

    // Now the section is the bag, and the category heading is gone.
    expect(find.text('Clothes'), findsNothing);
    expect(find.text('Cabin bag'), findsOneWidget);
    expect(find.text('Jacket'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('an item shows which bag it is in when grouped by category',
      (tester) async {
    final bag = await seedBag(tester, 'Rucksack');
    await seedItem(tester, 'Charger', bagId: bag.id);
    await seedItem(tester, 'Hat');
    await openItemsTab(tester);

    // The tag is on the row that has a bag, and only that one.
    expect(find.text('Rucksack'), findsOneWidget);
    expect(find.text('Charger'), findsOneWidget);
    expect(find.text('Hat'), findsOneWidget);

    // Grouped by bag the header already says it, so the tag would be noise.
    await groupByBag(tester);
    expect(find.text('Rucksack'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('items with no bag are gathered under their own heading',
      (tester) async {
    final bag = await seedBag(tester, 'Cabin bag');
    await seedItem(tester, 'Passport', bagId: bag.id);
    await seedItem(tester, 'Hat');
    await openItemsTab(tester);
    await groupByBag(tester);

    expect(find.text('Cabin bag'), findsOneWidget);
    // The catch-all section is last, so it starts below the fold.
    await tester.drag(find.byType(ListView).last, const Offset(0, -200));
    await settle(tester);
    expect(find.text('No bag'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('a bag is created from the list and an item moved into it',
      (tester) async {
    await seedItem(tester, 'Passport');
    await openItemsTab(tester);
    await groupByBag(tester);

    // Nothing is in a bag, so the whole list sits under "No bag".
    expect(find.text('No bag'), findsOneWidget);

    // The "New bag" card is the last thing in the list, so it starts behind
    // the bottom bar.
    await tester.ensureVisible(find.text('New bag'));
    await settle(tester);
    await tester.tap(find.text('New bag'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Cabin bag');
    await tester.tap(find.widgetWithText(FilledButton, 'Add bag'));
    await settle(tester);

    // The bag exists, and is shown even though nothing is in it yet.
    expect(find.text('Cabin bag'), findsOneWidget);
    expect(find.text('Nothing in here yet'), findsOneWidget);

    // Scroll the row clear of the bottom bar before reaching for its menu,
    // then use the last menu on screen — the new bag's section header has one
    // too.
    await tester.drag(find.byType(ListView).last, const Offset(0, -160));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await settle(tester);
    await tester.tap(find.text('Put in a bag'));
    await settle(tester);
    await tester.tap(find.text('Cabin bag').last);
    await settle(tester);

    expect(find.text('Nothing in here yet'), findsNothing);
    final stored = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(stored.single.bagId, isNotNull);
  }, timeout: _timeout);

  testWidgets('an item can be taken back out of its bag', (tester) async {
    final bag = await seedBag(tester, 'Cabin bag');
    final item = await seedItem(tester, 'Passport', bagId: bag.id);
    await openItemsTab(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text('Move to bag'));
    await settle(tester);
    await tester.tap(find.text('No bag'));
    await settle(tester);

    final stored = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(stored.single.id, item.id);
    expect(stored.single.bagId, isNull);
  }, timeout: _timeout);

  testWidgets('a bag is renamed from its section header', (tester) async {
    // Not called "Bag" — that is also the label of the group-by control.
    final bag = await seedBag(tester, 'Duffel');
    await seedItem(tester, 'Passport', bagId: bag.id);
    await openItemsTab(tester);
    await groupByBag(tester);

    // The section header's menu, not the item row's.
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settle(tester);
    await tester.tap(find.text('Rename bag'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Cabin bag');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.text('Cabin bag'), findsOneWidget);
    expect(find.text('Duffel'), findsNothing);
    final stored = await real(tester, () => db.getBagsForTrip(trip.id!));
    expect(stored.single.name, 'Cabin bag');
  }, timeout: _timeout);

  testWidgets('deleting a bag keeps what was in it', (tester) async {
    final bag = await seedBag(tester, 'Cabin bag');
    await seedItem(tester, 'Passport', bagId: bag.id);
    await openItemsTab(tester);
    await groupByBag(tester);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    // The warning says what happens to the contents.
    expect(find.textContaining('stay on your packing list'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(find.text('Cabin bag'), findsNothing);
    // The item survives, now unassigned.
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('No bag'), findsOneWidget);
    final stored = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(stored.single.bagId, isNull);
  }, timeout: _timeout);

  testWidgets('a bag section packs only its own items', (tester) async {
    final cabin = await seedBag(tester, 'Cabin bag');
    await seedItem(tester, 'Passport', bagId: cabin.id);
    await seedItem(tester, 'Hat');
    await openItemsTab(tester);
    await groupByBag(tester);

    // The bag's own pack-all, which is the first one on screen.
    await tester.tap(find.text('Pack all').at(1));
    await settle(tester);

    final stored = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(stored.firstWhere((i) => i.name == 'Passport').packed, isTrue);
    expect(stored.firstWhere((i) => i.name == 'Hat').packed, isFalse);
  }, timeout: _timeout);

  testWidgets('a bag is chosen while adding an item', (tester) async {
    await seedBag(tester, 'Cabin bag');
    await openItemsTab(tester);

    await tester.tap(find.byType(AppBottomBarAction));
    await settle(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Item name'), 'Passport');
    await tester.tap(find.text('Cabin bag'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add item'));
    await settle(tester);

    final stored = await real(tester, () => db.getItemsForTrip(trip.id!));
    final bags = await real(tester, () => db.getBagsForTrip(trip.id!));
    expect(stored.single.bagId, bags.single.id);
  }, timeout: _timeout);
}
