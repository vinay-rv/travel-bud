/// A belonging to track. Items always belong to the whole trip: there are no
/// hotel-specific items, so every item counts for every stay (a checkout
/// reminder at any hotel considers the trip's full packing list).
class Item {
  final int? id;
  final int tripId;
  final String name;
  final bool packed;

  const Item({
    this.id,
    required this.tripId,
    required this.name,
    this.packed = false,
  });

  Item copyWith({int? id, int? tripId, String? name, bool? packed}) {
    return Item(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
      packed: packed ?? this.packed,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'name': name,
      'packed': packed ? 1 : 0,
    };
  }

  factory Item.fromMap(Map<String, Object?> map) {
    return Item(
      id: map['id'] as int?,
      tripId: map['tripId'] as int,
      name: map['name'] as String,
      packed: (map['packed'] as int) == 1,
    );
  }

  @override
  String toString() =>
      'Item(id: $id, tripId: $tripId, name: $name, packed: $packed)';
}
