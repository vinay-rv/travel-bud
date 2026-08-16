import 'dart:async';

import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/item.dart';
import '../screens/item_edit_screen.dart';
import '../services/reminder_scheduler.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// The trip's packing list: one flat list of items, each a checkbox that
/// toggles its packed state. Items are never hotel-specific — the whole list
/// applies at every stay — so there is no grouping here.
///
/// Embeddable (used as the Items tab) and reused by a standalone checklist
/// screen opened from notifications in a later step. Exposes a [reload] method
/// via [ChecklistViewState] so a parent can refresh after adding an item.
class ChecklistView extends StatefulWidget {
  final int tripId;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const ChecklistView({super.key, required this.tripId, this.db});

  @override
  State<ChecklistView> createState() => ChecklistViewState();
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

  Future<void> _toggle(Item item, bool packed) async {
    await _db.setItemPacked(item.id!, packed);
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
          return const AppEmptyState(
            icon: Icons.checklist_rounded,
            title: 'No items yet',
            message:
                'Tap “Add Item” to start your packing list. Every item counts '
                'for the whole trip, at every hotel.',
            accent: AppColors.violet,
          );
        }

        final packed = items.where((i) => i.packed).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            110,
          ),
          children: [
            _PackingSummary(packed: packed, total: items.length),
            const SizedBox(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: SectionLabel(
                label: 'Packing list',
                trailing: AppPill(
                  label: packed == items.length
                      ? 'All packed'
                      : '${items.length - packed} left',
                  color: packed == items.length
                      ? AppColors.mint
                      : AppColors.textMuted,
                ),
              ),
            ),
            AppCard(
              padding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      const Divider(indent: 56, endIndent: AppSpacing.sm),
                    _ItemRow(
                      item: items[i],
                      onToggle: (value) => _toggle(items[i], value),
                      onEdit: () => _edit(items[i]),
                      onDelete: () => _confirmDelete(items[i]),
                    ),
                  ],
                ],
              ),
            ),
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

class _ItemRow extends StatelessWidget {
  final Item item;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemRow({
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(!item.packed),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
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
            const SizedBox(width: AppSpacing.sm),
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
                child: Text(item.name),
              ),
            ),
            AppRowMenu(onEdit: onEdit, onDelete: onDelete),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}
