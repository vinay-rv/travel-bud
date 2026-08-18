import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/item_category.dart';
import '../models/packing_list.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';
import '../widgets/ui.dart';
import 'packing_entry_edit_screen.dart';

/// One saved list, with its items grouped by category. Items can be added,
/// edited, re-counted, and removed here, so a list can be curated directly
/// rather than only captured from a trip.
class SavedListDetailScreen extends StatefulWidget {
  final PackingList list;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const SavedListDetailScreen({super.key, required this.list, this.db});

  @override
  State<SavedListDetailScreen> createState() => _SavedListDetailScreenState();
}

class _SavedListDetailScreenState extends State<SavedListDetailScreen> {
  late Future<List<PackingListEntry>> _future;
  late String _name;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;
  int get _listId => widget.list.id!;

  @override
  void initState() {
    super.initState();
    _name = widget.list.name;
    _load();
  }

  void _load() {
    _future = _db.getPackingListEntries(_listId);
  }

  Future<void> _add() async {
    final created = await Navigator.of(context).push<PackingListEntry>(
      MaterialPageRoute(
        builder: (_) => PackingEntryEditScreen(listId: _listId, db: widget.db),
      ),
    );
    if (created != null) setState(_load);
  }

  Future<void> _edit(PackingListEntry entry) async {
    final updated = await Navigator.of(context).push<PackingListEntry>(
      MaterialPageRoute(
        builder: (_) => PackingEntryEditScreen(
          listId: _listId,
          existing: entry,
          db: widget.db,
        ),
      ),
    );
    if (updated != null) setState(_load);
  }

  Future<void> _setQuantity(PackingListEntry entry, int quantity) async {
    await _db.setPackingListEntryQuantity(entry.id!, quantity);
    setState(_load);
  }

  Future<void> _confirmDelete(PackingListEntry entry) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove item?',
      message: 'Take "${entry.name}" out of "$_name".',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await _db.deletePackingListEntry(entry.id!);
    setState(_load);
  }

  Future<void> _rename() async {
    final name = await promptForText(
      context,
      title: 'Rename list',
      message: 'What should this list be called?',
      label: 'List name',
      initialValue: _name,
      actionLabel: 'Rename',
    );
    if (name == null) return;
    await _db.renamePackingList(_listId, name);
    if (mounted) setState(() => _name = name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      floatingActionButton: AppFab(
        heroTag: 'add-list-item',
        onPressed: _add,
        icon: Icons.add_rounded,
        label: 'Add Item',
      ),
      body: AppBackground(
        glow: AppColors.violet,
        child: SafeArea(
          child: Column(
            children: [
              _Header(name: _name, onRename: _rename),
              Expanded(
                child: FutureBuilder<List<PackingListEntry>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return AppErrorState(message: '${snapshot.error}');
                    }

                    final entries =
                        snapshot.data ?? const <PackingListEntry>[];
                    if (entries.isEmpty) {
                      return const AppEmptyState(
                        icon: Icons.playlist_add_rounded,
                        title: 'Nothing in this list',
                        message:
                            'Tap “Add Item” to build it up. Anything you add '
                            'here comes along whenever you use this list.',
                        accent: AppColors.violet,
                      );
                    }

                    final categories = [
                      for (final category in ItemCategory.values)
                        if (entries.any((e) => e.category == category)) category,
                    ];

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter,
                        AppSpacing.sm,
                        AppSpacing.gutter,
                        110,
                      ),
                      children: [
                        for (final category in categories) ...[
                          _CategoryBlock(
                            category: category,
                            entries: entries
                                .where((e) => e.category == category)
                                .toList(),
                            onEdit: _edit,
                            onQuantity: _setQuantity,
                            onDelete: _confirmDelete,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final VoidCallback onRename;

  const _Header({required this.name, required this.onRename});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textMuted,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 2),
                Text('Saved list', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline_rounded),
            color: AppColors.textMuted,
            tooltip: 'Rename list',
            onPressed: onRename,
          ),
        ],
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  final ItemCategory category;
  final List<PackingListEntry> entries;
  final Future<void> Function(PackingListEntry entry) onEdit;
  final Future<void> Function(PackingListEntry entry, int quantity) onQuantity;
  final Future<void> Function(PackingListEntry entry) onDelete;

  const _CategoryBlock({
    required this.category,
    required this.entries,
    required this.onEdit,
    required this.onQuantity,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = category.color;

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
              Icon(category.icon, size: 16, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${entries.length}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textFaint,
                ),
              ),
            ],
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  const Divider(indent: 20, endIndent: AppSpacing.sm),
                _EntryRow(
                  entry: entries[i],
                  accent: accent,
                  onTap: () => onEdit(entries[i]),
                  onQuantity: (value) => onQuantity(entries[i], value),
                  onDelete: () => onDelete(entries[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  final PackingListEntry entry;
  final Color accent;
  final VoidCallback onTap;
  final ValueChanged<int> onQuantity;
  final VoidCallback onDelete;

  const _EntryRow({
    required this.entry,
    required this.accent,
    required this.onTap,
    required this.onQuantity,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppQuantityStepper(
              quantity: entry.quantity,
              accent: accent,
              onChanged: onQuantity,
            ),
            AppRowMenu(onEdit: onTap, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}
