import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:packmate/data/database_helper.dart';
import 'package:packmate/models/item.dart';
import 'package:packmate/models/stay.dart';
import 'package:packmate/models/trip.dart';
import 'package:packmate/services/reminder_scheduler.dart';

/// Records what the platform was asked to do, so the planning logic can be
/// asserted without any notifications plugin.
class FakePlatform implements ReminderPlatform {
  final List<PendingReminder> scheduled = [];
  final List<int> cancelled = [];
  int cancelAllCount = 0;

  @override
  Future<void> schedule(PendingReminder reminder) async {
    scheduled.add(reminder);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseHelper db;
  late FakePlatform platform;
  late Trip trip;

  // Pin "now" so the fixtures below are deterministic.
  final now = DateTime(2026, 3, 1, 9);
  ReminderScheduler scheduler() =>
      ReminderScheduler(platform: platform, clock: () => now);

  setUp(() async {
    db = DatabaseHelper.forTesting(inMemoryDatabasePath);
    platform = FakePlatform();
    trip = await db.createTrip(Trip(
      name: 'Northeast India',
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 3, 8),
    ));
  });

  tearDown(() => db.close());

  Future<Stay> seedStay({
    String hotel = 'Hotel Polo Towers',
    required DateTime checkOutAt,
  }) {
    return db.createStay(Stay(
      tripId: trip.id!,
      hotelName: hotel,
      checkInAt: checkOutAt.subtract(const Duration(days: 2)),
      checkOutAt: checkOutAt,
    ));
  }

  test('schedules one reminder per stay, two hours before checkout', () async {
    await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));
    await seedStay(hotel: 'Cherrapunji Homestay',
        checkOutAt: DateTime(2026, 3, 6, 10));

    await scheduler().syncTrip(db, trip.id!);

    expect(platform.scheduled.length, 2);
    expect(platform.scheduled.first.when, DateTime(2026, 3, 4, 9));
    expect(platform.scheduled.last.when, DateTime(2026, 3, 6, 8));
    expect(checkoutLeadTime, const Duration(hours: 2));
  });

  test('the reminder names the hotel, checkout time, and unpacked items',
      () async {
    await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));
    await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
    await db.createItem(Item(tripId: trip.id!, name: 'Charger'));

    await scheduler().syncTrip(db, trip.id!);

    final reminder = platform.scheduled.single;
    expect(reminder.title, 'Checkout at 11:00 AM');
    expect(reminder.body, contains('Hotel Polo Towers'));
    expect(reminder.body, contains('Passport'));
    expect(reminder.body, contains('Charger'));
    expect(reminder.payload, 'trip:${trip.id}');
  });

  test('packed items drop out of the reminder body', () async {
    await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));
    final charger =
        await db.createItem(Item(tripId: trip.id!, name: 'Charger'));
    await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
    await db.setItemPacked(charger.id!, true);

    await scheduler().syncTrip(db, trip.id!);

    final body = platform.scheduled.single.body;
    expect(body, contains('Passport'));
    expect(body, isNot(contains('Charger')));
  });

  test('a fully packed list still reminds, without naming items', () async {
    await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));
    final item = await db.createItem(Item(tripId: trip.id!, name: 'Passport'));
    await db.setItemPacked(item.id!, true);

    await scheduler().syncTrip(db, trip.id!);

    final body = platform.scheduled.single.body;
    expect(body, contains('Everything on your list is packed'));
    expect(body, isNot(contains('Passport')));
  });

  test('long lists are truncated to three names plus a count', () async {
    await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));
    for (final name in ['A', 'B', 'C', 'D', 'E']) {
      await db.createItem(Item(tripId: trip.id!, name: name));
    }

    await scheduler().syncTrip(db, trip.id!);

    expect(platform.scheduled.single.body, contains('A, B, C, and 2 more'));
  });

  test('a checkout already past its lead time is not scheduled', () async {
    // Checkout is 10:00 today; the 08:00 reminder is behind "now" (09:00).
    await seedStay(checkOutAt: DateTime(2026, 3, 1, 10));

    await scheduler().syncTrip(db, trip.id!);

    expect(platform.scheduled, isEmpty);
    // It is still cancelled, in case an earlier sync had scheduled it.
    expect(platform.cancelled, isNotEmpty);
  });

  test('re-syncing replaces the previous reminder for the same stay',
      () async {
    final stay = await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));
    await scheduler().syncTrip(db, trip.id!);

    await db.updateStay(
      stay.copyWith(checkOutAt: DateTime(2026, 3, 5, 12)),
    );
    await scheduler().syncTrip(db, trip.id!);

    expect(platform.cancelled,
        everyElement(equals(checkoutNotificationId(stay.id!))));
    expect(platform.scheduled.last.when, DateTime(2026, 3, 5, 10));
    // Same stay, so the id is stable across syncs.
    expect(platform.scheduled.map((r) => r.id).toSet().single,
        checkoutNotificationId(stay.id!));
  });

  test('cancelStays drops the reminder ids for deleted stays', () async {
    final stay = await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));

    await scheduler().cancelStays([stay.id!]);

    expect(platform.cancelled, [checkoutNotificationId(stay.id!)]);
  });

  test('syncAll clears everything, then rebuilds across trips', () async {
    await seedStay(checkOutAt: DateTime(2026, 3, 4, 11));
    final other = await db.createTrip(Trip(
      name: 'Goa',
      startDate: DateTime(2026, 4, 1),
      endDate: DateTime(2026, 4, 4),
    ));
    await db.createStay(Stay(
      tripId: other.id!,
      hotelName: 'Beach Shack',
      checkInAt: DateTime(2026, 4, 1, 14),
      checkOutAt: DateTime(2026, 4, 4, 11),
    ));

    await scheduler().syncAll(db);

    expect(platform.cancelAllCount, 1);
    expect(platform.scheduled.length, 2);
    expect(
      platform.scheduled.map((r) => r.payload),
      containsAll(['trip:${trip.id}', 'trip:${other.id}']),
    );
  });
}
