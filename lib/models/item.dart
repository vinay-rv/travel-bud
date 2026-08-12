/// A belonging to track. [stayId] is nullable: null means the item travels with
/// the whole trip (passport, charger), non-null ties it to a specific stay.
class Item {
  final int? id;
  final int tripId;
  final int? stayId;
  final String name;
  final bool packed;

  const Item({
    this.id,
    required this.tripId,
    this.stayId,
    required this.name,
    this.packed = false,
  });

  /// True when this item is scoped to the whole trip rather than one stay.
  bool get isWholeTrip => stayId == null;

  Item copyWith({
    int? id,
    int? tripId,
    int? stayId,
    bool clearStayId = false,
    String? name,
    bool? packed,
  }) {
    return Item(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      stayId: clearStayId ? null : (stayId ?? this.stayId),
      name: name ?? this.name,
      packed: packed ?? this.packed,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'stayId': stayId,
      'name': name,
      'packed': packed ? 1 : 0,
    };
  }

  factory Item.fromMap(Map<String, Object?> map) {
    return Item(
      id: map['id'] as int?,
      tripId: map['tripId'] as int,
      stayId: map['stayId'] as int?,
      name: map['name'] as String,
      packed: (map['packed'] as int) == 1,
    );
  }

  @override
  String toString() =>
      'Item(id: $id, tripId: $tripId, stayId: $stayId, name: $name, '
      'packed: $packed)';
}
