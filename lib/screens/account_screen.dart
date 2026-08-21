import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/session.dart';
import '../data/database_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'auth/auth_gate.dart';

/// Your account.
///
/// There is nothing here about syncing, because there is no longer anything to
/// decide: the server holds the data and the app writes straight to it. What is
/// left is who you are and how to leave.
class AccountScreen extends StatefulWidget {
  /// Injectable for tests; the app-wide instances otherwise.
  final AuthService? auth;
  final DatabaseHelper? db;

  /// Sends the app back to sign-in once the session ends.
  final VoidCallback? onSignedOut;

  const AccountScreen({super.key, this.auth, this.db, this.onSignedOut});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  AuthService get _auth => widget.auth ?? Auth.instance;
  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  bool _busy = false;

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Sign out?',
      message:
          'Your trips stay in your account. You will need to sign in again to '
          'see them on this phone.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    await signOutAndReturn(
      auth: _auth,
      db: _db,
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
              const SizedBox(height: AppSpacing.xl),
              AppSecondaryButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                accent: AppColors.rose,
                onPressed: _busy ? () {} : _confirmSignOut,
              ),
              const SizedBox(height: AppSpacing.lg),
              const FormHint(
                'Your trips live in your account, so they are on every device '
                'you sign in to and survive losing this phone.',
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
          child: Text('Account', style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(width: AppSpacing.md),
        const AppIconTile(icon: Icons.person_rounded, color: AppColors.primary),
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final Session session;

  const _IdentityCard({required this.session});

  /// First letter of the name, or of the email when there is no name.
  String get _initial {
    final name = session.displayName;
    final source = (name != null && name.isNotEmpty) ? name : session.email;
    return source.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = session.displayName;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // Inverse of the canvas — a near-white disc with a dark initial —
              // so the one filled shape on the screen is monochrome, not tinted.
              color: AppColors.text,
            ),
            child: Text(
              _initial,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.canvas,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name == null || name.isEmpty ? 'Signed in' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  session.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

