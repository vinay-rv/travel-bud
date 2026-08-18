import 'package:flutter/material.dart';

import '../models/item_category.dart';
import '../theme/app_theme.dart';
import '../theme/category_style.dart';
import 'ui.dart';

/// The three fields that describe anything packable — name, category, and how
/// many — shared by the trip item editor and the saved list entry editor so
/// both stay identical.
class ItemFields extends StatelessWidget {
  final TextEditingController nameController;
  final ItemCategory category;
  final int quantity;
  final ValueChanged<ItemCategory> onCategoryChanged;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onSubmitted;
  final bool autofocus;

  const ItemFields({
    super.key,
    required this.nameController,
    required this.category,
    required this.quantity,
    required this.onCategoryChanged,
    required this.onQuantityChanged,
    required this.onSubmitted,
    this.autofocus = false,
  });

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
                  _CategoryChip(
                    category: value,
                    selected: value == category,
                    onTap: () => onCategoryChanged(value),
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

class _CategoryChip extends StatelessWidget {
  final ItemCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = category.color;

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
                  selected ? Icons.check_rounded : category.icon,
                  size: 16,
                  color: selected ? accent : AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? accent : AppColors.textMuted,
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
