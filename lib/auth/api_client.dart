import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'session.dart';

/// The API said no, and said why.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;

  const ApiException(this.status, this.code, this.message);

  /// True when the server is telling us the session is finished — the user has
  /// to sign in again, and no amount of retrying will help.
  bool get isAuthFailure =>
      status == 401 &&
      (code == 'invalid_refresh_token' ||
          code == 'refresh_token_reused' ||
          code == 'refresh_token_expired' ||
          code == 'unauthorized');

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// Couldn't reach the server at all. Ordinary on a plane or a foreign SIM, and
/// never something to show as an error.
class ApiUnavailable implements Exception {
  final Object cause;
  const ApiUnavailable(this.cause);

  @override
  String toString() => 'ApiUnavailable($cause)';
}

/// Talks to the Packmate API, holding the session and keeping it fresh.
///
/// Access tokens are deliberately short-lived, so expiry during normal use is
/// expected rather than exceptional: a 401 triggers one refresh and one retry.
/// Concurrent callers share a single refresh — otherwise five parallel sync
/// requests would each rotate the token, and rotation treats a reused token as
/// theft and revokes the lot.
class ApiClient {
  final Uri baseUrl;
  final SessionStore store;
  final http.Client _http;

  Session? _session;
  Future<Session?>? _refreshing;

  ApiClient({
    required this.baseUrl,
    required this.store,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Session? get session => _session;

  bool get isSignedIn => _session != null;

  /// Called by whoever changes the session — sign-in, sign-out, refresh.
  ///
  /// Persistence is best-effort on purpose. A keystore that refuses to write —
  /// a device with a broken one, or a build where the plugin is missing — must
  /// not stop someone signing in. They stay signed in for this run and are
  /// asked again next launch, which is a far better outcome than a sign-in
  /// button that fails with no explanation.
  Future<void> setSession(Session? session) async {
    _session = session;
    try {
      if (session == null) {
        await store.clear();
      } else {
        await store.write(session);
      }
    } catch (error) {
      debugPrint('Could not persist the session: $error');
    }
  }

  /// Restores a session saved on a previous launch. Purely local: no network,
  /// so the app opens instantly and works offline.
  Future<Session?> restore() async {
    try {
      _session = await store.read();
    } catch (error) {
      debugPrint('Could not read the stored session: $error');
      _session = null;
    }
    return _session;
  }

  Future<Map<String, Object?>> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) => _send('GET', path, query: query, authenticated: authenticated);

  Future<Map<String, Object?>> post(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) => _send('POST', path, body: body, authenticated: authenticated);

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    bool authenticated = true,
    bool isRetry = false,
  }) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path}$path',
      queryParameters: query,
    );

    late http.Response response;
    try {
      final request = http.Request(method, uri)
        ..headers['content-type'] = 'application/json';
      if (authenticated && _session != null) {
        request.headers['authorization'] = 'Bearer ${_session!.accessToken}';
      }
      if (body != null) request.body = jsonEncode(body);

      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 20)),
      );
    } on SocketException catch (e) {
      throw ApiUnavailable(e);
    } on http.ClientException catch (e) {
      throw ApiUnavailable(e);
    } on TimeoutException catch (e) {
      throw ApiUnavailable(e);
    }

    // An expired access token during ordinary use: refresh once, retry once.
    // Never retry twice, or a genuinely dead session becomes an infinite loop.
    if (response.statusCode == 401 && authenticated && !isRetry) {
      final refreshed = await _refreshSession();
      if (refreshed != null) {
        return _send(
          method,
          path,
          body: body,
          query: query,
          authenticated: authenticated,
          isRetry: true,
        );
      }
    }

    final decoded = response.body.isEmpty
        ? <String, Object?>{}
        : jsonDecode(response.body) as Map<String, Object?>;

    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        decoded['error'] as String? ?? 'server_error',
        decoded['message'] as String? ?? 'Something went wrong',
      );
    }
    return decoded;
  }

  /// Exchanges the refresh token for a new session, at most once at a time.
  Future<Session?> _refreshSession() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<Session?> _doRefresh() async {
    final current = _session;
    if (current == null) return null;

    try {
      final body = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': current.refreshToken},
        authenticated: false,
      );
      final next = Session.fromApi(body);
      await setSession(next);
      return next;
    } on ApiException catch (e) {
      // The refresh token itself is dead — signed out elsewhere, expired, or
      // flagged as reused. Clear the session so the app returns to sign-in
      // rather than retrying a credential that will never work again.
      if (e.isAuthFailure) await setSession(null);
      return null;
    } on ApiUnavailable {
      // Just offline. Keep the session; it may well still be valid later.
      return null;
    }
  }

  void close() => _http.close();
}
