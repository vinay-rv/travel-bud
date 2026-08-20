import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/models/stay.dart';
import 'package:packmate/models/transport_leg.dart';
import 'package:packmate/screens/trip_detail_screen.dart';
import 'package:packmate/widgets/app_bottom_bar.dart';

// See trip_flow_test.dart for why the DB work runs inside runAsync and why we
// avoid pumpAndSettle.
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

  Widget wrap() => MaterialApp(home: TripDetailScreen(trip: trip, db: db));

  testWidgets('stays tab: empty state, then add a stay via the form',
      (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    // Starts on the Stays tab.
    expect(find.text('No stays yet'), findsOneWidget);

    // Add a stay: the edit screen has a hotel field with default times.
    await tester.tap(find.widgetWithText(AppBottomBarAction, 'Add Stay'));
    await settle(tester);
    await tester.enterText(
        find.byType(TextFormField), 'Hotel Polo Towers');
    await tester.tap(find.widgetWithText(FilledButton, 'Add stay'));
    await settle(tester);

    // Back on the Stays tab, the new stay shows and is persisted.
    expect(find.text('Hotel Polo Towers'), findsOneWidget);
    final stays = await real(tester, () => db.getStaysForTrip(trip.id!));
    expect(stays.single.hotelName, 'Hotel Polo Towers');
  }, timeout: _timeout);

  testWidgets('stays tab: delete a seeded stay', (tester) async {
    await real(
      tester,
      () => db.createStay(Stay(
        tripId: trip.id!,
        hotelName: 'Old Hotel',
        checkInAt: DateTime(2026, 3, 1, 14),
        checkOutAt: DateTime(2026, 3, 3, 11),
      )),
    );

    await tester.pumpWidget(wrap());
    await settle(tester);
    expect(find.text('Old Hotel'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    expect(find.text('Old Hotel'), findsNothing);
    final stays = await real(tester, () => db.getStaysForTrip(trip.id!));
    expect(stays, isEmpty);
  }, timeout: _timeout);

  testWidgets('transport tab: add a train leg via the form', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    // Switch to the Transport tab.
    await tester.tap(find.text('Transport'));
    await settle(tester);
    expect(find.textContaining('No transport yet'), findsOneWidget);

    await tester
        .tap(find.widgetWithText(AppBottomBarAction, 'Add Transport'));
    await settle(tester);

    // Choose Train from the segmented type selector.
    await tester.tap(find.text('Train'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'From'), 'Guwahati');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'To'), 'Shillong');
    await tester.tap(find.widgetWithText(FilledButton, 'Add transport'));
    await settle(tester);

    // Back on the Transport tab, the leg shows and is persisted as a train.
    expect(find.text('Guwahati → Shillong'), findsOneWidget);
    final legs =
        await real(tester, () => db.getTransportLegsForTrip(trip.id!));
    expect(legs.single.type, TransportType.train);
    expect(legs.single.fromLocation, 'Guwahati');
    expect(legs.single.toLocation, 'Shillong');
  }, timeout: _timeout);
}
