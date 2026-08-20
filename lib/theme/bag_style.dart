import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Colours for bags.
///
/// Bags are named by the user, so unlike categories there is no fixed palette
/// to hand-assign. The colour is derived from the bag's id instead: stable for
/// the life of the bag, and different from its neighbours, which is all the
/// eye needs to tell a cabin bag from a rucksack down a long list.
const _bagPalette = [
  AppColors.primary,
  AppColors.mint,
  AppColors.amber,
  AppColors.violet,
  AppColors.rose,
];

/// The colour for [bagId], or the muted tone that marks "not in a bag yet".
Color bagColor(int? bagId) {
  if (bagId == null) return AppColors.steel;
  return _bagPalette[bagId.abs() % _bagPalette.length];
}

/// Bags all share an icon — the name is what distinguishes them, and a guessed
/// icon per name would be wrong more often than it was right.
const bagIcon = Icons.luggage_rounded;

/// What an item with no bag is called, everywhere it is shown.
const unassignedBagLabel = 'No bag';
