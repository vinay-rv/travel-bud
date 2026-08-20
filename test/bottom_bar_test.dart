import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/auth/api_client.dart';
import 'package:packmate/auth/auth_service.dart';
import 'package:packmate/auth/session.dart';
import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/screens/trip_detail_screen.dart';
import 'package:packmate/screens/trip_list_screen.dart';
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

  late DatabaseHelper db;

  setUp(() async {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);

    // The account screen reads the app-wide service, which only `main` sets
    // up. Install a signed-in one so opening it from the bar behaves as it
    // does in the app.
    final store = InMemorySessionStore();
    await store.write(const Session(
      userId: 'user-1',
      email: 'traveller@example.com',
      displayName: 'Vinay',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    ));
    final auth = AuthService(ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      store: store,
      httpClient:
          MockClient((_) async => http.Response('{"status":"signed_out"}', 200)),
    ));
    await auth.restore();
    Auth.install(auth);
  });
  tearDown(() async => db.close());

  Future<Trip> seedTrip(WidgetTester tester) => real(
        tester,
        () => db.createTrip(Trip(
          name: 'Northeast India',
          startDate: DateTime(2026, 3, 1),
          endDate: DateTime(2026, 3, 8),
        )),
      );

  Future<void> openHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: TripListScreen(db: db, onSignedOut: () {}),
    ));
    await settle(tester);
  }

  testWidgets('the trip list carries the three slots', (tester) async {
    await openHome(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.widgetWithText(AppBottomBarAction, 'Plan a trip'),
        findsOneWidget);
  }, timeout: _timeout);

  testWidgets('the account has left the header for the bar', (tester) async {
    await openHome(tester);

    // One way in, in the bar — not also an icon in the top row.
    expect(find.byTooltip('Account'), findsNothing);
    expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    // Saved lists stays in the header: it is about this screen's contents.
    expect(find.byTooltip('Saved lists'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('the account slot opens the account screen', (tester) async {
    await openHome(tester);

    await tester.tap(find.text('Account'));
    await settle(tester);

    expect(find.text('Sign out'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('the middle slot follows the tab you are on', (tester) async {
    final trip = await seedTrip(tester);
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: TripDetailScreen(trip: trip, db: db),
    ));
    await settle(tester);

    expect(find.widgetWithText(AppBottomBarAction, 'Add Stay'), findsOneWidget);

    for (final (tab, label) in [
      ('Transport', 'Add Transport'),
      ('Items', 'Add Item'),
      ('Expenses', 'Add Expense'),
    ]) {
      // The tab row scrolls when the labels do not all fit across a 360dp
      // phone, so the later ones have to be brought into view first.
      await tester.ensureVisible(find.text(tab));
      await settle(tester);
      await tester.tap(find.text(tab));
      await settle(tester);
      expect(find.widgetWithText(AppBottomBarAction, label), findsOneWidget,
          reason: tab);
    }
  }, timeout: _timeout);

  testWidgets('home takes you back out of a trip', (tester) async {
    final trip = await seedTrip(tester);
    await openHome(tester);

    await tester.tap(find.text(trip.name));
    await settle(tester);
    expect(find.text('Add Stay'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await settle(tester);

    // Back on the list, where the middle slot means "plan a trip" again.
    expect(find.widgetWithText(AppBottomBarAction, 'Plan a trip'),
        findsOneWidget);
  }, timeout: _timeout);

  testWidgets('the trip list marks home as where you already are',
      (tester) async {
    await openHome(tester);

    final home = tester.widget<AppBottomBar>(find.byType(AppBottomBar));
    expect(home.onHome, isNull);
  }, timeout: _timeout);
}
