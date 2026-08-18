import 'api_client.dart';
import 'session.dart';

/// What signing up produced. Sign-up deliberately does not sign you in: the
/// address has to be confirmed first, which is the whole point of verifying it.
enum SignUpOutcome { verificationRequired }

/// Account operations, in the app's own vocabulary.
///
/// A thin layer over [ApiClient] whose value is that screens never touch HTTP
/// or token plumbing — and that it can be swapped for a fake in tests.
class AuthService {
  final ApiClient api;

  AuthService(this.api);

  Session? get session => api.session;
  bool get isSignedIn => api.isSignedIn;

  Future<Session?> restore() => api.restore();

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await api.post('/auth/signup', authenticated: false, body: {
      'email': email,
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
    });
    return SignUpOutcome.verificationRequired;
  }

  Future<void> verifyEmail({required String email, required String code}) =>
      api.post('/auth/verify-email',
          authenticated: false, body: {'email': email, 'code': code});

  Future<void> resendVerification(String email) => api.post(
    '/auth/resend-verification',
    authenticated: false,
    body: {'email': email},
  );

  Future<Session> signIn({
    required String email,
    required String password,
  }) async {
    final body = await api.post('/auth/signin', authenticated: false, body: {
      'email': email,
      'password': password,
    });
    final session = Session.fromApi(body);
    await api.setSession(session);
    return session;
  }

  Future<void> forgotPassword(String email) => api.post(
    '/auth/forgot-password',
    authenticated: false,
    body: {'email': email},
  );

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) => api.post('/auth/reset-password', authenticated: false, body: {
    'email': email,
    'code': code,
    'password': password,
  });

  /// Ends the session. The local database is untouched — the phone keeps its
  /// copy of everything, and a later sign-in re-uploads it.
  Future<void> signOut() async {
    final refreshToken = api.session?.refreshToken;
    if (refreshToken != null) {
      try {
        await api.post('/auth/signout',
            authenticated: false, body: {'refreshToken': refreshToken});
      } on ApiUnavailable {
        // Signing out must work on a plane. The server-side token expires on
        // its own; what matters is that this device forgets it.
      } on ApiException {
        // Already invalid server-side, which is the state we wanted anyway.
      }
    }
    await api.setSession(null);
  }
}

/// App-wide auth, held the same way `Reminders` and `Sync` are.
///
/// `main` replaces this during startup. The default points at nothing usable,
/// so anything reaching for it before startup finishes fails obviously rather
/// than silently doing the wrong thing.
class Auth {
  Auth._();

  static late AuthService instance;

  /// True once `main` has wired it up. Tests that never call `main` can check
  /// this instead of tripping over a late field.
  static bool get isReady => _ready;
  static bool _ready = false;

  static void install(AuthService service) {
    instance = service;
    _ready = true;
  }
}
