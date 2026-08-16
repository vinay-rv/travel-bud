import '../data/database_helper.dart';
import '../models/item.dart';
import '../models/stay.dart';
import '../utils/date_format.dart';

/// How long before checkout the reminder fires. Long enough to actually pack
/// and sweep the room, short enough that the list is still relevant.
const checkoutLeadTime = Duration(hours: 2);

/// Notification id space. Each reminder kind gets its own block so ids stay
/// stable and never collide across kinds.
const _checkoutIdBase = 100000;

/// The stable notification id for a stay's checkout reminder.
int checkoutNotificationId(int stayId) => _checkoutIdBase + stayId;

/// One notification to be delivered at [when].
class PendingReminder {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  final String payload;

  const PendingReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    required this.payload,
  });

  @override
  String toString() => 'PendingReminder($id, $when, $title, $body)';
}

/// The platform side of scheduling, kept behind an interface so the planning
/// logic below can be tested without the notifications plugin.
abstract class ReminderPlatform {
  Future<void> schedule(PendingReminder reminder);
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

/// Decides which checkout reminders should exist and keeps the platform's
/// scheduled set in sync with the database.
///
/// Every reminder is rebuilt from scratch on each sync: the body names the
/// items still unpacked, so it goes stale whenever stays or items change.
/// Callers should [syncTrip] after any such edit. The database is passed per
/// call rather than held, so screens sync through whichever helper they use.
class ReminderScheduler {
  final ReminderPlatform platform;

  /// Injectable so tests can pin "now".
  final DateTime Function() clock;

  ReminderScheduler({required this.platform, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  /// Builds the reminder for one stay, or null when it should not be
  /// scheduled (no id yet, or the fire time has already passed).
  PendingReminder? reminderFor(
    int tripId,
    Stay stay,
    List<Item> unpackedItems,
  ) {
    final stayId = stay.id;
    if (stayId == null) return null;

    final when = stay.checkOutAt.subtract(checkoutLeadTime);
    if (!when.isAfter(clock())) return null;

    return PendingReminder(
      id: checkoutNotificationId(stayId),
      when: when,
      title: 'Checkout at ${formatTime(stay.checkOutAt)}',
      body: _body(stay, unpackedItems),
      payload: 'trip:$tripId',
    );
  }

  String _body(Stay stay, List<Item> unpacked) {
    if (unpacked.isEmpty) {
      return 'Leaving ${stay.hotelName}. Everything on your list is packed — '
          'do a last sweep of the room.';
    }
    final names = unpacked.map((i) => i.name).toList();
    final shown = names.take(3).join(', ');
    final rest = names.length - 3;
    final tail = rest > 0 ? ', and $rest more' : '';
    return 'Leaving ${stay.hotelName}. Still unpacked: $shown$tail.';
  }

  /// Rebuilds every checkout reminder for one trip.
  Future<void> syncTrip(DatabaseHelper db, int tripId) async {
    final stays = await db.getStaysForTrip(tripId);
    final unpacked = await db.getUnpackedItemsForTrip(tripId);

    for (final stay in stays) {
      final stayId = stay.id;
      if (stayId == null) continue;
      // Cancel first: a stay whose checkout moved into the past must not keep
      // an older pending notification.
      await platform.cancel(checkoutNotificationId(stayId));
      final reminder = reminderFor(tripId, stay, unpacked);
      if (reminder != null) await platform.schedule(reminder);
    }
  }

  /// Drops the reminders for [stayIds] — call before deleting a stay or trip,
  /// while the ids are still known.
  Future<void> cancelStays(Iterable<int> stayIds) async {
    for (final id in stayIds) {
      await platform.cancel(checkoutNotificationId(id));
    }
  }

  /// Rebuilds reminders for every trip. Run at startup so the scheduled set
  /// survives reboots, timezone changes, and edits made while the app was
  /// closed.
  Future<void> syncAll(DatabaseHelper db) async {
    await platform.cancelAll();
    for (final trip in await db.getTrips()) {
      if (trip.id != null) await syncTrip(db, trip.id!);
    }
  }
}

/// App-wide scheduler. `main` swaps in one backed by the real notification
/// platform; the default no-ops so tests and any pre-init call are safe.
class Reminders {
  Reminders._();

  static ReminderScheduler instance = ReminderScheduler(
    platform: const _NoopPlatform(),
  );
}

class _NoopPlatform implements ReminderPlatform {
  const _NoopPlatform();

  @override
  Future<void> schedule(PendingReminder reminder) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}
