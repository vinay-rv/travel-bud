import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/expense.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/screens/trip_detail_screen.dart';
import 'package:packmate/theme/app_theme.dart';
import 'package:packmate/widgets/app_bottom_bar.dart';

import 'write_through_test.dart' show FakeRemoteStore;

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
  for (var i = 0; i < 8; i++) {
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

  group('Money', () {
    // Money is stored as whole minor units. These are the conversions that
    // decide whether a total ever disagrees with the rows above it.
    test('parses what people actually type', () {
      expect(parseMinor('12'), 1200);
      expect(parseMinor('12.5'), 1250);
      expect(parseMinor('12.50'), 1250);
      expect(parseMinor('0.05'), 5);
      expect(parseMinor('1,234.56'), 123456);
      expect(parseMinor('  7.25  '), 725);
    });

    test('refuses what it cannot represent exactly', () {
      // Rounding a third decimal away would quietly change the amount.
      expect(parseMinor('12.555'), isNull);
      expect(parseMinor('12.5.5'), isNull);
      expect(parseMinor('twelve'), isNull);
      expect(parseMinor('-5'), isNull);
      expect(parseMinor(''), isNull);
    });

    test('formats back to something readable', () {
      expect(formatMinor(1250), '12.50');
      expect(formatMinor(5), '0.05');
      expect(formatMinor(0), '0.00');
      expect(formatMinor(123456), '1,234.56');
      expect(formatMinor(100000000), '1,000,000.00');
    });

    test('survives a round trip, which floats would not', () {
      // 0.1 + 0.2 in binary floating point is famously not 0.3.
      final total = parseMinor('0.10')! + parseMinor('0.20')!;
      expect(formatMinor(total), '0.30');
    });
  });

  group('Storing expenses', () {
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

    test('round-trips with its amount and timestamp intact', () async {
      final spentAt = DateTime(2026, 3, 2, 19, 45);
      await db.createExpense(Expense(
        tripId: trip.id!,
        name: 'Airport taxi',
        amountMinor: 125050,
        spentAt: spentAt,
      ));

      final expense = (await db.getExpensesForTrip(trip.id!)).single;
      expect(expense.name, 'Airport taxi');
      expect(expense.amountMinor, 125050);
      expect(expense.amountLabel, '1,250.50');
      expect(expense.spentAt, spentAt);
    });

    test('lists most recent first, whatever order they were entered',
        () async {
      await db.createExpense(Expense(
        tripId: trip.id!,
        name: 'Breakfast',
        amountMinor: 800,
        spentAt: DateTime(2026, 3, 2, 8),
      ));
      // Entered second, but happened first.
      await db.createExpense(Expense(
        tripId: trip.id!,
        name: 'Taxi',
        amountMinor: 2500,
        spentAt: DateTime(2026, 3, 1, 22),
      ));

      final expenses = await db.getExpensesForTrip(trip.id!);
      expect(expenses.map((e) => e.name), ['Breakfast', 'Taxi']);
    });

    test('totals in whole units, never drifting', () async {
      for (final amount in [1010, 2020, 3033]) {
        await db.createExpense(Expense(
          tripId: trip.id!,
          name: 'Thing $amount',
          amountMinor: amount,
          spentAt: DateTime(2026, 3, 2),
        ));
      }

      expect(await db.getExpenseTotalForTrip(trip.id!), 6063);
      expect(formatMinor(await db.getExpenseTotalForTrip(trip.id!)), '60.63');
    });

    test('belongs to its trip and goes when the trip goes', () async {
      final other = await db.createTrip(Trip(
        name: 'Goa',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 3),
      ));
      await db.createExpense(Expense(
        tripId: trip.id!,
        name: 'Taxi',
        amountMinor: 2500,
        spentAt: DateTime(2026, 3, 1),
      ));

      expect(await db.getExpensesForTrip(other.id!), isEmpty);

      await db.deleteTrip(trip.id!);
      expect(await db.getExpensesForTrip(trip.id!), isEmpty);
    });

    test('reaches the server like everything else', () async {
      final remote = FakeRemoteStore();
      db.remote = remote;

      await db.createExpense(Expense(
        tripId: trip.id!,
        name: 'Airport taxi',
        amountMinor: 2500,
        spentAt: DateTime(2026, 3, 1, 22),
      ));

      final sent = remote.lastUpsertTo('expenses')!;
      expect(sent['name'], 'Airport taxi');
      expect(sent['amountMinor'], 2500);
      expect(sent['tripUuid'], isNotNull);
      expect(sent.containsKey('tripId'), isFalse);
    });
  });

  group('The expenses tab', () {
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

    /// Opens straight on the Expenses tab.
    ///
    /// Not by tapping: with five tabs the strip scrolls on a 360dp phone and
    /// Expenses starts off-screen, so a tap would miss. That the strip scrolls
    /// the selection into view is covered separately.
    Future<void> openExpenses(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: TripDetailScreen(trip: trip, db: db, initialTab: 3),
      ));
      await settle(tester);
    }

    testWidgets('scrolls the selected tab into view when it does not fit',
        (tester) async {
      await openExpenses(tester);

      // Opening on a tab past the right-hand edge must not leave it invisible.
      final tab = tester.getRect(find.text('Expenses'));
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(tab.left, greaterThanOrEqualTo(screen.left));
      expect(tab.right, lessThanOrEqualTo(screen.right));
    }, timeout: _timeout);

    testWidgets('starts empty and offers a way in', (tester) async {
      await openExpenses(tester);

      expect(find.text('Nothing spent yet'), findsOneWidget);
      expect(
        find.widgetWithText(AppBottomBarAction, 'Add Expense'),
        findsOneWidget,
      );
    }, timeout: _timeout);

    testWidgets('adding one shows it with its amount, date and time',
        (tester) async {
      await openExpenses(tester);

      await tester.tap(find.widgetWithText(AppBottomBarAction, 'Add Expense'));
      await settle(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'What was it for'), 'Airport taxi');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '1250.50');
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await settle(tester);

      expect(find.text('Airport taxi'), findsOneWidget);
      expect(find.text('1,250.50'), findsWidgets);

      final saved = await real(tester, () => db.getExpensesForTrip(trip.id!));
      expect(saved.single.amountMinor, 125050);
      // Timestamped so the list can answer "when did I pay for that?".
      expect(saved.single.spentAt, isNotNull);
    }, timeout: _timeout);

    testWidgets('an amount it cannot store exactly is refused, not rounded',
        (tester) async {
      await openExpenses(tester);

      await tester.tap(find.widgetWithText(AppBottomBarAction, 'Add Expense'));
      await settle(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'What was it for'), 'Coffee');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'), '3.999');
      await tester.tap(find.widgetWithText(FilledButton, 'Add expense'));
      await settle(tester);

      expect(find.text('Use a number like 12.50'), findsOneWidget);
      expect(await real(tester, () => db.getExpensesForTrip(trip.id!)), isEmpty);
    }, timeout: _timeout);

    testWidgets('the total adds up across expenses', (tester) async {
      await real(tester, () async {
        await db.createExpense(Expense(
          tripId: trip.id!,
          name: 'Taxi',
          amountMinor: 2500,
          spentAt: DateTime(2026, 3, 1, 22),
        ));
        await db.createExpense(Expense(
          tripId: trip.id!,
          name: 'Dinner',
          amountMinor: 1875,
          spentAt: DateTime(2026, 3, 2, 20),
        ));
      });
      await openExpenses(tester);

      expect(find.text('43.75'), findsOneWidget);
      expect(find.text('2 expenses'), findsOneWidget);
    }, timeout: _timeout);
  });
}
