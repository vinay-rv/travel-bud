import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/packing_list.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/ui.dart';
import 'saved_list_detail_screen.dart';

/// Browse the packing lists saved from earlier trips.
///
/// When [applyToTripId] is set the screen is in "pick one" mode: tapping a
/// list copies it onto that trip and pops with the number of items added.
/// Without it, the screen is just a manager for reviewing and deleting lists.
class SavedListsScreen extends StatefulWidget {
  final int? applyToTripId;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const SavedListsScreen({super.key, this.applyToTripId, this.db});

  @override
  State<SavedListsScreen> createState() => _SavedListsScreenState();
}

class _SavedListsScreenState extends State<SavedListsScreen> {
  late Future<List<PackingList>> _future;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  bool get _picking => widget.applyToTripId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _db.getPackingLists();
  }

  Future<void> _apply(PackingList list) async {
    final added = await _db.applyPackingListToTrip(
      list.id!,
      widget.applyToTripId!,
    );
    if (mounted) Navigator.of(context).pop(added);
  }

  Future<void> _confirmDelete(PackingList list) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete saved list?',
      message:
          'Remove "${list.name}" from your saved lists. Trips you already '
          'built from it keep their items.',
    );
    if (!confirmed) return;
    await _db.deletePackingList(list.id!);
    setState(_load);
  }

  Future<void> _open(PackingList list) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedListDetailScreen(list: list, db: _db),
      ),
    );
    // Item counts and the name may have changed while we were away.
    setState(_load);
  }

  /// Starts an empty list so one can be built up item by item, without
  /// needing a trip to capture it from.
  Future<void> _createList() async {
    final name = await promptForText(
      context,
      title: 'New saved list',
      message: 'Name the list, then add the items that belong on it.',
      label: 'List name',
      actionLabel: 'Create list',
    );
    if (name == null) return;
    final list = await _db.createPackingList(name);
    if (!mounted) return;
    await _open(list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      floatingActionButton: AppFab(
        heroTag: 'new-saved-list',
        onPressed: _createList,
        icon: Icons.add_rounded,
        label: 'New list',
      ),
      body: AppBackground(
        glow: AppColors.violet,
        child: SafeArea(
          child: Column(
            children: [
              _Header(picking: _picking),
              Expanded(
                child: FutureBuilder<List<PackingList>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return AppErrorState(message: '${snapshot.error}');
                    }

                    final lists = snapshot.data ?? const <PackingList>[];
                    if (lists.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.bookmarks_outlined,
                        title: 'No saved lists',
                        message:
                            'Build one here with “New list”, or save a trip\'s '
                            'packing list from its Items tab.',
                        accent: AppColors.violet,
                        action: AppSecondaryButton(
                          label: 'New list',
                          icon: Icons.add_rounded,
                          accent: AppColors.violet,
                          onPressed: _createList,
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter,
                        AppSpacing.sm,
                        AppSpacing.gutter,
                        110,
                      ),
                      itemCount: lists.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final list = lists[index];
                        return _SavedListCard(
                          list: list,
                          picking: _picking,
                          onTap: () => _picking ? _apply(list) : _open(list),
                          onOpen: () => _open(list),
                          onDelete: () => _confirmDelete(list),
                        );
                      },
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
  final bool picking;

  const _Header({required this.picking});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.gutter,
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
                Text('Saved lists', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(
                  picking
                      ? 'Pick one to add to this trip'
                      : 'Reusable lists from earlier trips',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const AppIconTile(
            icon: Icons.bookmarks_rounded,
            color: AppColors.violet,
          ),
        ],
      ),
    );
  }
}

class _SavedListCard extends StatelessWidget {
  final PackingList list;
  final bool picking;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _SavedListCard({
    required this.list,
    required this.picking,
    required this.onTap,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          const AppIconTile(
            icon: Icons.checklist_rtl_rounded,
            color: AppColors.violet,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${list.itemCount} item${list.itemCount == 1 ? '' : 's'} · '
                  'saved ${formatDate(list.createdAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (picking)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: Icon(
                Icons.add_circle_outline_rounded,
                size: 20,
                color: AppColors.violet,
              ),
            ),
          AppRowMenu(
            onEdit: onOpen,
            onDelete: onDelete,
            editLabel: picking ? 'Open' : 'Edit',
          ),
        ],
      ),
    );
  }
}
