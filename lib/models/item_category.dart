/// The buckets a packing item can belong to. Fixed set — [other] also catches
/// anything created before categories existed.
///
/// The enum's `name` is what gets stored, so these identifiers are part of the
/// database format: rename one and old rows stop resolving.
enum ItemCategory {
  documents('Documents'),
  clothes('Clothes'),
  hygiene('Hygiene'),
  electronics('Electronics'),
  health('Health'),
  other('Other');

  final String label;

  const ItemCategory(this.label);

  /// Resolves a stored value, falling back to [other] for anything unknown.
  static ItemCategory fromStorage(String? value) {
    return ItemCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => ItemCategory.other,
    );
  }
}
