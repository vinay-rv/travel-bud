import 'package:sqflite/sqflite.dart';

import '../data/database_helper.dart';
import 'sync_remote.dart';

/// How a local table maps onto its server counterpart.
///
/// Local rows reference their parent by integer id; the server can't use those,
/// because the same trip is id 3 on a phone and id 17 on a tablet. So the wire
/// format carries the parent's uuid instead, and this describes the swap.
class SyncedTable {
  final String name;

  /// Local foreign key column, e.g. `tripId`. Null for top-level tables.
  final String? parentColumn;

  /// The table [parentColumn] points at, e.g. `trips`.
  final String? parentTable;

  /// What the parent is called on the wire, e.g. `tripUuid`.
  final String? parentWireColumn;

  const SyncedTable(
    this.name, {
    this.parentColumn,
    this.parentTable,
    this.parentWireColumn,
  });

  bool get hasParent => parentColumn != null;
}

/// The tables the engine actually uploads, parents before children so a row's
/// parent always exists by the time the row itself is applied.
///
/// `documents` is deliberately absent: its `photoPath` is a device file path,
/// meaningless on another phone and stale even on the same one after a
/// reinstall. It syncs when the Documents feature gains real file storage.
const syncedTables = <SyncedTable>[
  SyncedTable(DatabaseHelper.tableTrip),
  SyncedTable(
    DatabaseHelper.tableStay,
    parentColumn: 'tripId',
    parentTable: DatabaseHelper.tableTrip,
    parentWireColumn: 'tripUuid',
  ),
  SyncedTable(
    DatabaseHelper.tableTransport,
    parentColumn: 'tripId',
    parentTable: DatabaseHelper.tableTrip,
    parentWireColumn: 'tripUuid',
  ),
  SyncedTable(
    DatabaseHelper.tableItem,
    parentColumn: 'tripId',
    parentTable: DatabaseHelper.tableTrip,
    parentWireColumn: 'tripUuid',
  ),
  SyncedTable(DatabaseHelper.tablePackingList),
  SyncedTable(
    DatabaseHelper.tablePackingListItem,
    parentColumn: 'listId',
    parentTable: DatabaseHelper.tablePackingList,
    parentWireColumn: 'listUuid',
  ),
];

/// Columns that exist only on this device and must never be sent.
const _localOnlyColumns = {'id', 'dirty', 'updatedAt', 'serverUpdatedAt'};

/// How a sync attempt ended. Every outcome is ordinary — nothing here is an
/// error the user needs to see.
enum SyncOutcome {
  /// Rows moved, or there was nothing to move.
  ok,

  /// No account yet. Sync is opt-in, so this is the default state.
  noAccount,

  /// Another sync is already running.
  busy,

  /// The local data belongs to a different account. Needs a human decision.
  accountMismatch,

  /// Couldn't reach the server. Normal when travelling.
  unavailable,
}

/// Keeps the local database and the server in step.
///
/// The rules that keep this correct, all of them learned the hard way:
///
/// * Every write here goes through raw SQL, never [DatabaseHelper]'s CRUD
///   methods — those stamp rows dirty, so applying a pulled row through them
///   would queue it straight back for upload, forever.
/// * Upserts use `ON CONFLICT` and never `INSERT OR REPLACE`: replace deletes
///   the old row first, which fires the tombstone trigger and invents a
///   deletion for a row that was only being updated.
/// * Local `updatedAt` is never compared against a server timestamp. Device
///   clocks are wrong; cursors and ordering use server time exclusively.
class SyncEngine {
  final DatabaseHelper db;
  final SyncRemote remote;

  /// Injectable so tests can pin "now", as [ReminderScheduler] does.
  final DateTime Function() clock;

  /// Rows per upload request. A first sync of a long-standing database can be
  /// hundreds of rows; each chunk commits independently.
  final int chunkSize;

  /// Re-reads a little before the cursor, because a transaction can commit with
  /// a timestamp earlier than one already seen. Upserts are idempotent, so
  /// re-reading is free.
  final int overlapMs;

  bool _running = false;

  SyncEngine({
    required this.db,
    required this.remote,
    DateTime Function()? clock,
    this.chunkSize = 200,
    this.overlapMs = 5000,
  }) : clock = clock ?? DateTime.now;

  /// Pushes local changes, then pulls remote ones. Never throws: callers fire
  /// this and forget it.
  Future<SyncOutcome> sync() async {
    if (_running) return SyncOutcome.busy;
    _running = true;
    try {
      final userId = await remote.currentUserId();
      if (userId == null) return SyncOutcome.noAccount;

      if (!await _claim(userId)) return SyncOutcome.accountMismatch;

      // Deletes first: if a row was deleted and a new one created reusing the
      // same uuid, doing it the other way round would resurrect the old one.
      await _pushDeletes();
      for (final table in syncedTables) {
        await _pushUpserts(table);
      }
      for (final table in syncedTables) {
        await _pullTable(table);
      }
      await _setMeta(
        'lastSyncedAt',
        clock().millisecondsSinceEpoch.toString(),
      );
      return SyncOutcome.ok;
    } on SyncUnavailable {
      return SyncOutcome.unavailable;
    } finally {
      _running = false;
    }
  }

  /// Records which account this device's data belongs to, and refuses to run
  /// if that ever changes.
  ///
  /// Without this, signing into a second account on a device that already has
  /// trips would push all of them under the new account and silently duplicate
  /// everything. Merging two accounts is a decision only a person can make.
  Future<bool> _claim(String userId) async {
    final database = await db.database;
    final rows = await database.query(
      DatabaseHelper.tableSyncMeta,
      where: 'key = ?',
      whereArgs: ['userId'],
      limit: 1,
    );

    if (rows.isEmpty) {
      await database.insert(DatabaseHelper.tableSyncMeta, {
        'key': 'userId',
        'value': userId,
      });
      return true;
    }
    return rows.first['value'] == userId;
  }

  /// The account this device's data is claimed by, if any.
  Future<String?> claimedUserId() => _meta('userId');

  /// When the last sync finished, or null if one never has.
  Future<DateTime?> lastSyncedAt() async {
    final value = await _meta('lastSyncedAt');
    final ms = value == null ? null : int.tryParse(value);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Whether this device is currently backing up at all.
  Future<bool> get isBackingUp async => await claimedUserId() != null;

  Future<String?> _meta(String key) async {
    final database = await db.database;
    final rows = await database.query(
      DatabaseHelper.tableSyncMeta,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String? value) async {
    final database = await db.database;
    if (value == null) {
      await database.delete(
        DatabaseHelper.tableSyncMeta,
        where: 'key = ?',
        whereArgs: [key],
      );
      return;
    }
    await database.insert(DatabaseHelper.tableSyncMeta, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------------
  // Account changes
  // ---------------------------------------------------------------------------

  /// Call after signing out: forgets which account this device's rows belong
  /// to and re-queues them all.
  ///
  /// The local database is left completely intact — the phone is the source of
  /// truth. Re-queueing means whoever signs in next receives everything, rather
  /// than rows sitting there looking as though they had already been uploaded.
  Future<void> forgetAccount() => _forgetAccountAndRequeue();

  /// How to settle a device whose data belongs to one account when a different
  /// account has just signed in.
  Future<void> resolveAccountMismatch(MismatchResolution resolution) async {
    switch (resolution) {
      case MismatchResolution.keepThisDevice:
        // Re-offer everything to the new account.
        await _forgetAccountAndRequeue();

      case MismatchResolution.useTheAccount:
        final database = await db.database;
        for (final table in syncedTables.reversed) {
          await database.delete(table.name);
        }
        // Essential, and easy to miss: those deletes just fired the tombstone
        // triggers. Left in place they would be pushed as deletions and would
        // wipe the very account the user asked to keep.
        await database.delete(DatabaseHelper.tableTombstone);
        await database.delete(DatabaseHelper.tableSyncState);
        await _setMeta('userId', null);
        await _setMeta('lastSyncedAt', null);
    }
  }

  Future<void> _forgetAccountAndRequeue() async {
    final database = await db.database;
    for (final table in syncedTables) {
      await database.update(table.name, {'dirty': 1});
    }
    await database.delete(DatabaseHelper.tableSyncState);
    await database.update(DatabaseHelper.tableTombstone, {'dirty': 1});
    await _setMeta('userId', null);
    await _setMeta('lastSyncedAt', null);
  }

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  Future<void> _pushDeletes() async {
    final database = await db.database;
    final pending = await database.query(
      DatabaseHelper.tableTombstone,
      where: 'dirty = 1',
    );
    if (pending.isEmpty) return;

    // Only tables we actually upload — a tombstone for `documents` would be
    // pushed to a table the server isn't tracking yet.
    final tracked = syncedTables.map((t) => t.name).toSet();
    final deletes = pending
        .where((row) => tracked.contains(row['tableName']))
        .map(
          (row) => Tombstone(
            table: row['tableName'] as String,
            uuid: row['uuid'] as String,
            deletedAt: row['deletedAt'] as int,
          ),
        )
        .toList();
    if (deletes.isEmpty) return;

    for (final chunk in _chunks(deletes)) {
      await remote.pushDeletes(chunk);
      for (final tombstone in chunk) {
        await database.update(
          DatabaseHelper.tableTombstone,
          {'dirty': 0},
          where: 'tableName = ? AND uuid = ?',
          whereArgs: [tombstone.table, tombstone.uuid],
        );
      }
    }
  }

  Future<void> _pushUpserts(SyncedTable table) async {
    final database = await db.database;
    final dirty = await database.query(table.name, where: 'dirty = 1');
    if (dirty.isEmpty) return;

    final parentUuids = await _parentUuidsFor(table);

    final payloads = <Map<String, Object?>>[];
    final localUpdatedAt = <String, int>{};
    for (final row in dirty) {
      final uuid = row['uuid'] as String?;
      if (uuid == null) continue; // repaired on next open by _ensureSchema

      final wire = <String, Object?>{'uuid': uuid};
      for (final entry in row.entries) {
        if (_localOnlyColumns.contains(entry.key)) continue;
        if (entry.key == table.parentColumn) continue;
        wire[entry.key] = entry.value;
      }
      if (table.hasParent) {
        final parentUuid = parentUuids[row[table.parentColumn!] as int?];
        // A child whose parent vanished mid-sync: skip it, the next run picks
        // it up or the cascade will have tombstoned it anyway.
        if (parentUuid == null) continue;
        wire[table.parentWireColumn!] = parentUuid;
      }
      payloads.add(wire);
      localUpdatedAt[uuid] = (row['updatedAt'] as int?) ?? 0;
    }
    if (payloads.isEmpty) return;

    for (final chunk in _chunks(payloads)) {
      final pushed = await remote.pushUpserts(table.name, chunk);
      for (final row in pushed) {
        // Guarded on updatedAt: if the row changed while the request was in
        // flight, it must stay dirty so the edit isn't lost.
        await database.update(
          table.name,
          {'dirty': 0, 'serverUpdatedAt': row.serverUpdatedAt},
          where: 'uuid = ? AND updatedAt = ?',
          whereArgs: [row.uuid, localUpdatedAt[row.uuid] ?? 0],
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Pull
  // ---------------------------------------------------------------------------

  Future<void> _pullTable(SyncedTable table) async {
    final cursor = await _cursor(table.name);
    final since = cursor > overlapMs ? cursor - overlapMs : 0;

    final rows = await remote.pull(table.name, sinceMs: since);
    if (rows.isEmpty) return;

    final localIdsByUuid = table.hasParent
        ? await _localIdsByUuid(table.parentTable!)
        : const <String, int>{};

    var highWater = cursor;
    for (final row in rows) {
      final applied = row.isDeleted
          ? await _applyDelete(table, row)
          : await _applyUpsert(table, row, localIdsByUuid);
      // Don't step the cursor past something we couldn't apply — it'll be
      // retried next time rather than lost.
      if (!applied) break;
      if (row.serverUpdatedAt > highWater) highWater = row.serverUpdatedAt;
    }

    if (highWater > cursor) await _setCursor(table.name, highWater);
  }

  Future<bool> _applyDelete(SyncedTable table, RemoteRow row) async {
    final database = await db.database;
    await database.delete(
      table.name,
      where: 'uuid = ?',
      whereArgs: [row.uuid],
    );
    // Our own delete trigger just fired for that row. Clear it, or this device
    // would push the deletion back to the server on every future sync.
    await database.update(
      DatabaseHelper.tableTombstone,
      {'dirty': 0},
      where: 'tableName = ? AND uuid = ?',
      whereArgs: [table.name, row.uuid],
    );
    return true;
  }

  Future<bool> _applyUpsert(
    SyncedTable table,
    RemoteRow row,
    Map<String, int> parentIds,
  ) async {
    final database = await db.database;

    final existing = await database.query(
      table.name,
      columns: ['id', 'dirty'],
      where: 'uuid = ?',
      whereArgs: [row.uuid],
      limit: 1,
    );
    // A local edit outranks what the server has: we pushed ours moments ago, so
    // this is either our own echo or a row that will go up on the next run.
    if (existing.isNotEmpty && existing.first['dirty'] == 1) return true;

    final values = <String, Object?>{
      'uuid': row.uuid,
      'dirty': 0,
      'serverUpdatedAt': row.serverUpdatedAt,
      'updatedAt': clock().millisecondsSinceEpoch,
    };
    // Only columns this device actually has. The server carries things the app
    // doesn't — `userId`, the generated timestamp twins — and a newer server
    // may carry columns an older app has never heard of. Filtering here means
    // those are ignored rather than turning into "no such column" on insert.
    final localColumns = await _localColumns(table.name);
    for (final entry in row.values.entries) {
      if (entry.key == table.parentWireColumn) continue;
      if (_localOnlyColumns.contains(entry.key)) continue;
      if (!localColumns.contains(entry.key)) continue;
      values[entry.key] = entry.value;
    }

    if (table.hasParent) {
      final parentUuid = row.values[table.parentWireColumn!] as String?;
      final localParentId = parentUuid == null ? null : parentIds[parentUuid];
      // The parent hasn't arrived yet. Stop here rather than dropping the row:
      // leaving the cursor put means we see it again next sync.
      if (localParentId == null) return false;
      values[table.parentColumn!] = localParentId;
    }

    final columns = values.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    // `ON CONFLICT`, never `INSERT OR REPLACE` — replace would delete the old
    // row first and fire the tombstone trigger, inventing a delete.
    final assignments = columns
        .where((c) => c != 'uuid')
        .map((c) => '$c = excluded.$c')
        .join(', ');

    await database.rawInsert(
      'INSERT INTO ${table.name} (${columns.join(', ')}) '
      'VALUES ($placeholders) '
      'ON CONFLICT(uuid) DO UPDATE SET $assignments',
      columns.map((c) => values[c]).toList(),
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  final Map<String, Set<String>> _columnCache = {};

  /// The columns [table] actually has on this device, read once and kept.
  Future<Set<String>> _localColumns(String table) async {
    final cached = _columnCache[table];
    if (cached != null) return cached;

    final database = await db.database;
    final columns = (await database.rawQuery('PRAGMA table_info($table)'))
        .map((row) => row['name'] as String)
        .toSet();
    _columnCache[table] = columns;
    return columns;
  }

  /// local id → uuid, for translating a child's foreign key on the way out.
  Future<Map<int, String>> _parentUuidsFor(SyncedTable table) async {
    if (!table.hasParent) return const {};
    final database = await db.database;
    final rows = await database.query(
      table.parentTable!,
      columns: ['id', 'uuid'],
    );
    return {
      for (final row in rows)
        if (row['uuid'] != null) row['id'] as int: row['uuid'] as String,
    };
  }

  /// uuid → local id, for translating a child's parent on the way in.
  Future<Map<String, int>> _localIdsByUuid(String table) async {
    final database = await db.database;
    final rows = await database.query(table, columns: ['id', 'uuid']);
    return {
      for (final row in rows)
        if (row['uuid'] != null) row['uuid'] as String: row['id'] as int,
    };
  }

  Future<int> _cursor(String table) async {
    final database = await db.database;
    final rows = await database.query(
      DatabaseHelper.tableSyncState,
      where: 'tableName = ?',
      whereArgs: [table],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.first['cursorMs'] as int;
  }

  Future<void> _setCursor(String table, int cursorMs) async {
    final database = await db.database;
    await database.insert(DatabaseHelper.tableSyncState, {
      'tableName': table,
      'cursorMs': cursorMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Iterable<List<T>> _chunks<T>(List<T> items) sync* {
    for (var i = 0; i < items.length; i += chunkSize) {
      yield items.sublist(
        i,
        i + chunkSize > items.length ? items.length : i + chunkSize,
      );
    }
  }
}

/// What to do when the signed-in account isn't the one this device's data
/// belongs to. There is deliberately no automatic merge here: guessing wrong
/// either duplicates everything or destroys something the user wanted.
enum MismatchResolution {
  /// Give this device's trips to the new account.
  keepThisDevice,

  /// Discard this device's copy and take the account's instead.
  useTheAccount,
}

/// App-wide engine. `main` swaps in one backed by the real server once the user
/// opts into backup; the default no-ops, so tests and every pre-opt-in call are
/// inert — the same shape as `Reminders`.
class Sync {
  Sync._();

  static SyncEngine instance = SyncEngine(
    db: DatabaseHelper.instance,
    remote: const _NoopRemote(),
  );
}

/// Stands in until an account exists. Reports "no account", which is exactly
/// what's true before the user opts in.
class _NoopRemote implements SyncRemote {
  const _NoopRemote();

  @override
  Future<String?> currentUserId() async => null;

  @override
  Future<List<PushedRow>> pushUpserts(
    String table,
    List<Map<String, Object?>> rows,
  ) async => const [];

  @override
  Future<void> pushDeletes(List<Tombstone> deletes) async {}

  @override
  Future<List<RemoteRow>> pull(String table, {required int sinceMs}) async =>
      const [];
}
