/// A hotel stay within a trip, with check-in and check-out timestamps.
/// Checkout reminders are scheduled off [checkOutAt].
class Stay {
  final int? id;
  final int tripId;
  final String hotelName;
  final DateTime checkInAt;
  final DateTime checkOutAt;

  const Stay({
    this.id,
    required this.tripId,
    required this.hotelName,
    required this.checkInAt,
    required this.checkOutAt,
  });

  Stay copyWith({
    int? id,
    int? tripId,
    String? hotelName,
    DateTime? checkInAt,
    DateTime? checkOutAt,
  }) {
    return Stay(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      hotelName: hotelName ?? this.hotelName,
      checkInAt: checkInAt ?? this.checkInAt,
      checkOutAt: checkOutAt ?? this.checkOutAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'hotelName': hotelName,
      'checkInAt': checkInAt.millisecondsSinceEpoch,
      'checkOutAt': checkOutAt.millisecondsSinceEpoch,
    };
  }

  factory Stay.fromMap(Map<String, Object?> map) {
    return Stay(
      id: map['id'] as int?,
      tripId: map['tripId'] as int,
      hotelName: map['hotelName'] as String,
      checkInAt: DateTime.fromMillisecondsSinceEpoch(map['checkInAt'] as int),
      checkOutAt:
          DateTime.fromMillisecondsSinceEpoch(map['checkOutAt'] as int),
    );
  }

  @override
  String toString() =>
      'Stay(id: $id, tripId: $tripId, hotelName: $hotelName, '
      'checkInAt: $checkInAt, checkOutAt: $checkOutAt)';
}
