import 'package:flutter/material.dart';

import '../models/item_category.dart';
import 'app_theme.dart';

/// How each category looks. Kept out of the model so the data layer stays free
/// of Flutter, and in one place so the icon and colour agree everywhere a
/// category is drawn.
extension ItemCategoryStyle on ItemCategory {
  IconData get icon => switch (this) {
    ItemCategory.documents => Icons.description_rounded,
    ItemCategory.clothes => Icons.checkroom_rounded,
    ItemCategory.hygiene => Icons.soap_rounded,
    ItemCategory.electronics => Icons.cable_rounded,
    ItemCategory.health => Icons.medical_services_rounded,
    ItemCategory.other => Icons.inventory_2_rounded,
  };

  Color get color => switch (this) {
    ItemCategory.documents => AppColors.primary,
    ItemCategory.clothes => AppColors.mint,
    ItemCategory.hygiene => AppColors.violet,
    ItemCategory.electronics => AppColors.amber,
    ItemCategory.health => AppColors.rose,
    ItemCategory.other => AppColors.steel,
  };
}
