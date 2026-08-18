import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/item_category.dart';
import '../models/packing_list.dart';
import '../theme/category_style.dart';
import '../widgets/item_fields.dart';
import '../widgets/ui.dart';

/// Add an entry to a saved list (when [existing] is null) or edit one.
/// Pops with the saved [PackingListEntry] on success, or null if cancelled.
class PackingEntryEditScreen extends StatefulWidget {
  final int listId;
  final PackingListEntry? existing;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const PackingEntryEditScreen({
    super.key,
    required this.listId,
    this.existing,
    this.db,
  });

  bool get isEditing => existing != null;

  @override
  State<PackingEntryEditScreen> createState() => _PackingEntryEditScreenState();
}

class _PackingEntryEditScreenState extends State<PackingEntryEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late ItemCategory _category;
  late int _quantity;
  bool _saving = false;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _category = widget.existing?.category ?? ItemCategory.other;
    _quantity = widget.existing?.quantity ?? 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final entry = PackingListEntry(
      id: widget.existing?.id,
      listId: widget.listId,
      name: _nameController.text.trim(),
      category: _category,
      quantity: _quantity,
    );

    try {
      final PackingListEntry saved;
      if (widget.isEditing) {
        await _db.updatePackingListEntry(entry);
        saved = entry;
      } else {
        saved = await _db.addPackingListEntry(entry);
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
      accent: _category.color,
      title: widget.isEditing ? 'Edit item' : 'Add item',
      subtitle: 'Part of this saved list',
      icon: _category.icon,
      actionLabel: widget.isEditing ? 'Save changes' : 'Add item',
      saving: _saving,
      onAction: _save,
      children: [
        ItemFields(
          nameController: _nameController,
          category: _category,
          quantity: _quantity,
          autofocus: !widget.isEditing,
          onCategoryChanged: (value) => setState(() => _category = value),
          onQuantityChanged: (value) => setState(() => _quantity = value),
          onSubmitted: _save,
        ),
        const FormHint(
          'Saved list items are a template. Adding one here changes future '
          'trips you build from this list, not trips you already made.',
        ),
      ],
    );
  }
}
