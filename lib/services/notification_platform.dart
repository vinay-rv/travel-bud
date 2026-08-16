import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_scheduler.dart';

/// Notification channel for stay checkout reminders (Android only).
const _channelId = 'checkout_reminders';
const _channelName = 'Checkout reminders';
const _channelDescription =
    'Reminds you to pack up before checking out of a hotel.';

/// Delivers [PendingReminder]s through flutter_local_notifications.
///
/// All planning lives in [ReminderScheduler]; this class only knows how to
/// talk to the OS.
class NotificationPlatform implements ReminderPlatform {
  final FlutterLocalNotificationsPlugin _plugin;

  /// Set once [init] has run. Scheduling before that is a no-op rather than a
  /// crash, so a failed init never takes the app down.
  bool _ready = false;

  /// True when the OS lets us schedule to-the-minute alarms. Android 12+ can
  /// refuse, in which case reminders are scheduled inexactly and may arrive
  /// somewhat late.
  bool _canScheduleExact = true;

  NotificationPlatform({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Called when the user taps a notification while the app is running.
  static void Function(String payload)? onSelect;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (e) {
      // Not fatal: reminders are scheduled from an absolute instant, so they
      // still fire at the right moment. Only DST edge cases suffer.
      debugPrint('Could not resolve the local timezone: $e');
    }

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        // Ask on first launch; a checkout reminder is the whole point of the
        // app's notification use, so there is nothing to explain first.
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: true,
      );

      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: darwin),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) onSelect?.call(payload);
        },
      );

      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
        await android?.requestNotificationsPermission();
        _canScheduleExact =
            await android?.canScheduleExactNotifications() ?? false;
      }

      _ready = true;
    } catch (e, stack) {
      // Notifications are a nice-to-have; never block app start on them.
      debugPrint('Notification init failed: $e\n$stack');
      _ready = false;
    }
  }

  /// The payload of a notification that cold-started the app, if any.
  Future<String?> launchPayload() async {
    if (!_ready) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }

  NotificationDetails get _details => NotificationDetails(
    android: const AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    ),
    iOS: const DarwinNotificationDetails(),
  );

  @override
  Future<void> schedule(PendingReminder reminder) async {
    if (!_ready) return;
    try {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: reminder.title,
        body: reminder.body,
        payload: reminder.payload,
        scheduledDate: tz.TZDateTime.from(reminder.when, tz.local),
        notificationDetails: _details,
        androidScheduleMode: _canScheduleExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Could not schedule reminder ${reminder.id}: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }
}

