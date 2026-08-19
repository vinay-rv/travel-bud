/// Where the Packmate API lives.
///
/// Supplied with `--dart-define`:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
/// ```
///
/// Note the host: an Android emulator reaches the machine it runs on at
/// `10.0.2.2`, never `localhost` — that would be the emulator itself. An iOS
/// simulator shares the host's network, so `localhost` works there, and a real
/// phone needs the machine's LAN address.
library;

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// Whether this build has somewhere to talk to. Always true in practice — the
/// app requires an account — but keeps the default explicit and overridable.
bool get apiConfigured => apiBaseUrl.isNotEmpty;
