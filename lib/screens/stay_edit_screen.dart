import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/stay.dart';
import '../services/reminder_scheduler.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/date_pick.dart';
import '../utils/trip_status.dart';
import '../widgets/ui.dart';

/// Create a new stay for [tripId] (when [existing] is null) or edit one.
/// Pops with the saved [Stay] on success, or null if cancelled.
class StayEditScreen extends StatefulWidget {
  final int tripId;
  final Stay? existing;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const StayEditScreen({
    super.key,
    required this.tripId,
    this.existing,
    this.db,
  });

  bool get isEditing => existing != null;

  @override
  State<StayEditScreen> createState() => _StayEditScreenState();
}

class _StayEditScreenState extends State<StayEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hotelController;
  late DateTime _checkInAt;
  late DateTime _checkOutAt;
  bool _saving = false;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _hotelController = TextEditingController(text: existing?.hotelName ?? '');
    final now = DateTime.now();
    final defaultCheckIn = DateTime(now.year, now.month, now.day, 14);
    _checkInAt = existing?.checkInAt ?? defaultCheckIn;
    _checkOutAt =
        existing?.checkOutAt ?? DateTime(now.year, now.month, now.day + 1, 11);
  }

  @override
  void dispose() {
    _hotelController.dispose();
    super.dispose();
  }

  Future<void> _pickCheckIn() async {
    final picked = await pickDateTime(context, initial: _checkInAt);
    if (picked == null) return;
    setState(() {
      _checkInAt = picked;
      // Keep checkout after check-in.
      if (!_checkOutAt.isAfter(_checkInAt)) {
        _checkOutAt = _checkInAt.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickCheckOut() async {
    final picked = await pickDateTime(context, initial: _checkOutAt);
    if (picked == null) return;
    setState(() => _checkOutAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_checkOutAt.isAfter(_checkInAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-out must be after check-in.')),
      );
      return;
    }
    setState(() => _saving = true);

    final stay = Stay(
      id: widget.existing?.id,
      tripId: widget.tripId,
      hotelName: _hotelController.text.trim(),
      checkInAt: _checkInAt,
      checkOutAt: _checkOutAt,
    );

    try {
      final Stay saved;
      if (widget.isEditing) {
        await _db.updateStay(stay);
        saved = stay;
      } else {
        saved = await _db.createStay(stay);
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save stay: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nights = daysBetween(_checkInAt, _checkOutAt);

    return AppFormScaffold(
      formKey: _formKey,
      accent: AppColors.mint,
      title: widget.isEditing ? 'Edit stay' : 'Add stay',
      subtitle: 'Hotel, check-in, and check-out',
      icon: Icons.hotel_rounded,
      actionLabel: widget.isEditing ? 'Save changes' : 'Add stay',
      saving: _saving,
      onAction: _save,
      children: [
        FormSection(
          label: 'Accommodation',
          children: [
            TextFormField(
              controller: _hotelController,
              autofocus: !widget.isEditing,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Hotel name',
                hintText: 'e.g. Hotel Polo Towers',
                prefixIcon: Icon(Icons.hotel_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a hotel name';
                }
                return null;
              },
            ),
          ],
        ),
        FormSection(
          label: 'Schedule',
          children: [
            AppPickerField(
              label: 'Check-in',
              value: formatDateTime(_checkInAt),
              icon: Icons.login_rounded,
              onTap: _pickCheckIn,
            ),
            const SizedBox(height: AppSpacing.md),
            AppPickerField(
              label: 'Check-out',
              value: formatDateTime(_checkOutAt),
              icon: Icons.logout_rounded,
              onTap: _pickCheckOut,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPill(
              label: nights <= 0
                  ? 'Same-day stay'
                  : '$nights night${nights == 1 ? '' : 's'}',
              color: AppColors.mint,
              icon: Icons.bedtime_outlined,
            ),
          ],
        ),
        FormHint(
          'You will get a reminder two hours before check-out '
          '(${formatDateTime(_checkOutAt.subtract(checkoutLeadTime))}), '
          'listing anything still unpacked.',
        ),
      ],
    );
  }
}
