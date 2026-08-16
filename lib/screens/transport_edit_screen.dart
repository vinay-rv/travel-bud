import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/transport_leg.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/date_pick.dart';
import '../widgets/ui.dart';

/// Create a new transport leg for [tripId] (when [existing] is null) or edit
/// one. Pops with the saved [TransportLeg] on success, or null if cancelled.
class TransportEditScreen extends StatefulWidget {
  final int tripId;
  final TransportLeg? existing;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const TransportEditScreen({
    super.key,
    required this.tripId,
    this.existing,
    this.db,
  });

  bool get isEditing => existing != null;

  @override
  State<TransportEditScreen> createState() => _TransportEditScreenState();
}

class _TransportEditScreenState extends State<TransportEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late TransportType _type;
  late DateTime _departureAt;
  bool _saving = false;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _fromController = TextEditingController(text: existing?.fromLocation ?? '');
    _toController = TextEditingController(text: existing?.toLocation ?? '');
    _type = existing?.type ?? TransportType.flight;
    final now = DateTime.now();
    _departureAt =
        existing?.departureAt ??
        DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  Future<void> _pickDeparture() async {
    final picked = await pickDateTime(context, initial: _departureAt);
    if (picked == null) return;
    setState(() => _departureAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final leg = TransportLeg(
      id: widget.existing?.id,
      tripId: widget.tripId,
      type: _type,
      departureAt: _departureAt,
      fromLocation: _fromController.text.trim(),
      toLocation: _toController.text.trim(),
    );

    try {
      final TransportLeg saved;
      if (widget.isEditing) {
        await _db.updateTransportLeg(leg);
        saved = leg;
      } else {
        saved = await _db.createTransportLeg(leg);
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save transport: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormScaffold(
      formKey: _formKey,
      accent: AppColors.amber,
      title: widget.isEditing ? 'Edit transport' : 'Add transport',
      subtitle: 'How you get from one stop to the next',
      icon: _iconFor(_type),
      actionLabel: widget.isEditing ? 'Save changes' : 'Add transport',
      saving: _saving,
      onAction: _save,
      children: [
        FormSection(
          label: 'Mode',
          children: [
            _TypeSelector(
              value: _type,
              onChanged: (type) => setState(() => _type = type),
            ),
          ],
        ),
        FormSection(
          label: 'Route',
          children: [
            TextFormField(
              controller: _fromController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'From',
                hintText: 'e.g. Guwahati',
                prefixIcon: Icon(Icons.trip_origin_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a departure location';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _toController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'To',
                hintText: 'e.g. Shillong',
                prefixIcon: Icon(Icons.place_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a destination';
                }
                return null;
              },
            ),
          ],
        ),
        FormSection(
          label: 'Timing',
          children: [
            AppPickerField(
              label: 'Departure',
              value: formatDateTime(_departureAt),
              icon: Icons.schedule_rounded,
              onTap: _pickDeparture,
            ),
          ],
        ),
        const FormHint(
          'Pre-departure reminders will be scheduled from this time.',
        ),
      ],
    );
  }
}

IconData _iconFor(TransportType type) => switch (type) {
  TransportType.flight => Icons.flight_rounded,
  TransportType.train => Icons.train_rounded,
  TransportType.bus => Icons.directions_bus_rounded,
};

/// Segmented picker — with only three modes, showing them all beats hiding
/// them behind a dropdown.
class _TypeSelector extends StatelessWidget {
  final TransportType value;
  final ValueChanged<TransportType> onChanged;

  const _TypeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final type in TransportType.values) ...[
          Expanded(
            child: _TypeOption(
              type: type,
              selected: type == value,
              onTap: () => onChanged(type),
            ),
          ),
          if (type != TransportType.values.last)
            const SizedBox(width: AppSpacing.md),
        ],
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  final TransportType type;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.amber.withValues(alpha: 0.14)
                  : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected
                    ? AppColors.amber.withValues(alpha: 0.45)
                    : AppColors.border,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _iconFor(type),
                  size: 22,
                  color: selected ? AppColors.amber : AppColors.textMuted,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? AppColors.amber : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
