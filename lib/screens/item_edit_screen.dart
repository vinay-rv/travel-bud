import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/bag.dart';
import '../models/item.dart';
import '../models/item_category.dart';
import '../theme/category_style.dart';
import '../widgets/item_fields.dart';
import '../widgets/ui.dart';

/// Create a new item for [tripId] (when [existing] is null) or edit one.
/// Items always cover the whole trip; what varies is the category it files
/// under and how many to bring.
/// Pops with the saved [Item] on success, or null if cancelled.
class ItemEditScreen extends StatefulWidget {
  final int tripId;
  final Item? existing;

  /// Preselects a category — used when adding from within a category.
  final ItemCategory? initialCategory;

  /// Preselects a bag — used when adding from within one.
  final int? initialBagId;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const ItemEditScreen({
    super.key,
    required this.tripId,
    this.existing,
    this.initialCategory,
    this.initialBagId,
    this.db,
  });

  bool get isEditing => existing != null;

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late ItemCategory _category;
  late int _quantity;
  int? _bagId;
  bool _saving = false;

  /// The trip's bags. Empty until they load, which only costs the bag chips a
  /// frame — the rest of the form is usable immediately.
  List<Bag> _bags = const [];

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _category = widget.existing?.category ??
        widget.initialCategory ??
        ItemCategory.other;
    _quantity = widget.existing?.quantity ?? 1;
    _bagId = widget.existing?.bagId ?? widget.initialBagId;
    _loadBags();
  }

  Future<void> _loadBags() async {
    final bags = await _db.getBagsForTrip(widget.tripId);
    if (mounted) setState(() => _bags = bags);
  }

  /// Names a bag from inside the form, without losing what has been typed.
  Future<Bag?> _createBag() async {
    final name = await promptForText(
      context,
      title: 'New bag',
      message: 'Name a bag you are packing into, so you know what is where.',
      label: 'Bag name',
      hintText: 'e.g. Cabin bag, Rucksack',
      actionLabel: 'Add bag',
    );
    if (name == null) return null;
    final bag = await _db.createBag(Bag(tripId: widget.tripId, name: name));
    if (mounted) setState(() => _bags = [..._bags, bag]);
    return bag;
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
      category: _category,
      quantity: _quantity,
      packed: widget.existing?.packed ?? false,
      bagId: _bagId,
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
      accent: _category.color,
      title: widget.isEditing ? 'Edit item' : 'Add item',
      subtitle: 'Something to pack for this trip',
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
          bags: _bags,
          bagId: _bagId,
          onCategoryChanged: (value) => setState(() => _category = value),
          onQuantityChanged: (value) => setState(() => _quantity = value),
          onBagChanged: (value) => setState(() => _bagId = value),
          onCreateBag: _createBag,
          onSubmitted: _save,
        ),
        const FormHint(
          'Every item travels with you for the whole trip, so it counts at '
          'each hotel — a checkout reminder always covers the full list.',
        ),
      ],
    );
  }
}
