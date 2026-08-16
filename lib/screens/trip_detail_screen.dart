import 'dart:async';

import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/item.dart';
import '../models/stay.dart';
import '../models/transport_leg.dart';
import '../models/trip.dart';
import '../services/reminder_scheduler.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/trip_status.dart';
import '../widgets/checklist.dart';
import '../widgets/ui.dart';
import 'item_edit_screen.dart';
import 'stay_edit_screen.dart';
import 'transport_edit_screen.dart';
import 'trip_edit_screen.dart';

/// Trip detail with tabs. Stays and Transport are fully editable here; Items
/// and Documents arrive in later build steps.
class TripDetailScreen extends StatefulWidget {
  final Trip trip;

  /// Tab to open on. A checkout reminder deep-links straight to Items.
  final int initialTab;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const TripDetailScreen({
    super.key,
    required this.trip,
    this.initialTab = 0,
    this.db,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['Stays', 'Transport', 'Items', 'Documents'];

  late final TabController _tabController;
  late Trip _trip;

  Color get _accent => accentFor(_trip.id ?? 0);

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _tabController = TabController(
      length: _tabs.length,
      initialIndex: widget.initialTab.clamp(0, _tabs.length - 1),
      vsync: this,
    );
    // Rebuild so the contextual FAB matches the active tab.
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _editTrip() async {
    final updated = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(
        builder: (_) => TripEditScreen(existing: _trip, db: widget.db),
      ),
    );
    if (updated != null) setState(() => _trip = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      floatingActionButton: _buildFab(),
      body: AppBackground(
        glow: _accent,
        child: SafeArea(
          child: Column(
            children: [
              _DetailHeader(
                trip: _trip,
                accent: _accent,
                onBack: () => Navigator.of(context).pop(),
                onEdit: _editTrip,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.lg,
                  AppSpacing.gutter,
                  AppSpacing.sm,
                ),
                child: _TabSelector(
                  controller: _tabController,
                  tabs: _tabs,
                  accent: _accent,
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    StaysTab(key: _staysKey, tripId: _trip.id!, db: widget.db),
                    TransportTab(
                      key: _transportKey,
                      tripId: _trip.id!,
                      db: widget.db,
                    ),
                    ChecklistView(
                      key: _itemsKey,
                      tripId: _trip.id!,
                      db: widget.db,
                    ),
                    const AppEmptyState(
                      icon: Icons.folder_copy_outlined,
                      title: 'Document vault',
                      message:
                          'Passports, tickets, and booking confirmations will '
                          'live here in a later build step.',
                      accent: AppColors.violet,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildFab() {
    switch (_tabController.index) {
      case 0:
        return AppFab(
          heroTag: 'add-stay',
          onPressed: _addStay,
          icon: Icons.add_rounded,
          label: 'Add Stay',
        );
      case 1:
        return AppFab(
          heroTag: 'add-transport',
          onPressed: _addTransport,
          icon: Icons.add_rounded,
          label: 'Add Transport',
        );
      case 2:
        return AppFab(
          heroTag: 'add-item',
          onPressed: _addItem,
          icon: Icons.add_rounded,
          label: 'Add Item',
        );
      default:
        return null;
    }
  }

  Future<void> _addStay() async {
    final created = await Navigator.of(context).push<Stay>(
      MaterialPageRoute(
        builder: (_) => StayEditScreen(tripId: _trip.id!, db: widget.db),
      ),
    );
    if (created != null) _staysKey.currentState?.reload();
  }

  Future<void> _addTransport() async {
    final created = await Navigator.of(context).push<TransportLeg>(
      MaterialPageRoute(
        builder: (_) => TransportEditScreen(tripId: _trip.id!, db: widget.db),
      ),
    );
    if (created != null) _transportKey.currentState?.reload();
  }

  Future<void> _addItem() async {
    final created = await Navigator.of(context).push<Item>(
      MaterialPageRoute(
        builder: (_) => ItemEditScreen(tripId: _trip.id!, db: widget.db),
      ),
    );
    if (created != null) _itemsKey.currentState?.reload();
  }

  // Keys let the FAB tell the relevant tab to reload after an add.
  final _staysKey = GlobalKey<_StaysTabState>();
  final _transportKey = GlobalKey<_TransportTabState>();
  final _itemsKey = GlobalKey<ChecklistViewState>();
}

/// Hero header: navigation, trip identity, and at-a-glance trip facts.
class _DetailHeader extends StatelessWidget {
  final Trip trip;
  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const _DetailHeader({
    required this.trip,
    required this.accent,
    required this.onBack,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = tripStatus(trip.startDate, trip.endDate);
    final days = tripLengthInDays(trip.startDate, trip.endDate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                color: AppColors.textMuted,
                tooltip: 'Back',
                onPressed: onBack,
              ),
              const Spacer(),
              Text('Trip details', style: theme.textTheme.labelSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                color: AppColors.textMuted,
                tooltip: 'Edit trip',
                onPressed: onEdit,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              color: Color.alphaBlend(
                accent.withValues(alpha: 0.09),
                AppColors.surface,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          trip.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      AppPill(label: status.label, color: status.color),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          formatDateRange(trip.startDate, trip.endDate),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '$days day${days == 1 ? '' : 's'}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented control that keeps its edges aligned with the content cards
/// instead of running flush against the screen.
class _TabSelector extends StatelessWidget {
  final TabController controller;
  final List<String> tabs;
  final Color accent;

  const _TabSelector({
    required this.controller,
    required this.tabs,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: List.generate(tabs.length, (index) {
              final selected = controller.index == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: tabs[index],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => controller.animateTo(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? accent.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: selected
                              ? accent.withValues(alpha: 0.35)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        tabs[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          letterSpacing: -0.2,
                          color: selected ? accent : AppColors.textMuted,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stays tab
// ---------------------------------------------------------------------------

class StaysTab extends StatefulWidget {
  final int tripId;
  final DatabaseHelper? db;

  const StaysTab({super.key, required this.tripId, this.db});

  @override
  State<StaysTab> createState() => _StaysTabState();
}

class _StaysTabState extends State<StaysTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Stay>> _future;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _db.getStaysForTrip(widget.tripId);
  }

  /// Public so the parent's FAB can trigger a refresh after adding.
  ///
  /// Every stay change lands here, so this is also where checkout reminders
  /// are rebuilt.
  void reload() {
    setState(_load);
    unawaited(Reminders.instance.syncTrip(_db, widget.tripId));
  }

  Future<void> _edit(Stay stay) async {
    final updated = await Navigator.of(context).push<Stay>(
      MaterialPageRoute(
        builder: (_) => StayEditScreen(
          tripId: widget.tripId,
          existing: stay,
          db: widget.db,
        ),
      ),
    );
    if (updated != null) reload();
  }

  Future<void> _confirmDelete(Stay stay) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete stay?',
      message:
          'Remove "${stay.hotelName}" from this trip? '
          'Your packing list is unaffected.',
    );
    if (!confirmed) return;
    // Cancel while the id is still known — the row is about to disappear.
    await Reminders.instance.cancelStays([stay.id!]);
    await _db.deleteStay(stay.id!);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Stay>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppErrorState(message: '${snapshot.error}');
        }
        final stays = snapshot.data ?? const <Stay>[];
        if (stays.isEmpty) {
          return const AppEmptyState(
            icon: Icons.hotel_outlined,
            title: 'No stays yet',
            message: 'Tap “Add Stay” to save a hotel with its check-in and '
                'check-out times.',
            accent: AppColors.mint,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            110,
          ),
          itemCount: stays.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _StayCard(
            stay: stays[index],
            onTap: () => _edit(stays[index]),
            onEdit: () => _edit(stays[index]),
            onDelete: () => _confirmDelete(stays[index]),
          ),
        );
      },
    );
  }
}

class _StayCard extends StatelessWidget {
  final Stay stay;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StayCard({
    required this.stay,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nights = daysBetween(stay.checkInAt, stay.checkOutAt);
    // Mirrors what the scheduler will actually do: no pill once the reminder
    // time has passed, because nothing is pending.
    final fireAt = stay.checkOutAt.subtract(checkoutLeadTime);
    final reminderAt = fireAt.isAfter(DateTime.now()) ? fireAt : null;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppIconTile(
                icon: Icons.hotel_rounded,
                color: AppColors.mint,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stay.hotelName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      nights <= 0
                          ? 'Same-day stay'
                          : '$nights night${nights == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (reminderAt != null) ...[
                      const SizedBox(height: 7),
                      AppPill(
                        label: 'Reminder ${formatTime(reminderAt)}',
                        icon: Icons.notifications_active_outlined,
                        color: AppColors.amber,
                      ),
                    ],
                  ],
                ),
              ),
              AppRowMenu(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: _TimeBlock(
                    label: 'Check-in',
                    icon: Icons.login_rounded,
                    value: stay.checkInAt,
                  ),
                ),
                const _Connector(),
                Expanded(
                  child: _TimeBlock(
                    label: 'Check-out',
                    icon: Icons.logout_rounded,
                    value: stay.checkOutAt,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label + date + time, stacked so long dates never wrap mid-value.
class _TimeBlock extends StatelessWidget {
  final String label;
  final DateTime value;
  final IconData icon;

  const _TimeBlock({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.textFaint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            formatDate(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            formatTime(value),
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 14,
        color: AppColors.textFaint,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transport tab
// ---------------------------------------------------------------------------

class TransportTab extends StatefulWidget {
  final int tripId;
  final DatabaseHelper? db;

  const TransportTab({super.key, required this.tripId, this.db});

  @override
  State<TransportTab> createState() => _TransportTabState();
}

class _TransportTabState extends State<TransportTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<TransportLeg>> _future;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _db.getTransportLegsForTrip(widget.tripId);
  }

  void reload() => setState(_load);

  Future<void> _edit(TransportLeg leg) async {
    final updated = await Navigator.of(context).push<TransportLeg>(
      MaterialPageRoute(
        builder: (_) => TransportEditScreen(
          tripId: widget.tripId,
          existing: leg,
          db: widget.db,
        ),
      ),
    );
    if (updated != null) reload();
  }

  Future<void> _confirmDelete(TransportLeg leg) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete transport?',
      message:
          'Remove the ${leg.type.label.toLowerCase()} from '
          '${leg.fromLocation} to ${leg.toLocation}?',
    );
    if (!confirmed) return;
    await _db.deleteTransportLeg(leg.id!);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<TransportLeg>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppErrorState(message: '${snapshot.error}');
        }
        final legs = snapshot.data ?? const <TransportLeg>[];
        if (legs.isEmpty) {
          return const AppEmptyState(
            icon: Icons.directions_transit_outlined,
            title: 'No transport yet',
            message:
                'Tap “Add Transport” to add a flight, train, or bus between '
                'your stops.',
            accent: AppColors.amber,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            110,
          ),
          itemCount: legs.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _TransportCard(
            leg: legs[index],
            onTap: () => _edit(legs[index]),
            onEdit: () => _edit(legs[index]),
            onDelete: () => _confirmDelete(legs[index]),
          ),
        );
      },
    );
  }
}

class _TransportCard extends StatelessWidget {
  final TransportLeg leg;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TransportCard({
    required this.leg,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  static IconData _iconFor(TransportType type) => switch (type) {
    TransportType.flight => Icons.flight_rounded,
    TransportType.train => Icons.train_rounded,
    TransportType.bus => Icons.directions_bus_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconTile(
                icon: _iconFor(leg.type),
                color: AppColors.amber,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kept as one string so the route reads as a single line.
                    Text(
                      '${leg.fromLocation} → ${leg.toLocation}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(leg.type.label, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              AppRowMenu(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: _TimeBlock(
              label: 'Departure',
              icon: Icons.schedule_rounded,
              value: leg.departureAt,
            ),
          ),
        ],
      ),
    );
  }
}
