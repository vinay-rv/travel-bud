import 'package:flutter/material.dart';

import '../models/bag.dart';
import '../models/item_category.dart';
import '../theme/app_theme.dart';
import '../theme/bag_style.dart';
import '../theme/category_style.dart';
import 'ui.dart';

/// The fields that describe anything packable — name, category, and how many —
/// shared by the trip item editor and the saved list entry editor so both stay
/// identical.
///
/// Bags are the one part that is not shared: they belong to a trip, and a
/// saved list is a template that outlives any particular set of luggage. Pass
/// [bags] to show the section; leave it null and it is absent entirely.
class ItemFields extends StatelessWidget {
  final TextEditingController nameController;
  final ItemCategory category;
  final int quantity;
  final ValueChanged<ItemCategory> onCategoryChanged;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onSubmitted;
  final bool autofocus;

  /// The trip's bags, or null on editors where bags do not apply.
  final List<Bag>? bags;
  final int? bagId;
  final ValueChanged<int?>? onBagChanged;

  /// Names a new bag and returns it, so one can be added without abandoning a
  /// half-filled form.
  final Future<Bag?> Function()? onCreateBag;

  const ItemFields({
    super.key,
    required this.nameController,
    required this.category,
    required this.quantity,
    required this.onCategoryChanged,
    required this.onQuantityChanged,
    required this.onSubmitted,
    this.autofocus = false,
    this.bags,
    this.bagId,
    this.onBagChanged,
    this.onCreateBag,
  });

  Future<void> _createBag() async {
    final bag = await onCreateBag?.call();
    if (bag != null) onBagChanged?.call(bag.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormSection(
          label: 'Item',
          children: [
            TextFormField(
              controller: nameController,
              autofocus: autofocus,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'e.g. Passport, Charger',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an item name';
                }
                return null;
              },
              onFieldSubmitted: (_) => onSubmitted(),
            ),
          ],
        ),
        FormSection(
          label: 'Category',
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final value in ItemCategory.values)
                  _ChoiceChip(
                    label: value.label,
                    icon: value.icon,
                    accent: value.color,
                    selected: value == category,
                    onTap: () => onCategoryChanged(value),
                  ),
              ],
            ),
          ],
        ),
        if (bags != null)
          FormSection(
            label: 'Which bag',
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final bag in bags!)
                    _ChoiceChip(
                      label: bag.name,
                      icon: bagIcon,
                      accent: bagColor(bag.id),
                      selected: bag.id == bagId,
                      onTap: () => onBagChanged?.call(bag.id),
                    ),
                  _ChoiceChip(
                    label: unassignedBagLabel,
                    icon: Icons.inventory_2_outlined,
                    accent: bagColor(null),
                    selected: bagId == null,
                    onTap: () => onBagChanged?.call(null),
                  ),
                  if (onCreateBag != null)
                    _ChoiceChip(
                      label: 'New bag',
                      icon: Icons.add_rounded,
                      accent: AppColors.primary,
                      selected: false,
                      showIconWhenSelected: true,
                      onTap: _createBag,
                    ),
                ],
              ),
            ],
          ),
        FormSection(
          label: 'How many',
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quantity == 1
                        ? 'Bringing one'
                        : 'Bringing $quantity of these',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                AppQuantityStepper(
                  quantity: quantity,
                  accent: category.color,
                  onChanged: onQuantityChanged,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// A selectable pill. Shared by categories and bags so the two rows of chips
/// cannot drift apart.
class _ChoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  /// Selection normally swaps the icon for a tick. Actions that are not a
  /// selection at all — "New bag" — keep their own icon.
  final bool showIconWhenSelected;

  const _ChoiceChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.showIconWhenSelected = false,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.16)
                  : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.5)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected && !showIconWhenSelected ? Icons.check_rounded : icon,
                  size: 16,
                  color: selected ? accent : AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? accent : AppColors.textMuted,
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
