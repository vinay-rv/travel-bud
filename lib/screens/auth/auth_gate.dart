import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/auth_service.dart';
import '../../data/database_helper.dart';
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

  /// Injectable for tests; the app-wide singleton otherwise.
  final DatabaseHelper? db;

  /// Runs after a successful sign-in to pull down whatever the account already
  /// has. Deliberately not awaited before the app appears: it is a background
  /// refresh, not a gate.
  final Future<void> Function()? onSignedIn;

  const AuthGate({super.key, required this.auth, this.onSignedIn, this.db});

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

  void _handleSignedIn() {
    if (!mounted) return;

    // Show the app first. The trips live on the device, so there is nothing to
    // wait for — and a sync that is slow, or wedged, must never leave someone
    // staring at a spinner on the sign-in button.
    setState(() => _signedIn = true);

    // Sign-up and confirm-email are pushed on top of this gate. Swapping the
    // child underneath them is not enough: without this the user stays on the
    // code screen and nothing appears to happen.
    Navigator.of(context).popUntil((route) => route.isFirst);

    // Now pull down whatever the account already has, in the background.
    unawaited(Future<void>.sync(() async {
      try {
        await widget.onSignedIn?.call();
      } catch (error) {
        debugPrint('First sync after sign-in failed: $error');
      }
    }));
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

        return TripListScreen(db: widget.db, onSignedOut: handleSignedOut);
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

/// Signs out and returns to the entry screen.
///
/// The cache is emptied on the way out: it holds one account's trips, and
/// leaving them on the device for whoever signs in next would be both confusing
/// and a small privacy leak.
Future<void> signOutAndReturn({
  required AuthService auth,
  required DatabaseHelper db,
  required SignedOutCallback onSignedOut,
}) async {
  await auth.signOut();
  await db.clearCache();
  onSignedOut();
}
