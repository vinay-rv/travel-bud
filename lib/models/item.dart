import 'item_category.dart';

/// Distinguishes "not passed" from an explicit null in [Item.copyWith].
const Object _unset = Object();

/// A belonging to track. Items always belong to the whole trip: there are no
/// hotel-specific items, so every item counts for every stay (a checkout
/// reminder at any hotel considers the trip's full packing list).
///
/// [quantity] is how many to bring (always at least 1). Packing stays a single
/// flag for the whole line — you either have all 3 t-shirts in the bag or you
/// don't.
///
/// [bagId] is which bag it travels in, or null for "not in a bag yet". One bag
/// per item for the same reason packing is one flag: the line is the unit.
class Item {
  final int? id;
  final int tripId;
  final String name;
  final ItemCategory category;
  final int quantity;
  final bool packed;

  /// The [Bag] this travels in, or null when it has not been assigned one.
  final int? bagId;

  const Item({
    this.id,
    required this.tripId,
    required this.name,
    this.category = ItemCategory.other,
    this.quantity = 1,
    this.packed = false,
    this.bagId,
  });

  Item copyWith({
    int? id,
    int? tripId,
    String? name,
    ItemCategory? category,
    int? quantity,
    bool? packed,
    // Nullable in its own right, so a sentinel is the only way to say "take it
    // out of its bag" as distinct from "leave the bag alone".
    Object? bagId = _unset,
  }) {
    return Item(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      packed: packed ?? this.packed,
      bagId: bagId == _unset ? this.bagId : bagId as int?,
    );
  }

  /// e.g. "T-shirts ×3", or just "Passport" for a single.
  String get displayName => quantity > 1 ? '$name ×$quantity' : name;

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'name': name,
      'category': category.name,
      'quantity': quantity,
      'packed': packed ? 1 : 0,
      'bagId': bagId,
    };
  }

  factory Item.fromMap(Map<String, Object?> map) {
    return Item(
      id: map['id'] as int?,
      tripId: map['tripId'] as int,
      name: map['name'] as String,
      category: ItemCategory.fromStorage(map['category'] as String?),
      // Rows written before quantities existed default to one.
      quantity: (map['quantity'] as int?) ?? 1,
      packed: (map['packed'] as int) == 1,
      bagId: map['bagId'] as int?,
    );
  }

  @override
  String toString() =>
      'Item(id: $id, tripId: $tripId, name: $name, '
      'category: ${category.name}, quantity: $quantity, packed: $packed, '
      'bagId: $bagId)';
}
