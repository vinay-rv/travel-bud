/// The mode of transport for a [TransportLeg].
enum TransportType { flight, train, bus }

extension TransportTypeLabel on TransportType {
  /// Human-readable label for display.
  String get label {
    switch (this) {
      case TransportType.flight:
        return 'Flight';
      case TransportType.train:
        return 'Train';
      case TransportType.bus:
        return 'Bus';
    }
  }
}

/// A transport leg within a trip (flight/train/bus). Pre-departure reminders
/// are scheduled off [departureAt].
class TransportLeg {
  final int? id;
  final int tripId;
  final TransportType type;
  final DateTime departureAt;
  final String fromLocation;
  final String toLocation;

  const TransportLeg({
    this.id,
    required this.tripId,
    required this.type,
    required this.departureAt,
    required this.fromLocation,
    required this.toLocation,
  });

  TransportLeg copyWith({
    int? id,
    int? tripId,
    TransportType? type,
    DateTime? departureAt,
    String? fromLocation,
    String? toLocation,
  }) {
    return TransportLeg(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      type: type ?? this.type,
      departureAt: departureAt ?? this.departureAt,
      fromLocation: fromLocation ?? this.fromLocation,
      toLocation: toLocation ?? this.toLocation,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'type': type.name,
      'departureAt': departureAt.millisecondsSinceEpoch,
      'fromLocation': fromLocation,
      'toLocation': toLocation,
    };
  }

  factory TransportLeg.fromMap(Map<String, Object?> map) {
    return TransportLeg(
      id: map['id'] as int?,
      tripId: map['tripId'] as int,
      type: TransportType.values.byName(map['type'] as String),
      departureAt:
          DateTime.fromMillisecondsSinceEpoch(map['departureAt'] as int),
      fromLocation: map['fromLocation'] as String,
      toLocation: map['toLocation'] as String,
    );
  }

  @override
  String toString() =>
      'TransportLeg(id: $id, tripId: $tripId, type: ${type.name}, '
      'departureAt: $departureAt, fromLocation: $fromLocation, '
      'toLocation: $toLocation)';
}
