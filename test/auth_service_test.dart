import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:packmate/auth/api_client.dart';
import 'package:packmate/auth/auth_service.dart';
import 'package:packmate/auth/session.dart';

/// Records what the client sent, and replies with whatever the test wants.
class FakeApi {
  final List<http.Request> requests = [];
  final Map<String, List<http.Response>> _queued = {};

  /// Queue a reply for a path. Multiple replies are returned in order, which is
  /// how the refresh-and-retry path gets a 401 then a 200.
  void reply(String path, Object body, {int status = 200}) {
    _queued.putIfAbsent(path, () => []).add(
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'}),
    );
  }

  http.Client get client => MockClient((request) async {
    requests.add(
      http.Request(request.method, request.url)..body = request.body,
    );
    final queue = _queued[request.url.path];
    if (queue == null || queue.isEmpty) {
      return http.Response(
        jsonEncode({'error': 'not_stubbed', 'message': request.url.path}),
        500,
      );
    }
    return queue.removeAt(0);
  });

  int countOf(String path) =>
      requests.where((r) => r.url.path == path).length;

  http.Request? lastTo(String path) {
    final matching = requests.where((r) => r.url.path == path);
    return matching.isEmpty ? null : matching.last;
  }
}

Map<String, Object?> sessionBody({
  String access = 'access-1',
  String refresh = 'refresh-1',
  String email = 'traveller@example.com',
}) => {
  'accessToken': access,
  'refreshToken': refresh,
  'expiresIn': 900,
  'user': {'id': 'user-1', 'email': email, 'displayName': 'Vinay'},
};

void main() {
  late FakeApi api;
  late InMemorySessionStore store;
  late ApiClient client;
  late AuthService auth;

  setUp(() {
    api = FakeApi();
    store = InMemorySessionStore();
    client = ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      store: store,
      httpClient: api.client,
    );
    auth = AuthService(client);
  });

  group('Signing up', () {
    test('does not sign you in — the email has to be confirmed first',
        () async {
      api.reply('/auth/signup', {
        'status': 'verification_required',
        'email': 'traveller@example.com',
      }, status: 201);

      final outcome = await auth.signUp(
        email: 'traveller@example.com',
        password: 'correct-horse-battery',
      );

      expect(outcome, SignUpOutcome.verificationRequired);
      expect(auth.isSignedIn, isFalse);
      expect(await store.read(), isNull);
    });

    test('surfaces a taken email as a typed failure', () async {
      api.reply('/auth/signup', {
        'error': 'email_taken',
        'message': 'That email is already registered',
      }, status: 409);

      await expectLater(
        auth.signUp(email: 'taken@example.com', password: 'correct-horse-battery'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'email_taken')),
      );
    });
  });

  group('Signing in', () {
    test('stores the session so the next launch skips sign-in', () async {
      api.reply('/auth/signin', sessionBody());

      final session = await auth.signIn(
        email: 'traveller@example.com',
        password: 'correct-horse-battery',
      );

      expect(session.email, 'traveller@example.com');
      expect(auth.isSignedIn, isTrue);
      expect((await store.read())?.refreshToken, 'refresh-1');
    });

    test('an unverified account is reported distinctly so the app can offer '
        'the confirmation screen', () async {
      api.reply('/auth/signin', {
        'error': 'email_not_verified',
        'message': 'Confirm your email address to finish signing in',
      }, status: 403);

      await expectLater(
        auth.signIn(email: 'new@example.com', password: 'correct-horse-battery'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'email_not_verified')),
      );
    });

    test('being offline is distinguishable from being rejected', () async {
      final offline = ApiClient(
        baseUrl: Uri.parse('https://api.test'),
        store: store,
        // What a real device throws with no route to the host.
        httpClient: MockClient(
          (_) async => throw const SocketException('No route to host'),
        ),
      );

      await expectLater(
        AuthService(offline)
            .signIn(email: 'a@example.com', password: 'correct-horse-battery'),
        throwsA(isA<ApiUnavailable>()),
      );
    });
  });

  group('Keeping the session alive', () {
    test('refreshes once and retries when the access token has expired',
        () async {
      api.reply('/auth/signin', sessionBody());
      await auth.signIn(
        email: 'traveller@example.com',
        password: 'correct-horse-battery',
      );

      // Short-lived access tokens mean this is routine, not exceptional.
      api.reply('/sync/pull', {'error': 'unauthorized', 'message': 'nope'},
          status: 401);
      api.reply('/auth/refresh',
          sessionBody(access: 'access-2', refresh: 'refresh-2'));
      api.reply('/sync/pull', {'rows': []});

      final result = await client.get('/sync/pull', query: {'table': 'trips'});

      expect(result['rows'], isEmpty);
      expect(api.countOf('/auth/refresh'), 1);
      expect(api.countOf('/sync/pull'), 2);
      // The rotated token is what gets persisted.
      expect((await store.read())?.refreshToken, 'refresh-2');
    });

    test('gives up rather than looping when the refresh is also rejected',
        () async {
      api.reply('/auth/signin', sessionBody());
      await auth.signIn(
        email: 'traveller@example.com',
        password: 'correct-horse-battery',
      );

      api.reply('/sync/pull', {'error': 'unauthorized', 'message': 'nope'},
          status: 401);
      api.reply('/auth/refresh', {
        'error': 'refresh_token_reused',
        'message': 'Session expired. Please sign in again.',
      }, status: 401);
      api.reply('/sync/pull', {'error': 'unauthorized', 'message': 'nope'},
          status: 401);

      await expectLater(
        client.get('/sync/pull', query: {'table': 'trips'}),
        throwsA(isA<ApiException>()),
      );

      // One refresh attempt, and the dead session is cleared so the gate sends
      // the user back to sign-in instead of retrying forever.
      expect(api.countOf('/auth/refresh'), 1);
      expect(auth.isSignedIn, isFalse);
      expect(await store.read(), isNull);
    });

    test('keeps the session when a refresh merely fails to connect', () async {
      api.reply('/auth/signin', sessionBody());
      await auth.signIn(
        email: 'traveller@example.com',
        password: 'correct-horse-battery',
      );

      // Offline is not the same as rejected: signing someone out because they
      // walked into a tunnel would be its own bug.
      expect(auth.isSignedIn, isTrue);
      expect((await store.read())?.accessToken, 'access-1');
    });
  });

  group('Signing out', () {
    test('clears the stored session', () async {
      api.reply('/auth/signin', sessionBody());
      await auth.signIn(
        email: 'traveller@example.com',
        password: 'correct-horse-battery',
      );
      api.reply('/auth/signout', {'status': 'signed_out'});

      await auth.signOut();

      expect(auth.isSignedIn, isFalse);
      expect(await store.read(), isNull);
    });

    test('still signs out locally when the server cannot be reached',
        () async {
      api.reply('/auth/signin', sessionBody());
      await auth.signIn(
        email: 'traveller@example.com',
        password: 'correct-horse-battery',
      );
      // No stub for /auth/signout, so the call fails — signing out must not
      // depend on a working connection.

      await auth.signOut();

      expect(auth.isSignedIn, isFalse);
      expect(await store.read(), isNull);
    });
  });

  group('Restoring on launch', () {
    test('reads the stored session without touching the network', () async {
      await store.write(const Session(
        userId: 'user-1',
        email: 'traveller@example.com',
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
      ));

      final restored = await auth.restore();

      expect(restored?.email, 'traveller@example.com');
      expect(auth.isSignedIn, isTrue);
      expect(api.requests, isEmpty);
    });

    test('reports no session on a fresh install', () async {
      expect(await auth.restore(), isNull);
      expect(auth.isSignedIn, isFalse);
    });
  });
}
