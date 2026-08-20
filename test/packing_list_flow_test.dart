import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/models/item_category.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/models/packing_list.dart';
import 'package:packmate/screens/saved_list_detail_screen.dart';
import 'package:packmate/screens/saved_lists_screen.dart';
import 'package:packmate/screens/trip_detail_screen.dart';
import 'package:packmate/theme/app_theme.dart';

// See trip_flow_test.dart for why DB work runs inside runAsync and why we avoid
// pumpAndSettle.
Future<T> real<T>(WidgetTester tester, Future<T> Function() op) async {
  late T result;
  await tester.runAsync(() async {
    result = await op();
  });
  return result;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
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

  tearDown(() async {
    await db.close();
  });

  Future<void> openItemsTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: TripDetailScreen(trip: trip, db: db),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Items'));
    await settle(tester);
  }

  Future<void> seedItems(WidgetTester tester) => real(tester, () async {
    await db.createItem(Item(
      tripId: trip.id!,
      name: 'T-shirts',
      category: ItemCategory.clothes,
      quantity: 2,
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
  });

  testWidgets('items are grouped under their category headings',
      (tester) async {
    await seedItems(tester);
    await openItemsTab(tester);

    expect(find.text('Clothes'), findsOneWidget);
    // Categories with nothing in them stay hidden.
    expect(find.text('Hygiene'), findsNothing);
    expect(find.text('0/2'), findsOneWidget);

    // The last group sits below the fold on a small phone.
    await tester.drag(find.byType(ListView).last, const Offset(0, -200));
    await settle(tester);
    expect(find.text('Electronics'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('the + and − steppers change how many to bring', (tester) async {
    await real(
      tester,
      () => db.createItem(Item(
        tripId: trip.id!,
        name: 'T-shirts',
        category: ItemCategory.clothes,
        quantity: 2,
      )),
    );
    await openItemsTab(tester);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await settle(tester);
    expect((await real(tester, () => db.getItemsForTrip(trip.id!))).single.quantity, 3);

    await tester.tap(find.byIcon(Icons.remove_rounded).first);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.remove_rounded).first);
    await settle(tester);
    final items = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(items.single.quantity, 1);

    // At one, the minus is disabled rather than deleting the item.
    await tester.tap(find.byIcon(Icons.remove_rounded).first);
    await settle(tester);
    expect((await real(tester, () => db.getItemsForTrip(trip.id!))).single.quantity, 1);
  }, timeout: _timeout);

  testWidgets('Pack all packs just that category, then offers Unpack all',
      (tester) async {
    await seedItems(tester);
    await openItemsTab(tester);

    // The first "Pack all" belongs to the list header; the Clothes one follows.
    await tester.tap(find.text('Pack all').at(1));
    await settle(tester);

    final items = await real(tester, () => db.getItemsForTrip(trip.id!));
    final packed = items.where((i) => i.packed).map((i) => i.name);
    expect(packed, containsAll(['T-shirts', 'Jacket']));
    expect(packed, isNot(contains('Charger')));
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('Unpack all'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('the header packs and then unpacks every item', (tester) async {
    await seedItems(tester);
    await openItemsTab(tester);

    await tester.tap(find.text('Pack all').first);
    await settle(tester);
    expect(
      (await real(tester, () => db.getItemsForTrip(trip.id!)))
          .every((i) => i.packed),
      isTrue,
    );

    await tester.tap(find.text('Unpack all').first);
    await settle(tester);
    expect(
      (await real(tester, () => db.getItemsForTrip(trip.id!)))
          .every((i) => !i.packed),
      isTrue,
    );
  }, timeout: _timeout);

  testWidgets('saving the list keeps it for a later trip', (tester) async {
    await seedItems(tester);
    await openItemsTab(tester);

    await tester.tap(find.text('Save as list'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Hill trek');
    await tester.tap(find.widgetWithText(FilledButton, 'Save list'));
    await settle(tester);

    final lists = await real(tester, () => db.getPackingLists());
    expect(lists.single.name, 'Hill trek');
    expect(lists.single.itemCount, 3);
  }, timeout: _timeout);

  testWidgets('a saved list can be applied to another trip', (tester) async {
    late Trip next;
    await real(tester, () async {
      final items = [
        Item(
          tripId: trip.id!,
          name: 'T-shirts',
          category: ItemCategory.clothes,
          quantity: 2,
        ),
        Item(
          tripId: trip.id!,
          name: 'Passport',
          category: ItemCategory.documents,
        ),
      ];
      await db.savePackingList('Hill trek', items);
      next = await db.createTrip(Trip(
        name: 'Next trip',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 4),
      ));
    });

    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SavedListsScreen(applyToTripId: next.id!, db: db),
      ),
    );
    await settle(tester);

    expect(find.text('Hill trek'), findsOneWidget);
    expect(find.textContaining('2 items'), findsOneWidget);

    await tester.tap(find.text('Hill trek'));
    await settle(tester);

    final items = await real(tester, () => db.getItemsForTrip(next.id!));
    expect(items.map((i) => i.name), ['T-shirts', 'Passport']);
    expect(items.first.quantity, 2);
    expect(items.every((i) => !i.packed), isTrue);
  }, timeout: _timeout);

  testWidgets('items can be added straight into a saved list', (tester) async {
    final saved = await real(
      tester,
      () => db.savePackingList('Hill trek', [
        Item(
          tripId: trip.id!,
          name: 'Passport',
          category: ItemCategory.documents,
        ),
      ]),
    );

    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SavedListDetailScreen(list: saved, db: db),
      ),
    );
    await settle(tester);
    expect(find.text('Passport'), findsOneWidget);

    // A saved list is a pushed screen, not a place in the bottom bar, so it
    // keeps its own floating button.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Item'));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField), 'Rain jacket');
    await tester.tap(find.text('Clothes'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add item'));
    await settle(tester);

    // Back on the list, the new entry shows under its own category.
    expect(find.text('Rain jacket'), findsOneWidget);
    expect(find.text('Clothes'), findsOneWidget);

    final entries = await real(tester, () => db.getPackingListEntries(saved.id!));
    expect(entries.map((e) => e.name), ['Passport', 'Rain jacket']);
    expect(entries.last.category, ItemCategory.clothes);
    expect(entries.last.quantity, 2);
  }, timeout: _timeout);

  testWidgets('an added item travels to the next trip that uses the list',
      (tester) async {
    late Trip next;
    final saved = await real(tester, () async {
      final list = await db.createPackingList('Hill trek');
      await db.addPackingListEntry(PackingListEntry(
        listId: list.id!,
        name: 'Head torch',
        category: ItemCategory.electronics,
        quantity: 2,
      ));
      next = await db.createTrip(Trip(
        name: 'Next trip',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 4),
      ));
      return list;
    });

    final added =
        await real(tester, () => db.applyPackingListToTrip(saved.id!, next.id!));
    expect(added, 1);

    final items = await real(tester, () => db.getItemsForTrip(next.id!));
    expect(items.single.name, 'Head torch');
    expect(items.single.category, ItemCategory.electronics);
    expect(items.single.quantity, 2);
  }, timeout: _timeout);

  testWidgets('a list can be built from scratch on the saved lists screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: SavedListsScreen(db: db)),
    );
    await settle(tester);
    expect(find.text('No saved lists'), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'New list'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Work travel');
    await tester.tap(find.widgetWithText(FilledButton, 'Create list'));
    await settle(tester);

    // Lands straight in the new, empty list, ready to add to.
    expect(find.text('Nothing in this list'), findsOneWidget);

    final lists = await real(tester, () => db.getPackingLists());
    expect(lists.single.name, 'Work travel');
    expect(lists.single.itemCount, 0);
  }, timeout: _timeout);

  testWidgets('a saved list item can be removed', (tester) async {
    final saved = await real(
      tester,
      () => db.savePackingList('Hill trek', [
        Item(tripId: trip.id!, name: 'Passport'),
        Item(tripId: trip.id!, name: 'Charger'),
      ]),
    );

    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SavedListDetailScreen(list: saved, db: db),
      ),
    );
    await settle(tester);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(tester);

    expect(find.text('Passport'), findsNothing);
    final entries =
        await real(tester, () => db.getPackingListEntries(saved.id!));
    expect(entries.single.name, 'Charger');
  }, timeout: _timeout);

  testWidgets('the empty items tab offers to bring in a saved list',
      (tester) async {
    await openItemsTab(tester);

    expect(find.text('No items yet'), findsOneWidget);
    await tester.tap(find.text('Use a saved list'));
    await settle(tester);

    // Lands on the saved lists screen, which has nothing in it yet.
    expect(find.text('No saved lists'), findsOneWidget);
  }, timeout: _timeout);
}
