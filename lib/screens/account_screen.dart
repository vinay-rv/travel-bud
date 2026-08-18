import 'package:flutter/material.dart';

import '../sync/sync_config.dart';
import '../sync/sync_engine.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/ui.dart';

/// Backup and account settings — the entire visible surface of sync.
///
/// The copy here is deliberately careful. An anonymous account is a convenience,
/// not a safety net: it cannot be recovered after a reinstall or on a new phone
/// until an email is attached. Telling someone their trips are "backed up" when
/// that is the only thing standing between them and losing everything would be
/// the kind of reassurance that costs people their data.
class AccountScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the app-wide engine.
  final SyncEngine? engine;

  const AccountScreen({super.key, this.engine});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  SyncEngine get _engine => widget.engine ?? Sync.instance;

  bool _busy = false;
  String? _accountId;
  DateTime? _lastSyncedAt;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final accountId = await _engine.claimedUserId();
    final lastSyncedAt = await _engine.lastSyncedAt();
    if (!mounted) return;
    setState(() {
      _accountId = accountId;
      _lastSyncedAt = lastSyncedAt;
    });
  }

  /// Runs [action], keeping the screen busy, then reports what happened.
  Future<void> _run(Future<SyncOutcome> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await action();
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;

    setState(() {
      _busy = false;
      _message = switch (outcome) {
        SyncOutcome.ok => null,
        SyncOutcome.noAccount => null,
        SyncOutcome.busy => null,
        SyncOutcome.unavailable =>
          'No connection. Your trips are safe on this phone — this will '
              'finish on its own once you are back online.',
        SyncOutcome.accountMismatch => null,
      };
    });

    if (outcome == SyncOutcome.accountMismatch) await _askAboutMismatch();
  }

  /// The device's data belongs to one account and a different one is signed in.
  /// Merging automatically would either duplicate everything or quietly throw
  /// something away, so this asks instead.
  Future<void> _askAboutMismatch() async {
    final resolution = await showDialog<MismatchResolution>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Two sets of trips'),
        content: const Text(
          'This phone has trips that belong to a different account than the '
          'one signed in. Which would you like to keep?',
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
    await _run(_engine.sync);
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Stop backing up?',
      message:
          'Your trips stay on this phone. They will no longer be copied to '
          'your account, and this phone will not receive changes made '
          'elsewhere.',
      confirmLabel: 'Stop backup',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    await _engine.disableBackup();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final backingUp = _accountId != null;

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
              if (!syncConfigured)
                const _NotConfiguredCard()
              else ...[
                _StatusCard(
                  backingUp: backingUp,
                  lastSyncedAt: _lastSyncedAt,
                  busy: _busy,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_message != null) ...[
                  _MessageCard(message: _message!),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (!backingUp)
                  AppPrimaryButton(
                    label: 'Back up my trips',
                    icon: Icons.cloud_upload_outlined,
                    loading: _busy,
                    onPressed: _busy ? null : () => _run(_engine.enableBackup),
                  )
                else ...[
                  AppSecondaryButton(
                    label: 'Sync now',
                    icon: Icons.sync_rounded,
                    onPressed: _busy ? () {} : () => _run(_engine.sync),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppSecondaryButton(
                    label: 'Stop backing up',
                    icon: Icons.cloud_off_outlined,
                    accent: AppColors.rose,
                    onPressed: _busy ? () {} : _confirmSignOut,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                const _HonestyNote(),
              ],
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
              Text('Backup', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                'Keep your trips if you lose this phone',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        const AppIconTile(
          icon: Icons.cloud_outlined,
          color: AppColors.primary,
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool backingUp;
  final DateTime? lastSyncedAt;
  final bool busy;

  const _StatusCard({
    required this.backingUp,
    required this.lastSyncedAt,
    required this.busy,
  });

  String get _detail {
    if (busy) return 'Working…';
    if (!backingUp) {
      return 'Your trips are on this phone only. Uninstalling the app or '
          'losing the phone would lose them.';
    }
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
    final color = backingUp ? AppColors.mint : AppColors.amber;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: backingUp ? Icons.cloud_done_outlined : Icons.phone_iphone,
            color: color,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backingUp ? 'Backing up' : 'On this phone only',
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
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.amber,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The caveat that stops "Backing up" from being read as a guarantee.
class _HonestyNote extends StatelessWidget {
  const _HonestyNote();

  @override
  Widget build(BuildContext context) {
    return const FormHint(
      'Backup currently uses an account with no email attached, so it can '
      'restore your trips onto this phone but not onto a new one. Adding an '
      'email — coming soon — is what makes them recoverable anywhere.',
    );
  }
}

class _NotConfiguredCard extends StatelessWidget {
  const _NotConfiguredCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: Icons.cloud_off_outlined,
                color: AppColors.textMuted,
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Backup is not available in this build',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            'Everything works exactly as before — your trips live on this '
            'phone and never leave it.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
