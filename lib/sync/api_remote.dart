import '../auth/api_client.dart';
import 'sync_remote.dart';

/// The real server, over the Packmate API.
///
/// The wire format is the app's own field names, because the API's columns are
/// spelled the same way — so nothing is translated here beyond the one thing
/// SQLite cannot represent: `packed` is 0/1 locally and a real boolean over the
/// wire, and sqflite refuses to bind a `bool` at all.
class ApiRemote implements SyncRemote {
  final ApiClient api;

  ApiRemote(this.api);

  @override
  Future<String?> currentUserId() async => api.session?.userId;

  @override
  Future<List<PushedRow>> pushUpserts(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return const [];

    final body = await _guard(
      () => api.post('/sync/push', body: {
        'table': table,
        'rows': rows.map(_encode).toList(),
      }),
    );

    return ((body['rows'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map(
          (row) => PushedRow(
            uuid: row['uuid'] as String,
            serverUpdatedAt: (row['updatedAt'] as num).toInt(),
          ),
        )
        .toList();
  }

  @override
  Future<void> pushDeletes(List<Tombstone> deletes) async {
    if (deletes.isEmpty) return;

    await _guard(
      () => api.post('/sync/deletes', body: {
        'deletes': deletes
            .map((t) => {
                  'table': t.table,
                  'uuid': t.uuid,
                  'deletedAt': t.deletedAt,
                })
            .toList(),
      }),
    );
  }

  @override
  Future<List<RemoteRow>> pull(String table, {required int sinceMs}) async {
    final body = await _guard(
      () => api.get('/sync/pull', query: {
        'table': table,
        'since': '$sinceMs',
      }),
    );

    return ((body['rows'] as List?) ?? const [])
        .cast<Map<String, Object?>>()
        .map((row) {
          final decoded = _decode(row);
          return RemoteRow(
            uuid: decoded['uuid'] as String,
            values: decoded,
            serverUpdatedAt: (decoded['updatedAt'] as num).toInt(),
            deletedAt: (decoded['deletedAt'] as num?)?.toInt(),
          );
        })
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
      entry.key: entry.value is bool
          ? ((entry.value as bool) ? 1 : 0)
          : entry.value,
  };

  /// Being unreachable is ordinary; the engine treats it as a quiet outcome.
  /// A real API error is a bug and is left to surface.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiUnavailable catch (e) {
      throw SyncUnavailable(e);
    } on ApiException catch (e) {
      // Session gone: nothing to sync until the user signs in again, which the
      // gate will already be showing them.
      if (e.isAuthFailure) throw SyncUnavailable(e);
      rethrow;
    }
  }
}
