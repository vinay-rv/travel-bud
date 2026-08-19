import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth/api_client.dart';
import 'auth/auth_service.dart';
import 'auth/session.dart';
import 'config/api_config.dart';
import 'data/database_helper.dart';
import 'data/remote_store.dart';
import 'models/trip.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/trip_detail_screen.dart';
import 'services/notification_platform.dart';
import 'services/reminder_scheduler.dart';
import 'theme/app_theme.dart';

/// Lets a notification tap push a route from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Accounts and data. No network here: the session is read from the device, so
  // a signed-in user opens straight into their trips even with no connection.
  final api = ApiClient(
    baseUrl: Uri.parse(apiBaseUrl),
    store: SecureSessionStore(),
  );
  Auth.install(AuthService(api));
  // The server owns the data; the local database is a cache of it.
  DatabaseHelper.instance.remote = ApiRemoteStore(api);

  // Notifications only exist on mobile here; elsewhere the default no-op
  // scheduler stays in place.
  if (Platform.isAndroid || Platform.isIOS) {
    final platform = NotificationPlatform();
    await platform.init();
    Reminders.instance = ReminderScheduler(platform: platform);
    NotificationPlatform.onSelect = _openTripFromPayload;

    // Rebuild the scheduled set from the cache on every launch, so it survives
    // reboots, timezone changes, and edits made while closed.
    unawaited(Reminders.instance.syncAll(DatabaseHelper.instance));

    final launchPayload = await platform.launchPayload();
    if (launchPayload != null) {
      // Wait for the first frame so the navigator exists.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openTripFromPayload(launchPayload),
      );
    }
  }

  runApp(const PackmateApp());
}

/// Payloads look like `trip:12`. Opens that trip's detail screen.
Future<void> _openTripFromPayload(String payload) async {
  if (!payload.startsWith('trip:')) return;
  final tripId = int.tryParse(payload.substring('trip:'.length));
  if (tripId == null) return;

  final Trip? trip = await DatabaseHelper.instance.getTrip(tripId);
  if (trip == null) return;

  final navigator = navigatorKey.currentState;
  if (navigator == null) return;
  navigator.push(
    MaterialPageRoute(
      builder: (_) => TripDetailScreen(trip: trip, initialTab: 2),
    ),
  );
}

class PackmateApp extends StatelessWidget {
  const PackmateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Packmate',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildAppTheme(),
      home: AuthGate(
        auth: Auth.instance,
        // Signing in is what brings an account's trips onto a new phone.
        onSignedIn: () => DatabaseHelper.instance.refreshFromServer(),
      ),
    );
  }
}
