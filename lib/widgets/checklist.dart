import 'dart:async';

import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/bag.dart';
import '../models/item.dart';
import '../models/item_category.dart';
import '../screens/item_edit_screen.dart';
import '../screens/saved_lists_screen.dart';
import '../services/reminder_scheduler.dart';
import '../theme/app_theme.dart';
import '../theme/bag_style.dart';
import '../theme/category_style.dart';
import 'bag_picker.dart';
import 'ui.dart';

/// The trip's packing list. Items are never hotel-specific — the whole list
/// applies at every stay.
///
/// The same items can be read two ways, and which one is useful depends on
/// what you are doing: by category while deciding what to bring, by bag while
/// actually filling them. So the grouping is a switch rather than a decision
/// made for the user.
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

/// How the list is broken up.
enum _GroupBy {
  category('Category', Icons.category_rounded),
  bag('Bag', bagIcon);

  final String label;
  final IconData icon;

  const _GroupBy(this.label, this.icon);
}

/// Everything one render of the list needs, fetched together so the bags and
/// the items can never disagree about what exists.
class _Checklist {
  final List<Item> items;
  final List<Bag> bags;

  const _Checklist(this.items, this.bags);
}

/// One section of the list, whichever way it is grouped.
class _Group {
  final String label;
  final IconData icon;
  final Color color;
  final List<Item> items;

  /// Set when grouping by category — what the section's pack-all acts on.
  final ItemCategory? category;

  /// Set when grouping by bag. Null with [isBagGroup] true means the section
  /// holding everything not in a bag, which has no bag to rename or delete.
  final Bag? bag;
  final bool isBagGroup;

  const _Group({
    required this.label,
    required this.icon,
    required this.color,
    required this.items,
    this.category,
    this.bag,
    this.isBagGroup = false,
  });

  int get packedCount => items.where((i) => i.packed).length;
  bool get allPacked => packedCount == items.length;
}

class ChecklistViewState extends State<ChecklistView>
    with AutomaticKeepAliveClientMixin {
  late Future<_Checklist> _future;
  _GroupBy _groupBy = _GroupBy.category;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _fetch();
  }

  Future<_Checklist> _fetch() async {
    final items = await _db.getItemsForTrip(widget.tripId);
    final bags = await _db.getBagsForTrip(widget.tripId);
    return _Checklist(items, bags);
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
  List<_Group> _groupByCategory(List<Item> items) {
    return [
      for (final category in ItemCategory.values)
        if (items.any((i) => i.category == category))
          _Group(
            label: category.label,
            icon: category.icon,
            color: category.color,
            category: category,
            items: items.where((i) => i.category == category).toList(),
          ),
    ];
  }

  /// Groups items by bag, in the order the bags were created, with anything
  /// unassigned gathered at the end.
  ///
  /// Empty bags are kept: a bag you have named but not filled is exactly the
  /// one you still need to think about.
  List<_Group> _groupByBag(_Checklist data) {
    final groups = [
      for (final bag in data.bags)
        _Group(
          label: bag.name,
          icon: bagIcon,
          color: bagColor(bag.id),
          bag: bag,
          isBagGroup: true,
          items: data.items.where((i) => i.bagId == bag.id).toList(),
        ),
    ];

    final loose = data.items.where((i) => i.bagId == null).toList();
    if (loose.isNotEmpty) {
      groups.add(_Group(
        label: unassignedBagLabel,
        icon: Icons.inventory_2_outlined,
        color: bagColor(null),
        isBagGroup: true,
        items: loose,
      ));
    }
    return groups;
  }

  Future<void> _toggle(Item item, bool packed) async {
    await _db.setItemPacked(item.id!, packed);
    reload();
  }

  Future<void> _setQuantity(Item item, int quantity) async {
    await _db.setItemQuantity(item.id!, quantity);
    reload();
  }

  Future<void> _setAllPacked(bool packed) async {
    await _db.setAllItemsPacked(widget.tripId, packed);
    reload();
  }

  Future<void> _setGroupPacked(_Group group, bool packed) async {
    if (group.isBagGroup) {
      await _db.setBagItemsPacked(widget.tripId, packed, bagId: group.bag?.id);
    } else {
      await _db.setAllItemsPacked(
        widget.tripId,
        packed,
        category: group.category,
      );
    }
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

  // ---------------------------------------------------------------------------
  // Bags
  // ---------------------------------------------------------------------------

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
    reload();
    return bag;
  }

  /// Asks which bag an item goes in, then puts it there.
  Future<void> _moveToBag(Item item, List<Bag> bags) async {
    final choice = await pickBag(
      context,
      bags: bags,
      selectedBagId: item.bagId,
      onCreateBag: _createBag,
    );
    if (choice == null) return;
    await _db.setItemBag(item.id!, choice.bagId);
    reload();
  }

  Future<void> _renameBag(Bag bag) async {
    final name = await promptForText(
      context,
      title: 'Rename bag',
      label: 'Bag name',
      initialValue: bag.name,
      actionLabel: 'Save',
    );
    if (name == null) return;
    await _db.renameBag(bag.id!, name);
    reload();
  }

  Future<void> _confirmDeleteBag(Bag bag, int itemCount) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete bag?',
      message: itemCount == 0
          ? 'Remove "${bag.name}" from this trip.'
          : 'Remove "${bag.name}". The $itemCount item'
              '${itemCount == 1 ? '' : 's'} in it stay on your packing list, '
              'just not in a bag.',
    );
    if (!confirmed) return;
    await _db.deleteBag(bag.id!);
    reload();
  }

  /// Stores the current items as a reusable list under a name the user picks.
  Future<void> _saveAsList(List<Item> items) async {
    final name = await promptForText(
      context,
      title: 'Save this list',
      message:
          'Save these ${items.length} items so you can reuse them on your '
          'next trip. Packed ticks and bags are not saved.',
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
    return FutureBuilder<_Checklist>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppErrorState(message: '${snapshot.error}');
        }

        final data = snapshot.data ?? const _Checklist([], []);
        final items = data.items;
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
        final allPacked = packed == items.length;
        final groups = _groupBy == _GroupBy.category
            ? _groupByCategory(items)
            : _groupByBag(data);

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.xl,
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
            _ListHeader(
              groupBy: _groupBy,
              allPacked: allPacked,
              onGroupByChanged: (value) => setState(() => _groupBy = value),
              onPackAll: () => _setAllPacked(!allPacked),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final group in groups) ...[
              _GroupSection(
                group: group,
                bags: data.bags,
                // Grouped by bag the section header already says which one, so
                // repeating it on every row would be noise.
                showBagOnRows: _groupBy == _GroupBy.category,
                onToggle: _toggle,
                onQuantity: _setQuantity,
                onEdit: _edit,
                onDelete: _confirmDelete,
                onMoveToBag: (item) => _moveToBag(item, data.bags),
                onPackAll: (packed) => _setGroupPacked(group, packed),
                onRenameBag: group.bag == null
                    ? null
                    : () => _renameBag(group.bag!),
                onDeleteBag: group.bag == null
                    ? null
                    : () => _confirmDeleteBag(group.bag!, group.items.length),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_groupBy == _GroupBy.bag) _AddBagCard(onTap: _createBag),
          ],
        );
      },
    );
  }
}

/// How the list is grouped, and the whole-trip pack action.
///
/// Deliberately one row rather than a control plus a section label: the
/// grouping already says what the list below is, so a "Packing list" heading
/// on top of it was a line of chrome that pushed the list itself off-screen.
class _ListHeader extends StatelessWidget {
  final _GroupBy groupBy;
  final bool allPacked;
  final ValueChanged<_GroupBy> onGroupByChanged;
  final VoidCallback onPackAll;

  const _ListHeader({
    required this.groupBy,
    required this.allPacked,
    required this.onGroupByChanged,
    required this.onPackAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in _GroupBy.values)
                  Flexible(
                    child: _GroupByOption(
                      option: option,
                      selected: option == groupBy,
                      onTap: () => onGroupByChanged(option),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppTextAction(
          label: allPacked ? 'Unpack all' : 'Pack all',
          icon: allPacked ? Icons.remove_done_rounded : Icons.done_all_rounded,
          color: allPacked ? AppColors.textMuted : AppColors.mint,
          onPressed: onPackAll,
        ),
      ],
    );
  }
}

/// Somewhere to name another bag, at the end of the bags rather than in the
/// header — which is where you look once you have run out of them.
class _AddBagCard extends StatelessWidget {
  final Future<Bag?> Function() onTap;

  const _AddBagCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          const AppIconTile(icon: Icons.add_rounded, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'New bag',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupByOption extends StatelessWidget {
  final _GroupBy option;
  final bool selected;
  final VoidCallback onTap;

  const _GroupByOption({
    required this.option,
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
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.icon,
                  size: 15,
                  color: selected ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.primary : AppColors.textMuted,
                    ),
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

/// One section: a header with its own pack/unpack action, then its items.
class _GroupSection extends StatelessWidget {
  final _Group group;
  final List<Bag> bags;
  final bool showBagOnRows;
  final Future<void> Function(Item item, bool packed) onToggle;
  final Future<void> Function(Item item, int quantity) onQuantity;
  final Future<void> Function(Item item) onEdit;
  final Future<void> Function(Item item) onDelete;
  final Future<void> Function(Item item) onMoveToBag;
  final ValueChanged<bool> onPackAll;

  /// Null unless this section is a bag that can be managed — the catch-all
  /// "no bag" section is not a real bag, so there is nothing to rename.
  final VoidCallback? onRenameBag;
  final VoidCallback? onDeleteBag;

  const _GroupSection({
    required this.group,
    required this.bags,
    required this.showBagOnRows,
    required this.onToggle,
    required this.onQuantity,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveToBag,
    required this.onPackAll,
    this.onRenameBag,
    this.onDeleteBag,
  });

  @override
  Widget build(BuildContext context) {
    final accent = group.color;
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
              Icon(group.icon, size: 16, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  group.label,
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
                  color: group.allPacked && items.isNotEmpty
                      ? AppColors.mint
                      : AppColors.textFaint,
                ),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                AppTextAction(
                  label: group.allPacked ? 'Unpack all' : 'Pack all',
                  icon: group.allPacked
                      ? Icons.remove_done_rounded
                      : Icons.done_all_rounded,
                  color: group.allPacked ? AppColors.textMuted : accent,
                  onPressed: () => onPackAll(!group.allPacked),
                ),
              if (onRenameBag != null && onDeleteBag != null)
                AppRowMenu(
                  editLabel: 'Rename bag',
                  editIcon: Icons.drive_file_rename_outline_rounded,
                  onEdit: onRenameBag!,
                  onDelete: onDeleteBag!,
                ),
            ],
          ),
        ),
        if (items.isEmpty)
          _EmptyBagCard(accent: accent)
        else
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
                    bags: bags,
                    showBag: showBagOnRows,
                    onToggle: (value) => onToggle(items[i], value),
                    onQuantity: (value) => onQuantity(items[i], value),
                    onEdit: () => onEdit(items[i]),
                    onDelete: () => onDelete(items[i]),
                    onMoveToBag: () => onMoveToBag(items[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A bag that has been named but not filled. Shown rather than hidden: it is
/// the one that still needs thinking about.
class _EmptyBagCard extends StatelessWidget {
  final Color accent;

  const _EmptyBagCard({required this.accent});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.add_circle_outline_rounded,
              size: 18, color: accent.withValues(alpha: 0.7)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Nothing in here yet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Item item;
  final Color accent;
  final List<Bag> bags;
  final bool showBag;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onQuantity;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveToBag;

  const _ItemRow({
    required this.item,
    required this.accent,
    required this.bags,
    required this.showBag,
    required this.onToggle,
    required this.onQuantity,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveToBag,
  });

  Bag? get _bag {
    for (final bag in bags) {
      if (bag.id == item.bagId) return bag;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bag = _bag;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
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
                  if (showBag && bag != null) ...[
                    const SizedBox(height: 4),
                    BagTag(name: bag.name, color: bagColor(bag.id)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppQuantityStepper(
              quantity: item.quantity,
              accent: accent,
              onChanged: onQuantity,
            ),
            AppRowMenu(
              onEdit: onEdit,
              onDelete: onDelete,
              extraActions: [
                AppRowMenuAction(
                  label: item.bagId == null ? 'Put in a bag' : 'Move to bag',
                  icon: bagIcon,
                  onSelected: onMoveToBag,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
