import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../data/remote_store.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/date_pick.dart';
import '../widgets/ui.dart';

/// Record something spent on [tripId], or edit one.
/// Pops with the saved [Expense], or null if cancelled.
class ExpenseEditScreen extends StatefulWidget {
  final int tripId;
  final Expense? existing;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const ExpenseEditScreen({
    super.key,
    required this.tripId,
    this.existing,
    this.db,
  });

  bool get isEditing => existing != null;

  @override
  State<ExpenseEditScreen> createState() => _ExpenseEditScreenState();
}

class _ExpenseEditScreenState extends State<ExpenseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late DateTime _spentAt;
  bool _saving = false;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _amountController = TextEditingController(
      text: existing == null ? '' : formatMinor(existing.amountMinor).replaceAll(',', ''),
    );
    // Defaults to now, but stays editable: yesterday's taxi usually gets typed
    // in this morning.
    _spentAt = existing?.spentAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickSpentAt() async {
    final picked = await pickDateTime(context, initial: _spentAt);
    if (picked == null) return;
    setState(() => _spentAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final expense = Expense(
      id: widget.existing?.id,
      tripId: widget.tripId,
      name: _nameController.text.trim(),
      amountMinor: parseMinor(_amountController.text)!,
      spentAt: _spentAt,
    );

    try {
      final Expense saved;
      if (widget.isEditing) {
        await _db.updateExpense(expense);
        saved = expense;
      } else {
        saved = await _db.createExpense(expense);
      }
      if (mounted) Navigator.of(context).pop(saved);
    } on RemoteUnavailable {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No connection — the expense was not saved.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save expense: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormScaffold(
      formKey: _formKey,
      accent: AppColors.amber,
      title: widget.isEditing ? 'Edit expense' : 'Add expense',
      subtitle: 'What you spent, and when',
      icon: Icons.receipt_long_rounded,
      actionLabel: widget.isEditing ? 'Save changes' : 'Add expense',
      saving: _saving,
      onAction: _save,
      children: [
        FormSection(
          label: 'Expense',
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: !widget.isEditing,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'What was it for',
                hintText: 'e.g. Airport taxi',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Give the expense a name';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: 'e.g. 12.50',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter the amount';
                // Refuses more than two decimals rather than rounding part of
                // someone's money away without telling them.
                if (parseMinor(text) == null) {
                  return 'Use a number like 12.50';
                }
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
        FormSection(
          label: 'When',
          children: [
            AppPickerField(
              label: 'Spent at',
              value: formatDateTime(_spentAt),
              icon: Icons.schedule_rounded,
              onTap: _pickSpentAt,
            ),
          ],
        ),
        const FormHint(
          'Amounts are all in one currency for now — a trip that crosses a '
          'border will need more than this.',
        ),
      ],
    );
  }
}
