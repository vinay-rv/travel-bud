import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/session.dart';
import '../sync/sync_engine.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/ui.dart';
import 'auth/auth_gate.dart';

/// Who you are signed in as, and how the syncing is going.
///
/// Sync itself has no controls: it is not a feature the user turns on, it is
/// how an account works. All that is left to show is whether it is up to date,
/// a way to force it, and the way out.
class AccountScreen extends StatefulWidget {
  /// Injectable for tests; default to the app-wide instances.
  final AuthService? auth;
  final SyncEngine? engine;

  /// Sends the app back to sign-in once the session ends.
  final VoidCallback? onSignedOut;

  const AccountScreen({super.key, this.auth, this.engine, this.onSignedOut});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  AuthService get _auth => widget.auth ?? Auth.instance;
  SyncEngine get _engine => widget.engine ?? Sync.instance;

  bool _busy = false;
  DateTime? _lastSyncedAt;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final lastSyncedAt = await _engine.lastSyncedAt();
    if (!mounted) return;
    setState(() => _lastSyncedAt = lastSyncedAt);
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await _engine.sync();
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _message = switch (outcome) {
        SyncOutcome.unavailable =>
          'No connection. Your trips are safe on this phone and will sync '
              'once you are back online.',
        SyncOutcome.noAccount => 'Signed out. Sign in again to sync.',
        _ => null,
      };
    });

    if (outcome == SyncOutcome.accountMismatch) await _askAboutMismatch();
  }

  /// This phone's trips belong to one account and a different one has signed
  /// in. Merging automatically would either duplicate everything or throw
  /// something away, so it asks.
  Future<void> _askAboutMismatch() async {
    final resolution = await showDialog<MismatchResolution>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Two sets of trips'),
        content: const Text(
          'This phone has trips from a different account. Which would you '
          'like to keep?',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(MismatchResolution.useTheAccount),
            child: const Text('Use the account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: () =>
                Navigator.of(context).pop(MismatchResolution.keepThisDevice),
            child: const Text('Keep this phone'),
          ),
        ],
      ),
    );
    if (resolution == null) return;

    await _engine.resolveAccountMismatch(resolution);
    await _syncNow();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Sign out?',
      message:
          'You will need to sign in again to use Packmate. Anything not yet '
          'synced will upload the next time you sign in on this phone.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    await signOutAndReturn(
      auth: _auth,
      sync: _engine,
      onSignedOut: () {
        widget.onSignedOut?.call();
        // Back to the root, where the gate now shows sign-in.
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _auth.session;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.xxl,
            ),
            children: [
              const _Header(),
              const SizedBox(height: AppSpacing.lg),
              if (session != null) _IdentityCard(session: session),
              const SizedBox(height: AppSpacing.md),
              _SyncCard(lastSyncedAt: _lastSyncedAt, busy: _busy),
              const SizedBox(height: AppSpacing.md),
              if (_message != null) ...[
                _MessageCard(message: _message!),
                const SizedBox(height: AppSpacing.md),
              ],
              AppSecondaryButton(
                label: 'Sync now',
                icon: Icons.sync_rounded,
                onPressed: _busy ? () {} : _syncNow,
              ),
              const SizedBox(height: AppSpacing.md),
              AppSecondaryButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                accent: AppColors.rose,
                onPressed: _busy ? () {} : _confirmSignOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.textMuted,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Account', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text('Your trips, on every device', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        const AppIconTile(
          icon: Icons.person_rounded,
          color: AppColors.primary,
        ),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final Session session;

  const _IdentityCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final name = session.displayName;

    return AppCard(
      child: Row(
        children: [
          const AppIconTile(
            icon: Icons.account_circle_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null || name.isEmpty ? 'Signed in' : name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  session.email,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends StatelessWidget {
  final DateTime? lastSyncedAt;
  final bool busy;

  const _SyncCard({required this.lastSyncedAt, required this.busy});

  String get _detail {
    if (busy) return 'Syncing…';
    final at = lastSyncedAt;
    if (at == null) return 'Waiting for the first sync.';
    return 'Last synced ${_relative(at)}.';
  }

  static String _relative(DateTime at) {
    final elapsed = DateTime.now().difference(at);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) {
      return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
    }
    return 'on ${formatDate(at)}';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: busy ? Icons.sync_rounded : Icons.cloud_done_outlined,
            color: AppColors.mint,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Synced to your account',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(_detail, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;

  const _MessageCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderColor: AppColors.amber.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.amber),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
