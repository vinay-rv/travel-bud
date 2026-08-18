import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/database_helper.dart';
import 'models/trip.dart';
import 'screens/trip_detail_screen.dart';
import 'screens/trip_list_screen.dart';
import 'services/notification_platform.dart';
import 'services/reminder_scheduler.dart';
import 'sync/supabase_remote.dart';
import 'sync/sync_config.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_trigger.dart';
import 'theme/app_theme.dart';

/// Lets a notification tap push a route from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notifications only exist on mobile here; elsewhere the default no-op
  // scheduler stays in place.
  if (Platform.isAndroid || Platform.isIOS) {
    final platform = NotificationPlatform();
    await platform.init();
    Reminders.instance = ReminderScheduler(platform: platform);
    NotificationPlatform.onSelect = _openTripFromPayload;

    // Rebuild the scheduled set from the database on every launch, so it
    // survives reboots, timezone changes, and edits made while closed.
    unawaited(Reminders.instance.syncAll(DatabaseHelper.instance));

    final launchPayload = await platform.launchPayload();
    if (launchPayload != null) {
      // Wait for the first frame so the navigator exists.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openTripFromPayload(launchPayload),
      );
    }
  }

  await _initSync();

  runApp(const TripInventoryApp());
}

/// Prepares backup and sync, if this build was configured for it.
///
/// Deliberately does not sign anyone in and makes no network call: backup is
/// opt-in, so nothing about a user's trips leaves the device until they ask for
/// it. `Supabase.initialize` only restores a session already stored locally.
///
/// Any failure here is swallowed for the same reason notification setup is
/// (`notification_platform.dart`): the app has to open and work regardless.
/// Until this succeeds, `Sync.instance` keeps its no-op remote and simply
/// reports that there is no account.
Future<void> _initSync() async {
  if (!syncConfigured) return;

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
    Sync.instance = SyncEngine(
      db: DatabaseHelper.instance,
      remote: SupabaseRemote(),
    );
    // From here sync looks after itself: on edits, and on returning to the
    // foreground. No screen has to remember to ask.
    SyncTrigger(db: DatabaseHelper.instance, engine: () => Sync.instance)
        .start();
    // Picks up anything left unsynced last time — a no-op unless the user has
    // already opted in, since the engine stops at "no account".
    unawaited(Sync.instance.sync());
  } catch (error, stack) {
    debugPrint('Sync unavailable this launch: $error');
    debugPrintStack(stackTrace: stack);
  }
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

class TripInventoryApp extends StatelessWidget {
  const TripInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Packmate',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildAppTheme(),
      home: const TripListScreen(),
    );
  }
}
