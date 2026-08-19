/// Something spent on a trip.
///
/// [amountMinor] is an integer of the currency's smallest unit — 1250 for
/// 12.50. Money is never stored as a double: a tenth cannot be represented
/// exactly in binary, so sums drift and a total eventually disagrees with the
/// rows above it by a penny.
///
/// [spentAt] is when the money went, not when the row was typed — you often add
/// yesterday's taxi this morning.
class Expense {
  final int? id;
  final int tripId;
  final String name;
  final int amountMinor;
  final DateTime spentAt;

  const Expense({
    this.id,
    required this.tripId,
    required this.name,
    required this.amountMinor,
    required this.spentAt,
  });

  Expense copyWith({
    int? id,
    int? tripId,
    String? name,
    int? amountMinor,
    DateTime? spentAt,
  }) {
    return Expense(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
      amountMinor: amountMinor ?? this.amountMinor,
      spentAt: spentAt ?? this.spentAt,
    );
  }

  /// The amount as a plain decimal string, e.g. "1250" -> "12.50".
  String get amountLabel => formatMinor(amountMinor);

  Map<String, Object?> toMap() => {
    'id': id,
    'tripId': tripId,
    'name': name,
    'amountMinor': amountMinor,
    'spentAt': spentAt.millisecondsSinceEpoch,
  };

  factory Expense.fromMap(Map<String, Object?> map) => Expense(
    id: map['id'] as int?,
    tripId: map['tripId'] as int,
    name: map['name'] as String,
    amountMinor: (map['amountMinor'] as num).toInt(),
    spentAt: DateTime.fromMillisecondsSinceEpoch((map['spentAt'] as num).toInt()),
  );

  @override
  String toString() =>
      'Expense(id: $id, tripId: $tripId, name: $name, '
      'amount: $amountLabel, spentAt: $spentAt)';
}

/// Minor units to a decimal string with a thousands separator: 123456 -> "1,234.56".
String formatMinor(int minor) {
  final negative = minor < 0;
  final absolute = minor.abs();
  final major = (absolute ~/ 100).toString();
  final fraction = (absolute % 100).toString().padLeft(2, '0');

  final grouped = StringBuffer();
  for (var i = 0; i < major.length; i++) {
    if (i > 0 && (major.length - i) % 3 == 0) grouped.write(',');
    grouped.write(major[i]);
  }
  return '${negative ? '-' : ''}$grouped.$fraction';
}

/// Parses what someone typed into minor units. Null when it isn't a number.
///
/// Accepts "12", "12.5", "12.50" and "1,234.56"; refuses more than two decimal
/// places rather than silently rounding away part of an amount.
int? parseMinor(String input) {
  final cleaned = input.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;

  final parts = cleaned.split('.');
  final major = int.parse(parts[0]);
  final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return major * 100 + int.parse(fraction);
}
