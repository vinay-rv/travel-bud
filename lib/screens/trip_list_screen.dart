import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/trip.dart';
import '../utils/date_format.dart';
import 'trip_detail_screen.dart';
import 'trip_edit_screen.dart';

/// Home screen: lists all trips, and lets the user create, edit, or delete them.
class TripListScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const TripListScreen({super.key, this.db});

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
        builder: (_) => TripDetailScreen(trip: trip, db: widget.db),
      ),
    );
    // Trip name/dates may have changed inside the detail screen.
    setState(_reload);
  }

  Future<void> _confirmDelete(Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete trip?'),
        content: Text(
          'This permanently removes "${trip.name}" and all its stays, '
          'transport, items, and documents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteTrip(trip.id!);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Trips')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTrip,
        icon: const Icon(Icons.add),
        label: const Text('New Trip'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Trip>>(
          future: _tripsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(message: '${snapshot.error}');
            }
            final trips = snapshot.data ?? const [];
            if (trips.isEmpty) {
              return const _EmptyState();
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: trips.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final trip = trips[index];
                return _TripCard(
                  trip: trip,
                  onTap: () => _openTrip(trip),
                  onEdit: () => _editTrip(trip),
                  onDelete: () => _confirmDelete(trip),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TripCard({
    required this.trip,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.luggage,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          trip.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(formatDateRange(trip.startDate, trip.endDate)),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // ListView so RefreshIndicator still works when there are no trips.
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.luggage_outlined,
            size: 72, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No trips yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text('Tap “New Trip” to plan your first one.'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline,
            size: 64, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 16),
        Center(child: Text('Something went wrong.\n$message',
            textAlign: TextAlign.center)),
      ],
    );
  }
}
