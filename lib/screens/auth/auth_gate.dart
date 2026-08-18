import 'package:flutter/material.dart';

import '../../auth/auth_service.dart';
import '../../sync/sync_engine.dart';
import '../../theme/app_theme.dart';
import '../trip_list_screen.dart';
import 'sign_in_screen.dart';

/// Decides whether to show the app or the way in.
///
/// The check is local — a stored session, no network — so a signed-in user
/// opens straight into their trips even with no connection. That is the whole
/// reason the session is persisted rather than re-established each launch: an
/// account is required to *use* Packmate, but not to open it on a plane.
class AuthGate extends StatefulWidget {
  final AuthService auth;

  /// Runs after a successful sign-in, before the app appears — the moment to
  /// pull down whatever the account already has.
  final Future<void> Function()? onSignedIn;

  const AuthGate({super.key, required this.auth, this.onSignedIn});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<void> _restoring;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _restoring = _restore();
  }

  Future<void> _restore() async {
    final session = await widget.auth.restore();
    if (mounted) setState(() => _signedIn = session != null);
  }

  Future<void> _handleSignedIn() async {
    await widget.onSignedIn?.call();
    if (mounted) setState(() => _signedIn = true);
  }

  /// Called when the session ends, from the account screen or because the
  /// server rejected a refresh.
  void handleSignedOut() {
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _restoring,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.canvas,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!_signedIn) {
          return SignInScreen(auth: widget.auth, onSignedIn: _handleSignedIn);
        }

        return TripListScreen(onSignedOut: handleSignedOut);
      },
    );
  }
}

/// Lets any screen end the session and return to sign-in.
///
/// A plain callback passed down rather than a state management package: the app
/// has exactly one piece of global UI state, and one callback is a smaller
/// thing to understand than a dependency.
typedef SignedOutCallback = void Function();

/// Signs out and returns to the entry screen, clearing the device's claim on
/// the account's data so a different account can sign in cleanly afterwards.
Future<void> signOutAndReturn({
  required AuthService auth,
  required SyncEngine sync,
  required SignedOutCallback onSignedOut,
}) async {
  await auth.signOut();
  await sync.forgetAccount();
  onSignedOut();
}
