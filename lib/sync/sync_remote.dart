/// The server side of syncing, kept behind an interface so the engine can be
/// tested without a network — the same split that lets `ReminderScheduler` be
/// tested without the notifications plugin.
///
/// Everything here speaks in plain maps keyed by *wire* column names. The
/// engine translates between those and the local schema, so nothing below this
/// line knows that local rows have integer primary keys.
library;

/// A row as the server holds it: its uuid, its columns, and the server's own
/// timestamp for the version being described.
///
/// [deletedAt] being non-null makes this a tombstone — the same pull returns
/// both live rows and deletions, so there's no second round trip for deletes.
class RemoteRow {
  final String uuid;
  final Map<String, Object?> values;
  final int serverUpdatedAt;
  final int? deletedAt;

  const RemoteRow({
    required this.uuid,
    required this.values,
    required this.serverUpdatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  @override
  String toString() =>
      'RemoteRow($uuid, updated: $serverUpdatedAt'
      '${isDeleted ? ', deleted' : ''})';
}

/// A local delete on its way to the server.
class Tombstone {
  final String table;
  final String uuid;
  final int deletedAt;

  const Tombstone({
    required this.table,
    required this.uuid,
    required this.deletedAt,
  });

  @override
  String toString() => 'Tombstone($table, $uuid)';
}

/// What the server said about a row we pushed. The engine records
/// [serverUpdatedAt] so the next pull can tell "this is my own echo" from
/// "someone else changed this".
class PushedRow {
  final String uuid;
  final int serverUpdatedAt;

  const PushedRow({required this.uuid, required this.serverUpdatedAt});
}

/// Thrown by an implementation when the server can't be reached. The engine
/// treats it as an ordinary, quiet failure — being offline is the normal state
/// for a travel app, not an error worth showing anyone.
class SyncUnavailable implements Exception {
  final Object cause;

  const SyncUnavailable(this.cause);

  @override
  String toString() => 'SyncUnavailable($cause)';
}

abstract class SyncRemote {
  /// The signed-in account, or null when there isn't one. Null means sync is
  /// simply not switched on yet, which is the default state of the app.
  Future<String?> currentUserId();

  /// Creates an account without asking for any personal details, returning its
  /// id. Called the moment the user opts into backup and never before — until
  /// then nothing about their trips leaves the device.
  Future<String> signInAnonymously();

  /// Ends the session. The local database is untouched; the phone remains the
  /// source of truth whether or not anyone is signed in.
  Future<void> signOut();

  /// Upserts [rows] into [table], keyed by uuid, returning the server
  /// timestamp it assigned to each.
  Future<List<PushedRow>> pushUpserts(
    String table,
    List<Map<String, Object?>> rows,
  );

  /// Marks rows deleted server-side.
  Future<void> pushDeletes(List<Tombstone> deletes);

  /// Rows in [table] the server has touched since [sinceMs], including
  /// tombstones. Ordered by the server's timestamp.
  Future<List<RemoteRow>> pull(String table, {required int sinceMs});
}
