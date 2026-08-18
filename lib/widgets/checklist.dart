import 'dart:async';

import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/item.dart';
import '../models/item_category.dart';
import '../screens/item_edit_screen.dart';
import '../screens/saved_lists_screen.dart';
import '../services/reminder_scheduler.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';
import 'ui.dart';

/// The trip's packing list, grouped by category. Items are never
/// hotel-specific — the whole list applies at every stay.
///
/// Embeddable (used as the Items tab) and reused by a standalone checklist
/// screen opened from notifications. Exposes a [reload] method via
/// [ChecklistViewState] so a parent can refresh after adding an item.
class ChecklistView extends StatefulWidget {
  final int tripId;

  /// Shown when saving the list, as the suggested name.
  final String? tripName;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const ChecklistView({
    super.key,
    required this.tripId,
    this.tripName,
    this.db,
  });

  @override
  State<ChecklistView> createState() => ChecklistViewState();
}

/// One category's items, in display order.
class _Group {
  final ItemCategory category;
  final List<Item> items;

  const _Group(this.category, this.items);

  int get packedCount => items.where((i) => i.packed).length;
  bool get allPacked => packedCount == items.length;
}

class ChecklistViewState extends State<ChecklistView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Item>> _future;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _db.getItemsForTrip(widget.tripId);
  }

  /// Public so a parent (e.g. the trip detail FAB) can refresh after adding.
  ///
  /// Checkout reminders name the items still unpacked, so every item change
  /// has to rebuild them.
  void reload() {
    setState(_load);
    unawaited(Reminders.instance.syncTrip(_db, widget.tripId));
  }

  /// Groups items by category, keeping the enum's order and dropping
  /// categories with nothing in them.
  List<_Group> _group(List<Item> items) {
    return [
      for (final category in ItemCategory.values)
        if (items.any((i) => i.category == category))
          _Group(category, items.where((i) => i.category == category).toList()),
    ];
  }

  Future<void> _toggle(Item item, bool packed) async {
    await _db.setItemPacked(item.id!, packed);
    reload();
  }

  Future<void> _setQuantity(Item item, int quantity) async {
    await _db.setItemQuantity(item.id!, quantity);
    reload();
  }

  Future<void> _setAllPacked(bool packed, {ItemCategory? category}) async {
    await _db.setAllItemsPacked(widget.tripId, packed, category: category);
    reload();
  }

  Future<void> _edit(Item item) async {
    final updated = await Navigator.of(context).push<Item>(
      MaterialPageRoute(
        builder: (_) => ItemEditScreen(
          tripId: widget.tripId,
          existing: item,
          db: widget.db,
        ),
      ),
    );
    if (updated != null) reload();
  }

  Future<void> _confirmDelete(Item item) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete item?',
      message: 'Remove "${item.name}" from this trip?',
    );
    if (!confirmed) return;
    await _db.deleteItem(item.id!);
    reload();
  }

  /// Stores the current items as a reusable list under a name the user picks.
  Future<void> _saveAsList(List<Item> items) async {
    final name = await promptForText(
      context,
      title: 'Save this list',
      message:
          'Save these ${items.length} items so you can reuse them on your '
          'next trip. Packed ticks are not saved.',
      label: 'List name',
      initialValue: widget.tripName ?? '',
      actionLabel: 'Save list',
    );
    if (name == null) return;

    await _db.savePackingList(name, items);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "$name" for future trips.')),
    );
  }

  /// Opens the saved lists so one can be copied onto this trip.
  Future<void> _useSavedList() async {
    final applied = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => SavedListsScreen(applyToTripId: widget.tripId, db: _db),
      ),
    );
    if (applied == null) return;
    reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applied == 0
              ? 'Those items are already on this trip.'
              : 'Added $applied item${applied == 1 ? '' : 's'}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Item>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppErrorState(message: '${snapshot.error}');
        }

        final items = snapshot.data ?? const <Item>[];
        if (items.isEmpty) {
          return AppEmptyState(
            icon: Icons.checklist_rounded,
            title: 'No items yet',
            message:
                'Tap “Add Item” to start your packing list, or bring in a list '
                'you saved on an earlier trip.',
            accent: AppColors.violet,
            action: AppSecondaryButton(
              label: 'Use a saved list',
              icon: Icons.library_add_outlined,
              accent: AppColors.violet,
              onPressed: _useSavedList,
            ),
          );
        }

        final packed = items.where((i) => i.packed).length;
        final groups = _group(items);
        final allPacked = packed == items.length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            110,
          ),
          children: [
            _PackingSummary(packed: packed, total: items.length),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppSecondaryButton(
                    label: 'Save as list',
                    icon: Icons.bookmark_add_outlined,
                    onPressed: () => _saveAsList(items),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppSecondaryButton(
                    label: 'Use a saved list',
                    icon: Icons.library_add_outlined,
                    accent: AppColors.violet,
                    onPressed: _useSavedList,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionLabel(
              label: 'Packing list',
              trailing: AppTextAction(
                label: allPacked ? 'Unpack all' : 'Pack all',
                icon: allPacked
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded,
                color: allPacked ? AppColors.textMuted : AppColors.mint,
                onPressed: () => _setAllPacked(!allPacked),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final group in groups) ...[
              _CategorySection(
                group: group,
                onToggle: _toggle,
                onQuantity: _setQuantity,
                onEdit: _edit,
                onDelete: _confirmDelete,
                onPackAll: (packed) =>
                    _setAllPacked(packed, category: group.category),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        );
      },
    );
  }
}

/// Overall packing progress for the trip.
class _PackingSummary extends StatelessWidget {
  final int packed;
  final int total;

  const _PackingSummary({required this.packed, required this.total});

  @override
  Widget build(BuildContext context) {
    final done = packed == total;
    final color = done ? AppColors.mint : AppColors.violet;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: done ? Icons.task_alt_rounded : Icons.backpack_rounded,
                color: color,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? 'All packed' : 'Packing progress',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$packed of $total items ready',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                '${total == 0 ? 0 : ((packed / total) * 100).round()}%',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppProgressBar(
            value: total == 0 ? 0 : packed / total,
            color: color,
          ),
        ],
      ),
    );
  }
}

/// One category: a header with its own pack/unpack action, then its items.
class _CategorySection extends StatelessWidget {
  final _Group group;
  final Future<void> Function(Item item, bool packed) onToggle;
  final Future<void> Function(Item item, int quantity) onQuantity;
  final Future<void> Function(Item item) onEdit;
  final Future<void> Function(Item item) onDelete;
  final ValueChanged<bool> onPackAll;

  const _CategorySection({
    required this.group,
    required this.onToggle,
    required this.onQuantity,
    required this.onEdit,
    required this.onDelete,
    required this.onPackAll,
  });

  @override
  Widget build(BuildContext context) {
    final accent = group.category.color;
    final items = group.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(group.category.icon, size: 16, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  group.category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${group.packedCount}/${items.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: group.allPacked ? AppColors.mint : AppColors.textFaint,
                ),
              ),
              const Spacer(),
              AppTextAction(
                label: group.allPacked ? 'Unpack all' : 'Pack all',
                icon: group.allPacked
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded,
                color: group.allPacked ? AppColors.textMuted : accent,
                onPressed: () => onPackAll(!group.allPacked),
              ),
            ],
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Divider(indent: 52, endIndent: AppSpacing.sm),
                _ItemRow(
                  item: items[i],
                  accent: accent,
                  onToggle: (value) => onToggle(items[i], value),
                  onQuantity: (value) => onQuantity(items[i], value),
                  onEdit: () => onEdit(items[i]),
                  onDelete: () => onDelete(items[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Item item;
  final Color accent;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onQuantity;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemRow({
    required this.item,
    required this.accent,
    required this.onToggle,
    required this.onQuantity,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(!item.packed),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Checkbox(
              value: item.packed,
              onChanged: (value) => onToggle(value ?? false),
            ),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: item.packed ? AppColors.textFaint : AppColors.text,
                  decoration: item.packed
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: AppColors.textFaint,
                ),
                child: Text(item.name, maxLines: 2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppQuantityStepper(
              quantity: item.quantity,
              accent: accent,
              onChanged: onQuantity,
            ),
            AppRowMenu(onEdit: onEdit, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}
