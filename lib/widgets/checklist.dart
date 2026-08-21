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

    // Saving the same name again should replace that list, not pile up an
    // identical copy each time. Match on the trimmed name, case-insensitively.
    final target = name.trim().toLowerCase();
    final existing = (await _db.getPackingLists())
        .where((l) => l.name.trim().toLowerCase() == target)
        .toList();
    if (existing.isNotEmpty) {
      if (!mounted) return;
      final replace = await confirmDestructive(
        context,
        title: 'Replace saved list?',
        message:
            'A saved list called "$name" already exists. Replacing it updates '
            'it to these ${items.length} items.',
        confirmLabel: 'Replace',
      );
      if (!replace) return;
      for (final list in existing) {
        await _db.deletePackingList(list.id!);
      }
    }

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
            _ListHeader(
              groupBy: _groupBy,
              allPacked: allPacked,
              onGroupByChanged: (value) => setState(() => _groupBy = value),
              onPackAll: () => _setAllPacked(!allPacked),
              onSaveAsList: () => _saveAsList(items),
              onUseSavedList: _useSavedList,
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
              const SizedBox(height: AppSpacing.md),
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
  final VoidCallback onSaveAsList;
  final VoidCallback onUseSavedList;

  const _ListHeader({
    required this.groupBy,
    required this.allPacked,
    required this.onGroupByChanged,
    required this.onPackAll,
    required this.onSaveAsList,
    required this.onUseSavedList,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // A hugging pill, not a stretched one: the design sizes it to its two
        // segments and lets the pack action take the rest of the row.
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in _GroupBy.values)
                _GroupByOption(
                  option: option,
                  selected: option == groupBy,
                  onTap: () => onGroupByChanged(option),
                ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: onPackAll,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    allPacked
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                    size: 15,
                    color: allPacked ? AppColors.textMuted : AppColors.mint,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      allPacked ? 'Unpack all' : 'Pack all',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: allPacked ? AppColors.textMuted : AppColors.mint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Save-as-list and use-a-saved-list fold into one overflow, as in the
        // design — the two actions the packing list has beyond the items.
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz_rounded,
              size: 19, color: AppColors.textMuted),
          tooltip: 'List actions',
          padding: const EdgeInsets.only(left: 2),
          iconSize: 19,
          splashRadius: 18,
          onSelected: (value) {
            if (value == 'save') onSaveAsList();
            if (value == 'use') onUseSavedList();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'save',
              height: 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_add_outlined,
                      size: 18, color: AppColors.textMuted),
                  SizedBox(width: 10),
                  Flexible(
                      child: Text('Save as list',
                          maxLines: 1, overflow: TextOverflow.clip)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'use',
              height: 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.library_add_outlined,
                      size: 18, color: AppColors.textMuted),
                  SizedBox(width: 10),
                  Flexible(
                      child: Text('Use a saved list',
                          maxLines: 1, overflow: TextOverflow.clip)),
                ],
              ),
            ),
          ],
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? AppGradients.onFilled : AppColors.textMuted,
              ),
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
    final theme = Theme.of(context);
    final pct = total == 0 ? 0 : ((packed / total) * 100).round();

    // A slim inline row, not a card: a title, the percentage, and a thin bar.
    // The one functional accent is the primary blue, matching the tab and the
    // add button; colour otherwise stays in the category dots below.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$packed of $total packed',
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
            ),
            const Spacer(),
            Text(
              '$pct%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppProgressBar(
          value: total == 0 ? 0 : packed / total,
          color: AppColors.primary,
        ),
      ],
    );
  }
}


/// One section: an uppercase header with a pack toggle, then the items.
class _GroupSection extends StatelessWidget {
  final _Group group;
  final List<Bag> bags;
  final bool showBagOnRows;
  final Future<void> Function(Item item, bool packed) onToggle;
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
    final hasItems = items.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 6),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  // Categories read as section labels, so they are upper-cased
                  // as in the design; a user's bag name keeps its own casing.
                  group.isBagGroup ? group.label : group.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${group.packedCount}/${items.length}',
                style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
              ),
              // The pack toggle sits right beside the count, not adrift at the
              // far edge of the row.
              if (hasItems) ...[
                const SizedBox(width: 2),
                Tooltip(
                  message: group.allPacked ? 'Unpack group' : 'Pack group',
                  child: InkResponse(
                    onTap: () => onPackAll(!group.allPacked),
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        group.allPacked
                            ? Icons.remove_done_rounded
                            : Icons.done_all_rounded,
                        size: 16,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
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
        if (!hasItems)
          _EmptyBagCard(accent: accent)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _ItemRow(
                      item: items[i],
                      bags: bags,
                      showBag: showBagOnRows,
                      onToggle: (value) => onToggle(items[i], value),
                      onEdit: () => onEdit(items[i]),
                      onDelete: () => onDelete(items[i]),
                      onMoveToBag: () => onMoveToBag(items[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A group that has been named but not filled (only bags can be empty).
class _EmptyBagCard extends StatelessWidget {
  final Color accent;

  const _EmptyBagCard({required this.accent});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline_rounded,
                size: 18, color: accent.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nothing in here yet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Item item;
  final List<Bag> bags;
  final bool showBag;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveToBag;

  const _ItemRow({
    required this.item,
    required this.bags,
    required this.showBag,
    required this.onToggle,
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
    // In category mode the tag names the bag (when there is one); in bag mode
    // the section is the bag, so the tag names the category instead.
    final String? tag =
        showBag ? _bag?.name : item.category.label;

    return InkWell(
      onTap: () => onToggle(!item.packed),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Row(
          children: [
            _PackCheck(
              packed: item.packed,
              onTap: () => onToggle(!item.packed),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color:
                            item.packed ? AppColors.textFaint : AppColors.text,
                        decoration: item.packed
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: AppColors.textFaint,
                      ),
                      child: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (tag != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (item.quantity > 1) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '\u00d7${item.quantity}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
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

/// The round packing checkbox: a filled disc with a dark tick when packed, a
/// hollow ring when not. Its own widget so a test can find and tap it.
class PackCheck extends StatelessWidget {
  final bool packed;
  final VoidCallback onTap;

  const PackCheck({super.key, required this.packed, required this.onTap});

  @override
  Widget build(BuildContext context) => _PackCheck(packed: packed, onTap: onTap);
}

class _PackCheck extends StatelessWidget {
  final bool packed;
  final VoidCallback onTap;

  const _PackCheck({required this.packed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: packed,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: packed ? AppColors.primary : Colors.transparent,
            border: Border.all(
              color: packed ? AppColors.primary : AppColors.borderStrong,
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.check_rounded,
            size: 14,
            color: packed ? AppGradients.onFilled : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
