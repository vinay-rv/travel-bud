import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/trip.dart';
import '../services/reminder_scheduler.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/trip_status.dart';
import '../widgets/ui.dart';
import '../widgets/app_bottom_bar.dart';
import 'account_screen.dart';
import 'saved_lists_screen.dart';
import 'trip_detail_screen.dart';
import 'trip_edit_screen.dart';

/// Home screen: lists all trips, and lets the user create, edit, or delete them.
class TripListScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  /// Lets the account screen end the session and send the app back to sign-in.
  final VoidCallback? onSignedOut;

  const TripListScreen({super.key, this.db, this.onSignedOut});

  @override
  State<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends State<TripListScreen> {
  late Future<List<Trip>> _tripsFuture;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _tripsFuture = _db.getTrips();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _tripsFuture;
  }

  Future<void> _createTrip() async {
    final created = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(builder: (_) => TripEditScreen(db: widget.db)),
    );
    if (created != null) setState(_reload);
  }

  Future<void> _editTrip(Trip trip) async {
    final updated = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(
        builder: (_) => TripEditScreen(existing: trip, db: widget.db),
      ),
    );
    if (updated != null) setState(_reload);
  }

  Future<void> _openTrip(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripDetailScreen(
          trip: trip,
          db: widget.db,
          onSignedOut: widget.onSignedOut,
        ),
      ),
    );
    setState(_reload);
  }

  Future<void> _openSavedLists() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SavedListsScreen(db: widget.db)),
    );
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          db: widget.db,
          onSignedOut: widget.onSignedOut,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Trip trip) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete trip?',
      message:
          'This permanently removes "${trip.name}" and all its stays, '
          'transport, items, and documents.',
    );
    if (!confirmed) return;
    // Deleting the trip cascades its stays away, so cancel their reminders
    // while the ids can still be read.
    final stays = await _db.getStaysForTrip(trip.id!);
    await Reminders.instance.cancelStays(
      stays.map((s) => s.id).whereType<int>(),
    );
    await _db.deleteTrip(trip.id!);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      bottomNavigationBar: AppBottomBar(
        // Already home, so the slot marks where you are rather than offering
        // to take you there.
        onHome: null,
        onAction: _createTrip,
        actionLabel: 'Trip',
        onAccount: _openAccount,
      ),
      body: AppBackground(
        child: SafeArea(
          child: FutureBuilder<List<Trip>>(
            future: _tripsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final trips = snapshot.data ?? const <Trip>[];

              return RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceAlt,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Greeting(
                        trips: trips,
                        onOpenSavedLists: _openSavedLists,
                      ),
                    ),
                    if (snapshot.hasError)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppErrorState(message: '${snapshot.error}'),
                      )
                    else if (trips.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppEmptyState(
                          icon: Icons.luggage_outlined,
                          title: 'No trips yet',
                          message:
                              'Plan your first trip and keep every booking, '
                              'route, and packing list in one place.',
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.gutter,
                          AppSpacing.xl,
                          AppSpacing.gutter,
                          AppSpacing.md,
                        ),
                        sliver: const SliverToBoxAdapter(
                          child: SectionLabel(label: 'Your itineraries'),
                        ),
                      ),
                      SliverPadding(
                        // The bottom bar insets the body itself, so this is
                        // ordinary breathing room rather than clearance for a
                        // button floating over the last card.
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.gutter,
                          0,
                          AppSpacing.gutter,
                          AppSpacing.xl,
                        ),
                        sliver: SliverList.separated(
                          itemCount: trips.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.md),
                          itemBuilder: (context, index) {
                            final trip = trips[index];
                            return _TripCard(
                              trip: trip,
                              accent: accentFor(trip.id ?? index),
                              onTap: () => _openTrip(trip),
                              onEdit: () => _editTrip(trip),
                              onDelete: () => _confirmDelete(trip),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Page header: brand mark, headline, and a one-line read on what's coming up.
class _Greeting extends StatelessWidget {
  final List<Trip> trips;
  final VoidCallback onOpenSavedLists;

  const _Greeting({
    required this.trips,
    required this.onOpenSavedLists,
  });

  /// The soonest trip that hasn't finished yet, if any.
  Trip? get _next {
    final now = DateTime.now();
    final live =
        trips.where((t) => daysBetween(now, t.endDate) >= 0).toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return live.isEmpty ? null : live.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = _next;
    final status = next == null
        ? null
        : tripStatus(next.startDate, next.endDate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(),
              const SizedBox(width: AppSpacing.md),
              // Takes the slack rather than a Spacer: with the saved-lists
              // button and the count pill also on this row, a fixed-width
              // brand overflows on a 360dp phone or at a large text scale.
              Expanded(
                child: Text(
                  'Packmate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPill(
                label: trips.isEmpty
                    ? 'Empty'
                    : '${trips.length} trip${trips.length == 1 ? '' : 's'}',
                icon: Icons.map_outlined,
              ),
              IconButton(
                icon: const Icon(Icons.bookmarks_outlined),
                color: AppColors.textMuted,
                tooltip: 'Saved lists',
                onPressed: onOpenSavedLists,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text('Your trips', style: theme.textTheme.displaySmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                next == null
                    ? Icons.nightlight_round
                    : Icons.flight_takeoff_rounded,
                size: 16,
                color: status?.color ?? AppColors.textFaint,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  next == null
                      ? 'Nothing on the horizon — time to plan something.'
                      : status!.phase == TripPhase.ongoing
                      ? 'Trip in progress · ${status.label}'
                      : 'Next departure ${status.label.toLowerCase()}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: next == null
                        ? AppColors.textMuted
                        : AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TripCard({
    required this.trip,
    required this.accent,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = tripStatus(trip.startDate, trip.endDate);
    final nights = tripLengthInDays(trip.startDate, trip.endDate) - 1;
    final dimmed = status.phase == TripPhase.past;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  accent.withValues(alpha: dimmed ? 0.04 : 0.10),
                  AppColors.surface,
                ),
                AppColors.surface,
              ],
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIconTile(
                      icon: Icons.location_on_rounded,
                      color: dimmed ? AppColors.textFaint : accent,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: dimmed
                                  ? AppColors.textMuted
                                  : AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            formatDateRange(trip.startDate, trip.endDate),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    AppRowMenu(onEdit: onEdit, onDelete: onDelete),
                  ],
                ),
              ),
              const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: AppPill(
                              label: status.label,
                              color: status.color,
                              icon: status.phase == TripPhase.ongoing
                                  ? Icons.play_arrow_rounded
                                  : Icons.schedule_rounded,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: AppPill(
                              label: nights == 0
                                  ? 'Day trip'
                                  : '$nights night${nights == 1 ? '' : 's'}',
                              color: AppColors.textMuted,
                              icon: Icons.bedtime_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: dimmed ? AppColors.textFaint : accent,
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
}
