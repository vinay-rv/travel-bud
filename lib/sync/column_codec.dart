/// Translation between the app's column names and the server's.
///
/// The Dart models use camelCase (`startDate`, `hotelName`), and the Postgres
/// schema is idiomatic snake_case (`start_date`, `hotel_name`) so that the
/// tables stay pleasant to query by hand — which the AI itinerary planner will
/// need to do later.
///
/// This is deliberately a rule rather than a hand-maintained table of column
/// pairs: a mapping table drifts silently the moment someone adds a field, and
/// the failure shows up as a rejected push rather than a compile error.
library;

/// `checkOutAt` → `check_out_at`.
String camelToSnake(String name) => name.replaceAllMapped(
  RegExp(r'[A-Z]'),
  (match) => '_${match[0]!.toLowerCase()}',
);

/// `check_out_at` → `checkOutAt`.
String snakeToCamel(String name) => name.replaceAllMapped(
  RegExp(r'_([a-z0-9])'),
  (match) => match[1]!.toUpperCase(),
);

/// Columns SQLite stores as 0/1 integers and Postgres stores as real booleans.
const _booleanColumns = {'packed'};

/// App row → server row.
Map<String, Object?> encodeRow(Map<String, Object?> row) {
  final encoded = <String, Object?>{};
  for (final entry in row.entries) {
    var value = entry.value;
    if (_booleanColumns.contains(entry.key) && value is int) {
      value = value == 1;
    }
    encoded[camelToSnake(entry.key)] = value;
  }
  return encoded;
}

/// Server row → app row.
///
/// Booleans come back as 0/1 because sqflite refuses to bind a `bool` at all —
/// it accepts only num, String, Uint8List and null.
Map<String, Object?> decodeRow(Map<String, Object?> row) {
  final decoded = <String, Object?>{};
  for (final entry in row.entries) {
    final value = entry.value;
    decoded[snakeToCamel(entry.key)] = value is bool ? (value ? 1 : 0) : value;
  }
  return decoded;
}
