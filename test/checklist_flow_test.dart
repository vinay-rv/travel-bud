import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/models/stay.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/screens/trip_detail_screen.dart';
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

  // Opens the trip detail and switches to the Items tab.
  //
  // Uses a phone-sized viewport rather than the 800x600 default: the list is
  // tall enough that on a short window the extended FAB sits on top of the
  // last row's controls, which no real device does.
  Future<void> openItemsTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: TripDetailScreen(trip: trip, db: db)),
    );
    await settle(tester);
    await tester.tap(find.text('Items'));
    await settle(tester);
  }

  testWidgets('items tab empty state', (tester) async {
    await openItemsTab(tester);
    expect(find.textContaining('No items yet'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('add an item and see it on the packing list', (tester) async {
    await openItemsTab(tester);

    await tester.tap(find.byType(AppBottomBarAction));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField), 'Passport');
    await tester.tap(find.widgetWithText(FilledButton, 'Add item'));
    await settle(tester);

    expect(find.text('Passport'), findsOneWidget);

    final items = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(items.single.name, 'Passport');
    expect(items.single.packed, isFalse);
  }, timeout: _timeout);

  testWidgets('toggling the checkbox packs the item', (tester) async {
    await real(
      tester,
      () => db.createItem(Item(tripId: trip.id!, name: 'Charger')),
    );
    await openItemsTab(tester);
    expect(find.text('Charger'), findsOneWidget);

    // Tap the row to pack it (the round check and the whole row both toggle).
    // Scrolled into view first: the bottom bar covers the foot of the list.
    await tester.ensureVisible(find.text('Charger'));
    await settle(tester);
    await tester.tap(find.text('Charger'));
    await settle(tester);

    final items = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(items.single.packed, isTrue);
  }, timeout: _timeout);

  testWidgets('the list is one flat set of items, not grouped by stay',
      (tester) async {
    await real(tester, () async {
      await db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Hotel Polo Towers',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 4, 11),
      ));
      await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
      await db.createItem(Item(tripId: trip.id!, name: 'Room key deposit'));
    });

    await openItemsTab(tester);

    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('Room key deposit'), findsOneWidget);
    // The stay is not a section header on this tab.
    expect(find.text('Hotel Polo Towers'), findsNothing);
  }, timeout: _timeout);

  testWidgets('delete an item through its row menu', (tester) async {
    await real(
      tester,
      () => db.createItem(Item(tripId: trip.id!, name: 'Sunglasses')),
    );
    await openItemsTab(tester);
    expect(find.text('Sunglasses'), findsOneWidget);

    // Scrolled clear of the bottom bar: the row is the last in the list.
    await tester.ensureVisible(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(find.text('Sunglasses'), findsNothing);
    final items = await real(tester, () => db.getItemsForTrip(trip.id!));
    expect(items, isEmpty);
  }, timeout: _timeout);

}
