import 'item_category.dart';

/// A belonging to track. Items always belong to the whole trip: there are no
/// hotel-specific items, so every item counts for every stay (a checkout
/// reminder at any hotel considers the trip's full packing list).
///
/// [quantity] is how many to bring (always at least 1). Packing stays a single
/// flag for the whole line — you either have all 3 t-shirts in the bag or you
/// don't.
class Item {
  final int? id;
  final int tripId;
  final String name;
  final ItemCategory category;
  final int quantity;
  final bool packed;

  const Item({
    this.id,
    required this.tripId,
    required this.name,
    this.category = ItemCategory.other,
    this.quantity = 1,
    this.packed = false,
  });

  Item copyWith({
    int? id,
    int? tripId,
    String? name,
    ItemCategory? category,
    int? quantity,
    bool? packed,
  }) {
    return Item(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      packed: packed ?? this.packed,
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
    );
  }

  @override
  String toString() =>
      'Item(id: $id, tripId: $tripId, name: $name, '
      'category: ${category.name}, quantity: $quantity, packed: $packed)';
}
