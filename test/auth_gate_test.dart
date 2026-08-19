import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/auth/api_client.dart';
import 'package:packmate/auth/auth_service.dart';
import 'package:packmate/auth/session.dart';
import 'package:packmate/data/database_helper.dart';
import 'package:packmate/screens/auth/auth_gate.dart';
import 'package:packmate/theme/app_theme.dart';

// See trip_flow_test.dart for why DB work runs inside runAsync and why we avoid
// pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

const _timeout = Timeout(Duration(seconds: 30));

String sessionJson() => jsonEncode({
  'accessToken': 'access-1',
  'refreshToken': 'refresh-1',
  'user': {
    'id': 'user-1',
    'email': 'traveller@example.com',
    'displayName': 'Vinay',
  },
});

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late InMemorySessionStore store;

  setUp(() {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    store = InMemorySessionStore();
  });

  tearDown(() async {
    await db.close();
  });

  /// An API that accepts any sign-in and any verification.
  AuthService buildAuth() => AuthService(ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    store: store,
    httpClient: MockClient((request) async {
      if (request.url.path == '/auth/verify-email') {
        return http.Response('{"status":"verified"}', 200);
      }
      return http.Response(sessionJson(), 200);
    }),
  ));

  Future<void> pumpGate(
    WidgetTester tester, {
    Future<void> Function()? onSignedIn,
  }) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AuthGate(auth: buildAuth(), db: db, onSignedIn: onSignedIn),
      ),
    );
    await settle(tester);
  }

  testWidgets('a slow first sync must not hold the app behind a spinner',
      (tester) async {
    // A sync that never finishes stands in for a slow or wedged one. The app is
    // local-first, so there is nothing to wait for: the trips are already on
    // the device.
    final neverFinishes = Completer<void>();
    addTearDown(() => neverFinishes.complete());

    await pumpGate(tester, onSignedIn: () => neverFinishes.future);
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'traveller@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'correct-horse-battery');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);

    expect(find.text('Your trips'), findsOneWidget,
        reason: 'signing in should show the app immediately, not wait on sync');
  }, timeout: _timeout);

  testWidgets('an unexpected failure stops the spinner and says something',
      (tester) async {
    // The real case this comes from: the secure storage plugin was missing from
    // the installed build, so writing the session threw MissingPluginException
    // — a type no handler expected. The button span forever with no message.
    final auth = AuthService(ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      store: store,
      httpClient: MockClient((_) async => throw StateError('unexpected')),
    ));

    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AuthGate(auth: auth, db: db),
      ),
    );
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'traveller@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'correct-horse-battery');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);

    // Still on sign-in, but with an explanation and a usable button.
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the button must not be left spinning');
  }, timeout: _timeout);

  testWidgets('confirming the emailed code lands on the trips, not a spinner',
      (tester) async {
    await pumpGate(tester);

    // Sign in -> create an account -> confirm the code, the way a new user
    // actually gets in. Both of those screens are pushed on top of the gate.
    await tester.tap(find.text('Create an account'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'traveller@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'correct-horse-battery');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);
    expect(find.text('Confirm your email'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmation code'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await settle(tester);

    // The gate swapping its child is not enough: these were pushed routes and
    // would otherwise stay on top, leaving the user staring at the code screen.
    expect(find.text('Confirm your email'), findsNothing);
    expect(find.text('Your trips'), findsOneWidget);
  }, timeout: _timeout);
}
