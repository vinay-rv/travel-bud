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
import 'package:packmate/sync/sync_engine.dart';
import 'package:packmate/theme/app_theme.dart';

import 'sync_engine_test.dart' show FakeRemote;

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
  late FakeRemote remote;
  late SyncEngine engine;
  late AuthService auth;
  late InMemorySessionStore store;

  setUp(() async {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    remote = FakeRemote();
    engine = SyncEngine(db: db, remote: remote);
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
        home: AccountScreen(
          auth: auth,
          engine: engine,
          onSignedOut: onSignedOut,
        ),
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

  testWidgets('offers no way to turn syncing off', (tester) async {
    await open(tester);

    // Sync is how an account works, not a feature to opt into — the old
    // "Back up my trips" opt-in should be gone entirely.
    expect(find.text('Back up my trips'), findsNothing);
    expect(find.text('Stop backing up'), findsNothing);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  }, timeout: _timeout);

  testWidgets('syncing reports when it last succeeded', (tester) async {
    await real(
      tester,
      () => db.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      )),
    );
    await open(tester);

    await tester.tap(find.text('Sync now'));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }

    expect(find.textContaining('Last synced'), findsOneWidget);
    expect(await real(tester, () => engine.lastSyncedAt()), isNotNull);
  }, timeout: _timeout);

  testWidgets('being offline is explained, not treated as an error',
      (tester) async {
    remote.offline = true;
    await open(tester);

    await tester.tap(find.text('Sync now'));
    await settle(tester);

    expect(find.textContaining('safe on this phone'), findsOneWidget);
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

  testWidgets('signing out re-queues the trips for the next account',
      (tester) async {
    final trip = await real(
      tester,
      () => db.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      )),
    );
    await real(tester, () => engine.sync());
    await open(tester);

    await tester.tap(find.text('Sign out'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await settle(tester);

    // The phone keeps everything, and it is queued so the next sign-in
    // uploads it rather than it looking already-synced.
    final rows = await real(
      tester,
      () async => (await db.database).query(
        DatabaseHelper.tableTrip,
        columns: ['dirty'],
        where: 'id = ?',
        whereArgs: [trip.id],
      ),
    );
    expect(rows.single['dirty'], 1);
    expect((await real(tester, () => db.getTrips())).single.name,
        'Northeast India');
  }, timeout: _timeout);
}
