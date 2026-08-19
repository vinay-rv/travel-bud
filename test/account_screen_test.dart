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
import 'package:packmate/screens/account_screen.dart';
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
  late AuthService auth;
  late InMemorySessionStore store;

  setUp(() async {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    store = InMemorySessionStore();
    await store.write(const Session(
      userId: 'user-1',
      email: 'traveller@example.com',
      displayName: 'Vinay',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    ));
    auth = AuthService(ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      store: store,
      httpClient: MockClient(
        (_) async => http.Response('{"status":"signed_out"}', 200),
      ),
    ));
    await auth.restore();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> open(WidgetTester tester, {VoidCallback? onSignedOut}) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AccountScreen(auth: auth, db: db, onSignedOut: onSignedOut),
      ),
    );
    await settle(tester);
  }

  testWidgets('shows who is signed in', (tester) async {
    await open(tester);

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Vinay'), findsOneWidget);
    expect(find.text('traveller@example.com'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('shows nothing about syncing', (tester) async {
    await open(tester);

    // The server owns the data and the app writes straight to it, so there is
    // no sync state to report and nothing to switch on or off.
    expect(find.text('Sync now'), findsNothing);
    expect(find.textContaining('Last synced'), findsNothing);
    expect(find.text('Back up my trips'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('signing out clears the session and hands back to the gate',
      (tester) async {
    var signedOutCalled = false;
    await open(tester, onSignedOut: () => signedOutCalled = true);

    await tester.tap(find.text('Sign out'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await settle(tester);

    expect(signedOutCalled, isTrue);
    expect(auth.isSignedIn, isFalse);
    expect(await real(tester, () => store.read()), isNull);
  }, timeout: _timeout);

  testWidgets('signing out empties the cached trips', (tester) async {
    await real(
      tester,
      () => db.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      )),
    );
    await open(tester);

    await tester.tap(find.text('Sign out'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await settle(tester);

    // The cache holds one account's trips. Leaving them for whoever signs in
    // next would be confusing, and a small privacy leak.
    expect(await real(tester, () => db.getTrips()), isEmpty);
  }, timeout: _timeout);
}
