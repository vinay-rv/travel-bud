import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../models/expense.dart';
import '../screens/expense_edit_screen.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'ui.dart';

/// What a trip has cost, newest first.
///
/// Every row carries its date and time, because "when did I pay for that?" is
/// the question this list exists to answer.
class ExpensesTab extends StatefulWidget {
  final int tripId;

  /// Injectable for tests; defaults to the app-wide singleton.
  final DatabaseHelper? db;

  const ExpensesTab({super.key, required this.tripId, this.db});

  @override
  State<ExpensesTab> createState() => ExpensesTabState();
}

class ExpensesTabState extends State<ExpensesTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Expense>> _future;

  DatabaseHelper get _db => widget.db ?? DatabaseHelper.instance;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _db.getExpensesForTrip(widget.tripId);
  }

  /// Public so the parent's FAB can refresh after adding.
  void reload() => setState(_load);

  Future<void> _edit(Expense expense) async {
    final updated = await Navigator.of(context).push<Expense>(
      MaterialPageRoute(
        builder: (_) => ExpenseEditScreen(
          tripId: widget.tripId,
          existing: expense,
          db: widget.db,
        ),
      ),
    );
    if (updated != null) reload();
  }

  Future<void> _confirmDelete(Expense expense) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete expense?',
      message: 'Remove "${expense.name}" from this trip.',
    );
    if (!confirmed) return;
    await _db.deleteExpense(expense.id!);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Expense>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppErrorState(message: '${snapshot.error}');
        }

        final expenses = snapshot.data ?? const <Expense>[];
        if (expenses.isEmpty) {
          return const AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Nothing spent yet',
            message:
                'Tap “Add Expense” to note what a trip is costing, as you go.',
            accent: AppColors.amber,
          );
        }

        final total = expenses.fold<int>(0, (sum, e) => sum + e.amountMinor);

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            _TotalCard(total: total, count: expenses.length),
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel(label: 'Recent first'),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < expenses.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        indent: AppSpacing.lg,
                        endIndent: AppSpacing.sm,
                      ),
                    _ExpenseRow(
                      expense: expenses[i],
                      onTap: () => _edit(expenses[i]),
                      onDelete: () => _confirmDelete(expenses[i]),
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

class _TotalCard extends StatelessWidget {
  final int total;
  final int count;

  const _TotalCard({required this.total, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // No icon tile, no coloured amount: a label, the big plain total, and the
    // count. The money is the loudest thing on the card by size, not by hue.
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENT ON THIS TRIP',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  formatMinor(total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '$count expense${count == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExpenseRow({
    required this.expense,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Date *and* time: knowing it was Tuesday afternoon is what
                  // makes a line on the list recognisable later.
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppColors.textFaint,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          formatDateTime(expense.spentAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              expense.amountLabel,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            AppRowMenu(onEdit: onTap, onDelete: onDelete),
          ],
        ),
      ),
    );
  }
}
