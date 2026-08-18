/// Build-time configuration for backup and sync.
///
/// Supplied with `--dart-define`, e.g.
///
/// ```sh
/// flutter run \
///   --dart-define=SYNC_ENABLED=true \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
///
/// The key Supabase now calls the *publishable* key (previously the anon key)
/// is publishable by design — it identifies the project, and row level security
/// is what actually protects the data, so a key baked into the app is not a
/// secret being leaked. The **service role** key is a different matter entirely
/// and must never appear anywhere in this project; it belongs only in Edge
/// Functions.
library;

/// Master switch. Off by default, so a build without the define behaves exactly
/// as the app did before sync existed: no network, no account, nothing to go
/// wrong.
const syncEnabled = bool.fromEnvironment('SYNC_ENABLED');

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Whether there is actually somewhere to sync to. A build with the flag on but
/// no project details is treated as off rather than crashing on startup.
bool get syncConfigured =>
    syncEnabled && supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
