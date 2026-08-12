/// A locally-stored photo of a travel document (passport, ticket, ID).
/// [photoPath] is an on-device file path; nothing is uploaded anywhere.
class Document {
  final int? id;
  final int tripId;
  final String photoPath;
  final String label;

  const Document({
    this.id,
    required this.tripId,
    required this.photoPath,
    required this.label,
  });

  Document copyWith({
    int? id,
    int? tripId,
    String? photoPath,
    String? label,
  }) {
    return Document(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      photoPath: photoPath ?? this.photoPath,
      label: label ?? this.label,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'photoPath': photoPath,
      'label': label,
    };
  }

  factory Document.fromMap(Map<String, Object?> map) {
    return Document(
      id: map['id'] as int?,
      tripId: map['tripId'] as int,
      photoPath: map['photoPath'] as String,
      label: map['label'] as String,
    );
  }

  @override
  String toString() =>
      'Document(id: $id, tripId: $tripId, photoPath: $photoPath, '
      'label: $label)';
}
