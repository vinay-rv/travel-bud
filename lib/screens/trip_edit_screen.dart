import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/trip.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/trip_status.dart';
import '../widgets/ui.dart';

/// Create a new trip (when [existing] is null) or edit an existing one.
/// Pops with the saved [Trip] on success, or null if cancelled.
class TripEditScreen extends StatefulWidget {
  final Trip? existing;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const TripEditScreen({super.key, this.existing, this.db});

  bool get isEditing => existing != null;

  @override
  State<TripEditScreen> createState() => _TripEditScreenState();
}

class _TripEditScreenState extends State<TripEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    final now = DateTime.now();
    _startDate = existing?.startDate ?? DateTime(now.year, now.month, now.day);
    _endDate = existing?.endDate ?? _startDate.add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Departure date',
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      // Keep the range valid: nudge the end date forward if needed.
      if (_endDate.isBefore(_startDate)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
      helpText: 'Return date',
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final trip = Trip(
      id: widget.existing?.id,
      name: _nameController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
    );

    final db = widget.db ?? DatabaseHelper.instance;
    try {
      final Trip saved;
      if (widget.isEditing) {
        await db.updateTrip(trip);
        saved = trip;
      } else {
        saved = await db.createTrip(trip);
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save trip: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = tripLengthInDays(_startDate, _endDate);

    return AppFormScaffold(
      formKey: _formKey,
      title: widget.isEditing ? 'Edit trip' : 'New trip',
      subtitle: widget.isEditing
          ? 'Update the name or the dates'
          : 'Where are you heading next?',
      icon: Icons.explore_rounded,
      actionLabel: widget.isEditing ? 'Save changes' : 'Create trip',
      saving: _saving,
      onAction: _save,
      children: [
        FormSection(
          label: 'Destination',
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: !widget.isEditing,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Trip name',
                hintText: 'e.g. Northeast India',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a trip name';
                }
                return null;
              },
            ),
          ],
        ),
        FormSection(
          label: 'Dates',
          children: [
            AppPickerField(
              label: 'Start date',
              value: formatDate(_startDate),
              icon: Icons.flight_takeoff_rounded,
              onTap: _pickStartDate,
            ),
            const SizedBox(height: AppSpacing.md),
            AppPickerField(
              label: 'End date',
              value: formatDate(_endDate),
              icon: Icons.flight_land_rounded,
              onTap: _pickEndDate,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                AppPill(
                  label: '$days day${days == 1 ? '' : 's'}',
                  icon: Icons.event_available_rounded,
                ),
                const SizedBox(width: AppSpacing.sm),
                AppPill(
                  label: days == 1
                      ? 'Day trip'
                      : '${days - 1} night${days - 1 == 1 ? '' : 's'}',
                  color: AppColors.mint,
                  icon: Icons.bedtime_outlined,
                ),
              ],
            ),
          ],
        ),
        const FormHint(
          'Stays, transport, packing items, and documents all hang off this '
          'trip, so you can set the dates roughly and refine them later.',
        ),
      ],
    );
  }
}
