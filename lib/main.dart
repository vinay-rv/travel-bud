import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'data/database_helper.dart';
import 'models/trip.dart';
import 'screens/trip_detail_screen.dart';
import 'screens/trip_list_screen.dart';
import 'services/notification_platform.dart';
import 'services/reminder_scheduler.dart';
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

  runApp(const TripInventoryApp());
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
