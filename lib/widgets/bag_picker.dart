import 'package:flutter/material.dart';

import '../models/bag.dart';
import '../theme/app_theme.dart';
import '../theme/bag_style.dart';
import 'ui.dart';

/// Which bag was chosen. A null [bagId] is a real answer — "no bag" — which is
/// why the sheet returns this rather than a bare nullable id that could not be
/// told apart from a dismissal.
class BagChoice {
  final int? bagId;

  const BagChoice(this.bagId);
}

/// Asks which bag something goes in.
///
/// Returns null if dismissed without choosing. [onCreateBag] lets a bag be
/// named without leaving the sheet, because the moment you discover you need
/// one is the moment you are assigning it.
Future<BagChoice?> pickBag(
  BuildContext context, {
  required List<Bag> bags,
  required int? selectedBagId,
  required Future<Bag?> Function() onCreateBag,
}) {
  return showModalBottomSheet<BagChoice>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (sheetContext) => _BagPickerSheet(
      bags: bags,
      selectedBagId: selectedBagId,
      onCreateBag: onCreateBag,
    ),
  );
}

class _BagPickerSheet extends StatelessWidget {
  final List<Bag> bags;
  final int? selectedBagId;
  final Future<Bag?> Function() onCreateBag;

  const _BagPickerSheet({
    required this.bags,
    required this.selectedBagId,
    required this.onCreateBag,
  });

  Future<void> _create(BuildContext context) async {
    final navigator = Navigator.of(context);
    final bag = await onCreateBag();
    if (bag == null) return;
    // Straight back out with the new bag selected: naming one is only ever a
    // step towards putting something in it.
    navigator.pop(BagChoice(bag.id));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which bag?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final bag in bags)
                      _BagOption(
                        label: bag.name,
                        color: bagColor(bag.id),
                        icon: bagIcon,
                        selected: bag.id == selectedBagId,
                        onTap: () =>
                            Navigator.of(context).pop(BagChoice(bag.id)),
                      ),
                    _BagOption(
                      label: unassignedBagLabel,
                      color: bagColor(null),
                      icon: Icons.inventory_2_outlined,
                      selected: selectedBagId == null,
                      onTap: () =>
                          Navigator.of(context).pop(const BagChoice(null)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: 'New bag',
              icon: Icons.add_rounded,
              onPressed: () => _create(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _BagOption extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _BagOption({
    required this.label,
    required this.color,
    required this.icon,
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
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                AppIconTile(icon: icon, color: color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 20, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small label showing which bag an item is in, for lists that are not
/// already grouped by bag.
class BagTag extends StatelessWidget {
  final String name;
  final Color color;

  const BagTag({super.key, required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(bagIcon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
