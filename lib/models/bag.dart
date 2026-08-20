/// A named container an item travels in — a cabin bag, a rucksack, the boot of
/// the car.
///
/// Bags belong to a trip, not to the account: what you carry changes from a
/// weekend away to a month abroad, and a stale list of last year's bags is
/// worse than naming two of them again. Items reference a bag by id, and an
/// item with no bag is simply not packed into one yet.
class Bag {
  final int? id;
  final int tripId;
  final String name;

  const Bag({this.id, required this.tripId, required this.name});

  Bag copyWith({int? id, int? tripId, String? name}) {
    return Bag(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
    );
  }

  Map<String, Object?> toMap() {
    return {'id': id, 'tripId': tripId, 'name': name};
  }

  factory Bag.fromMap(Map<String, Object?> map) {
    return Bag(
      id: map['id'] as int?,
      tripId: map['tripId'] as int,
      name: map['name'] as String,
    );
  }

  @override
  String toString() => 'Bag(id: $id, tripId: $tripId, name: $name)';
}
