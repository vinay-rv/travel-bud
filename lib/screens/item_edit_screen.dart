import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/item.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Create a new item for [tripId] (when [existing] is null) or edit one.
/// Items always cover the whole trip, so there is nothing to scope here.
/// Pops with the saved [Item] on success, or null if cancelled.
class ItemEditScreen extends StatefulWidget {
  final int tripId;
  final Item? existing;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const ItemEditScreen({
    super.key,
    required this.tripId,
    this.existing,
    this.db,
  });

  bool get isEditing => existing != null;

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final item = Item(
      id: widget.existing?.id,
      tripId: widget.tripId,
      name: _nameController.text.trim(),
      packed: widget.existing?.packed ?? false,
    );

    try {
      final Item saved;
      if (widget.isEditing) {
        await _db.updateItem(item);
        saved = item;
      } else {
        saved = await _db.createItem(item);
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save item: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormScaffold(
      formKey: _formKey,
      accent: AppColors.violet,
      title: widget.isEditing ? 'Edit item' : 'Add item',
      subtitle: 'Something to pack for this trip',
      icon: Icons.backpack_rounded,
      actionLabel: widget.isEditing ? 'Save changes' : 'Add item',
      saving: _saving,
      onAction: _save,
      children: [
        FormSection(
          label: 'Item',
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: !widget.isEditing,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'e.g. Passport, Charger',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an item name';
                }
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
        const FormHint(
          'Every item travels with you for the whole trip, so it counts at '
          'each hotel — a checkout reminder always covers the full list.',
        ),
      ],
    );
  }
}
