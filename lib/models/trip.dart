/// A trip is the top-level container. It has a name and a date range, and owns
/// stays, transport legs, items, and documents.
class Trip {
  final int? id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  const Trip({
    this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
  });

  Trip copyWith({
    int? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return Trip(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate.millisecondsSinceEpoch,
    };
  }

  factory Trip.fromMap(Map<String, Object?> map) {
    return Trip(
      id: map['id'] as int?,
      name: map['name'] as String,
      startDate:
          DateTime.fromMillisecondsSinceEpoch(map['startDate'] as int),
      endDate: DateTime.fromMillisecondsSinceEpoch(map['endDate'] as int),
    );
  }

  @override
  String toString() =>
      'Trip(id: $id, name: $name, startDate: $startDate, endDate: $endDate)';
}
