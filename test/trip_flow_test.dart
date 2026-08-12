import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:trip_inventory_tracker/data/database_helper.dart';
import 'package:trip_inventory_tracker/models/trip.dart';
import 'package:trip_inventory_tracker/screens/trip_list_screen.dart';

/// These screens read from a real (in-memory, FFI) database whose futures
/// resolve on the *real* event loop, not flutter_test's fake-async zone.
///
/// Two rules make this work reliably:
///  * Any direct DB call in a test body must run inside [tester.runAsync];
///    calling it in the fake-async zone would hang forever.
///  * We never use [pumpAndSettle] (the loading spinner animates endlessly and
///    would time out). Instead [settle] opens a real-async gap so the widget's
///    own load future can resolve, then pumps a couple of frames.

/// Runs a real-async DB operation from within a test body and returns its
/// result.
Future<T> real<T>(WidgetTester tester, Future<T> Function() op) async {
  late T result;
  await tester.runAsync(() async {
    result = await op();
  });
  return result;
}

/// Lets pending real-async work (DB loads, writes) complete, then renders the
/// resulting frames, including any navigation/dialog transition. Loops a few
/// times so a slower first DB open (native lib load + schema creation) or a
/// reload still lands before assertions run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

// Fail fast instead of hanging if something regresses.
const _timeout = Timeout(Duration(seconds: 30));

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

  Widget wrap() => MaterialApp(home: TripListScreen(db: db));

  testWidgets('empty state shows when there are no trips', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('No trips yet'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('existing trips render on load', (tester) async {
    await real(
      tester,
      () => db.createTrip(Trip(
        name: 'Kerala Backwaters',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 6),
      )),
    );

    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('Kerala Backwaters'), findsOneWidget);
    expect(find.text('1–6 May 2026'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('create a trip via the form and see it in the list',
      (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    // Open the create screen via the FAB.
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    // Enter a name and save.
    await tester.enterText(find.byType(TextFormField), 'Northeast India');
    await tester.tap(find.text('Create trip'));
    await settle(tester);

    // Back on the list, the new trip appears and was persisted.
    expect(find.text('Northeast India'), findsOneWidget);
    final trips = await real(tester, () => db.getTrips());
    expect(trips.single.name, 'Northeast India');
  }, timeout: _timeout);

  testWidgets('name validation blocks an empty trip', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);

    // Save without entering a name.
    await tester.tap(find.text('Create trip'));
    await settle(tester);

    expect(find.text('Please enter a trip name'), findsOneWidget);
    final trips = await real(tester, () => db.getTrips());
    expect(trips, isEmpty);
  }, timeout: _timeout);

  testWidgets('delete a trip through the popup menu', (tester) async {
    await real(
      tester,
      () => db.createTrip(Trip(
        name: 'Goa Weekend',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 3),
      )),
    );

    await tester.pumpWidget(wrap());
    await settle(tester);
    expect(find.text('Goa Weekend'), findsOneWidget);

    // Open the row menu and choose Delete.
    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);

    // Confirm in the dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(find.text('Goa Weekend'), findsNothing);
    expect(find.text('No trips yet'), findsOneWidget);
    final trips = await real(tester, () => db.getTrips());
    expect(trips, isEmpty);
  }, timeout: _timeout);
}
