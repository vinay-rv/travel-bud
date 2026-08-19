import '../auth/api_client.dart';

/// How a cached table maps onto its server counterpart.
///
/// Rows reference their parent by local integer id, which means nothing to the
/// server — so the wire format carries the parent's uuid instead.
class RemoteTable {
  final String name;

  /// Local foreign key column, e.g. `tripId`. Null for top-level tables.
  final String? parentColumn;

  /// The table [parentColumn] points at.
  final String? parentTable;

  /// What the parent is called on the wire, e.g. `tripUuid`.
  final String? parentWireColumn;

  const RemoteTable(
    this.name, {
    this.parentColumn,
    this.parentTable,
    this.parentWireColumn,
  });

  bool get hasParent => parentColumn != null;
}

/// Tables the server holds, parents before children.
///
/// `documents` is absent: its `photoPath` is a device file path, meaningless
/// anywhere else. It joins when the Documents feature gains real file storage.
const remoteTables = <RemoteTable>[
  RemoteTable('trips'),
  RemoteTable('stays',
      parentColumn: 'tripId', parentTable: 'trips', parentWireColumn: 'tripUuid'),
  RemoteTable('transport_legs',
      parentColumn: 'tripId', parentTable: 'trips', parentWireColumn: 'tripUuid'),
  RemoteTable('items',
      parentColumn: 'tripId', parentTable: 'trips', parentWireColumn: 'tripUuid'),
  RemoteTable('expenses',
      parentColumn: 'tripId', parentTable: 'trips', parentWireColumn: 'tripUuid'),
  RemoteTable('packing_lists'),
  RemoteTable('packing_list_items',
      parentColumn: 'listId',
      parentTable: 'packing_lists',
      parentWireColumn: 'listUuid'),
];

RemoteTable? remoteTableFor(String name) {
  for (final table in remoteTables) {
    if (table.name == name) return table;
  }
  return null;
}

/// Columns that exist only on this device and are never sent.
const localOnlyColumns = {'id', 'dirty', 'updatedAt', 'serverUpdatedAt'};

/// The server, as the data layer needs it.
///
/// Behind an interface so the cache can be exercised without a network, the
/// same split that lets the reminder scheduler be tested without the
/// notifications plugin.
abstract class RemoteStore {
  /// Creates or replaces a row. Throws if the server refuses or is unreachable.
  Future<void> upsert(String table, Map<String, Object?> row);

  /// Deletes a row by its uuid.
  Future<void> remove(String table, String uuid);

  /// Everything the account holds in [table].
  Future<List<Map<String, Object?>>> fetchAll(String table);
}

/// Raised when a write cannot reach the server.
///
/// The server owns the data, so an unreachable server means the change did not
/// happen — and the person who made it needs telling, rather than being shown a
/// row that will quietly vanish on the next refresh.
class RemoteUnavailable implements Exception {
  final Object cause;
  const RemoteUnavailable(this.cause);

  @override
  String toString() => 'RemoteUnavailable($cause)';
}

/// Talks to the Packmate API.
class ApiRemoteStore implements RemoteStore {
  final ApiClient api;

  ApiRemoteStore(this.api);

  @override
  Future<void> upsert(String table, Map<String, Object?> row) => _guard(
    () => api.post('/sync/push', body: {
      'table': table,
      'rows': [_encode(row)],
    }),
  );

  @override
  Future<void> remove(String table, String uuid) => _guard(
    () => api.post('/sync/deletes', body: {
      'deletes': [
        {
          'table': table,
          'uuid': uuid,
          'deletedAt': DateTime.now().millisecondsSinceEpoch,
        },
      ],
    }),
  );

  @override
  Future<List<Map<String, Object?>>> fetchAll(String table) async {
    final body = await _guard(
      () => api.get('/sync/pull', query: {'table': table, 'since': '0'}),
    );
    return ((body['rows'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .where((row) => row['deletedAt'] == null)
        .map(_decode)
        .toList();
  }

  /// SQLite has no boolean; Postgres does.
  Map<String, Object?> _encode(Map<String, Object?> row) => {
    for (final entry in row.entries)
      entry.key: entry.key == 'packed' && entry.value is int
          ? entry.value == 1
          : entry.value,
  };

  Map<String, Object?> _decode(Map<String, Object?> row) => {
    for (final entry in row.entries)
      entry.key: entry.value is bool ? ((entry.value as bool) ? 1 : 0) : entry.value,
  };

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiUnavailable catch (e) {
      throw RemoteUnavailable(e);
    } on ApiException catch (e) {
      if (e.isAuthFailure) throw RemoteUnavailable(e);
      rethrow;
    }
  }
}
