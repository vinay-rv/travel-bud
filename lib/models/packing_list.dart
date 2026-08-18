import 'item_category.dart';

/// A saved, reusable packing list — the template a trip's items can be
/// created from, so a familiar trip doesn't mean retyping everything.
///
/// Packed state is deliberately not stored: a saved list is what to bring,
/// not how far along you were last time.
class PackingList {
  final int? id;
  final String name;
  final DateTime createdAt;

  /// How many entries the list holds. Filled in by list queries; zero when the
  /// object is built locally before saving.
  final int itemCount;

  const PackingList({
    this.id,
    required this.name,
    required this.createdAt,
    this.itemCount = 0,
  });

  PackingList copyWith({int? id, String? name, DateTime? createdAt, int? itemCount}) {
    return PackingList(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      itemCount: itemCount ?? this.itemCount,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory PackingList.fromMap(Map<String, Object?> map) {
    return PackingList(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      itemCount: (map['itemCount'] as int?) ?? 0,
    );
  }

  @override
  String toString() => 'PackingList(id: $id, name: $name, items: $itemCount)';
}

/// One line of a saved list. Mirrors the packable fields of an item.
class PackingListEntry {
  final int? id;
  final int listId;
  final String name;
  final ItemCategory category;
  final int quantity;

  const PackingListEntry({
    this.id,
    required this.listId,
    required this.name,
    this.category = ItemCategory.other,
    this.quantity = 1,
  });

  /// e.g. "T-shirts ×3", or just "Passport" for a single.
  String get displayName => quantity > 1 ? '$name ×$quantity' : name;

  PackingListEntry copyWith({
    int? id,
    int? listId,
    String? name,
    ItemCategory? category,
    int? quantity,
  }) {
    return PackingListEntry(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'listId': listId,
    'name': name,
    'category': category.name,
    'quantity': quantity,
  };

  factory PackingListEntry.fromMap(Map<String, Object?> map) {
    return PackingListEntry(
      id: map['id'] as int?,
      listId: map['listId'] as int,
      name: map['name'] as String,
      category: ItemCategory.fromStorage(map['category'] as String?),
      quantity: (map['quantity'] as int?) ?? 1,
    );
  }

  @override
  String toString() =>
      'PackingListEntry(id: $id, listId: $listId, name: $name, '
      'category: ${category.name}, quantity: $quantity)';
}
