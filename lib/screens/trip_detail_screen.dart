import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/trip.dart';
import '../utils/date_format.dart';
import 'trip_edit_screen.dart';

/// Trip detail. Full tabs (Stays / Transport / Items / Documents) land in
/// later build steps; for now this shows the trip header and an edit action.
class TripDetailScreen extends StatefulWidget {
  final Trip trip;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const TripDetailScreen({super.key, required this.trip, this.db});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late Trip _trip;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
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
      appBar: AppBar(
        title: Text(_trip.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit trip',
            onPressed: _editTrip,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatDateRange(_trip.startDate, _trip.endDate),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            const Card(
              child: ListTile(
                leading: Icon(Icons.construction),
                title: Text('Stays, transport, items & documents'),
                subtitle: Text('Coming in the next build steps.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
