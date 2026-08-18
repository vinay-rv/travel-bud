import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/screens/account_screen.dart';
import 'package:packmate/sync/sync_config.dart';
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
  late FakeRemote remote;
  late SyncEngine engine;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    remote = FakeRemote(userId: null);
    engine = SyncEngine(db: db, remote: remote);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AccountScreen(engine: engine),
      ),
    );
    await settle(tester);
  }

  // What this screen shows depends on a compile-time flag, so each test says
  // which kind of build it is about. Without that the suite would pass under a
  // plain `flutter test` and fail under one with the sync defines set.
  // (`skip` takes a plain bool here, so the reason lives in the names.)
  final skipUnlessConfigured = !syncConfigured;
  final skipUnlessUnconfigured = syncConfigured;

  testWidgets('a build without a server says so plainly', (tester) async {
    await open(tester);

    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Backup is not available in this build'), findsOneWidget);
    // And is clear that nothing is broken as a result.
    expect(find.textContaining('never leave it'), findsOneWidget);
  }, timeout: _timeout, skip: skipUnlessUnconfigured);

  testWidgets('the opt-in is not offered when there is nowhere to send data',
      (tester) async {
    await real(
      tester,
      () => db.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      )),
    );
    await open(tester);

    expect(find.text('Back up my trips'), findsNothing);
  }, timeout: _timeout, skip: skipUnlessUnconfigured);

  testWidgets('a configured build offers the opt-in and is honest until taken',
      (tester) async {
    await open(tester);

    expect(find.text('On this phone only'), findsOneWidget);
    expect(find.textContaining('would lose them'), findsOneWidget);
    expect(find.text('Back up my trips'), findsOneWidget);
    // Nothing claims the data is backed up before the user has asked.
    expect(find.text('Backing up'), findsNothing);
  }, timeout: _timeout, skip: skipUnlessConfigured);

  testWidgets('tapping the opt-in starts backing up', (tester) async {
    await open(tester);
    await tester.tap(find.text('Back up my trips'));
    // Signing in and a full push/pull is a lot of real async work.
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }

    expect(find.text('Backing up'), findsOneWidget);
    expect(find.text('Stop backing up'), findsOneWidget);
    // Through `real`, not directly: a DB call made in the fake-async zone
    // never completes (see the note in trip_flow_test.dart).
    expect(await real(tester, () => engine.isBackingUp), isTrue);
  }, timeout: _timeout, skip: skipUnlessConfigured);

  group('Engine state the screen reads', () {
    // The screen is a thin shell over these; they are what actually decides
    // what it renders, and they work regardless of the build flag.
    test('starts out not backing up', () async {
      expect(await engine.isBackingUp, isFalse);
      expect(await engine.claimedUserId(), isNull);
      expect(await engine.lastSyncedAt(), isNull);
    });

    test('after opting in, reports an account and a sync time', () async {
      await db.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      ));

      expect(await engine.enableBackup(), SyncOutcome.ok);

      expect(await engine.isBackingUp, isTrue);
      expect(await engine.claimedUserId(), isNotNull);
      expect(await engine.lastSyncedAt(), isNotNull);
    });

    test('after stopping, reports not backing up but keeps the trips',
        () async {
      await db.createTrip(Trip(
        name: 'Northeast India',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 8),
      ));
      await engine.enableBackup();

      await engine.disableBackup();

      expect(await engine.isBackingUp, isFalse);
      expect(await engine.lastSyncedAt(), isNull);
      expect((await db.getTrips()).single.name, 'Northeast India');
    });
  });
}
