import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Who is signed in, and the tokens proving it.
class Session {
  final String userId;
  final String email;
  final String? displayName;
  final String accessToken;
  final String refreshToken;

  const Session({
    required this.userId,
    required this.email,
    this.displayName,
    required this.accessToken,
    required this.refreshToken,
  });

  Session copyWith({String? accessToken, String? refreshToken}) => Session(
    userId: userId,
    email: email,
    displayName: displayName,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
  );

  Map<String, Object?> toJson() => {
    'userId': userId,
    'email': email,
    'displayName': displayName,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };

  factory Session.fromJson(Map<String, Object?> json) => Session(
    userId: json['userId'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String?,
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
  );

  /// Built from the API's session response, which nests the user.
  factory Session.fromApi(Map<String, Object?> body) {
    final user = body['user'] as Map<String, Object?>;
    return Session(
      userId: user['id'] as String,
      email: user['email'] as String,
      displayName: user['displayName'] as String?,
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
    );
  }
}

/// Where the session lives between launches.
///
/// The refresh token is a long-lived credential — anyone holding it can mint
/// sessions until it expires — so it goes in the platform keystore rather than
/// shared preferences, which is a plain file on a rooted device.
///
/// Kept behind an interface so tests can run without the platform channel.
abstract class SessionStore {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'packmate.session';

  final FlutterSecureStorage _storage;

  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<Session?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // Unreadable stored session: treat as signed out rather than wedging the
      // app on every launch.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// In-memory store for tests and for any build without secure storage.
class InMemorySessionStore implements SessionStore {
  Session? _session;

  @override
  Future<Session?> read() async => _session;

  @override
  Future<void> write(Session session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
