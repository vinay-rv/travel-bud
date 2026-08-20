import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/screens/trip_detail_screen.dart';
import 'package:packmate/theme/app_theme.dart';
import 'package:packmate/widgets/app_bottom_bar.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('four tabs, Documents gone, Items still index 2', (tester) async {
    final db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    addTearDown(db.close);
    late Trip trip;
    await tester.runAsync(() async {
      trip = await db.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      ));
    });

    // A narrow phone. Note the row still scrolls at this width — four labels
    // do not fit across 360dp either, so dropping Documents shortened the row
    // without making it fit.
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: TripDetailScreen(trip: trip, db: db, initialTab: 2),
    ));
    await settle(tester);

    for (final label in ['Stays', 'Transport', 'Items', 'Expenses']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Documents'), findsNothing);
    expect(find.text('Document vault'), findsNothing);

    // Items is still index 2, which is where a checkout reminder deep-links.
    expect(find.widgetWithText(AppBottomBarAction, 'Add Item'),
        findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
