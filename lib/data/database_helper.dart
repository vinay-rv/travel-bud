import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/trip.dart';
import '../models/stay.dart';
import '../models/transport_leg.dart';
import '../models/item.dart';
import '../models/document.dart';
import '../models/item_category.dart';
import '../models/packing_list.dart';
import 'remote_store.dart';

/// Single point of access to the on-device SQLite database. Owns the schema,
/// the connection, and CRUD for all seven tables.
///
/// This is still the source of truth for everything the UI shows — it makes no
/// network calls itself. Since v4 every row also carries sync metadata (a
/// `uuid`, `updatedAt`, and a `dirty` flag) and deletes leave a tombstone, so a
/// sync engine can later mirror this database to a server without any screen
/// having to know about it.
///
/// Use [DatabaseHelper.instance] everywhere. For tests, call
/// [DatabaseHelper.forTesting] with an in-memory path.
class DatabaseHelper {
  static const _dbName = 'trip_inventory.db';
  static const _dbVersion = 4;

  static const tableTrip = 'trips';
  static const tableStay = 'stays';
  static const tableTransport = 'transport_legs';
  static const tableItem = 'items';
  static const tableDocument = 'documents';
  static const tablePackingList = 'packing_lists';
  static const tablePackingListItem = 'packing_list_items';

  /// Bookkeeping for the sync engine. These never hold user-visible content.
  static const tableSyncState = 'sync_state';
  static const tableTombstone = 'sync_tombstones';
  static const tableSyncMeta = 'sync_meta';

  /// The tables that carry sync metadata, parents before children — pushing and
  /// applying in this order means a row's parent always exists first.
  static const syncedTables = [
    tableTrip,
    tableStay,
    tableTransport,
    tableItem,
    tableDocument,
    tablePackingList,
    tablePackingListItem,
  ];

  DatabaseHelper._(this._explicitPath);

  /// App-wide singleton backed by the default on-device database file.
  static final DatabaseHelper instance = DatabaseHelper._(null);

  /// Builds a helper against an explicit path (e.g. `inMemoryDatabasePath`)
  /// for tests, so each test gets an isolated database.
  factory DatabaseHelper.forTesting(String path) => DatabaseHelper._(path);

  final String? _explicitPath;
  Database? _db;

  /// The server this cache mirrors. Null before sign-in, and in tests, where
  /// writes stay local.
  RemoteStore? remote;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final path = _explicitPath ?? join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        // Enforce foreign keys so cascading deletes actually cascade.
        await db.execute('PRAGMA foreign_keys = ON');
        // A cascaded delete must still fire the child's tombstone trigger, or
        // deletes would never reach other devices. SQLite's default for this
        // has varied by version, and sqflite uses whatever SQLite the OS
        // bundles — so state it explicitly rather than inheriting a default.
        await db.execute('PRAGMA recursive_triggers = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
      onOpen: _ensureSchema,
    );
  }

  /// Backstop for databases whose stored version says they're current but
  /// whose tables are not — e.g. a file that was open across a version bump,
  /// so `onUpgrade` never ran for it and never will.
  ///
  /// Every statement here is conditional on what's actually in the file, so
  /// this is a no-op on a healthy database and costs two catalogue reads.
  Future<void> _ensureSchema(Database db) async {
    final itemColumns = (await db.rawQuery('PRAGMA table_info($tableItem)'))
        .map((row) => row['name'] as String)
        .toSet();
    if (!itemColumns.contains('category')) {
      await db.execute(
        "ALTER TABLE $tableItem ADD COLUMN category TEXT NOT NULL "
        "DEFAULT 'other'",
      );
    }
    if (!itemColumns.contains('quantity')) {
      await db.execute(
        'ALTER TABLE $tableItem ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1',
      );
    }

    final catalogue = await db.rawQuery(
      "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'trigger')",
    );
    final tables = catalogue
        .where((row) => row['type'] == 'table')
        .map((row) => row['name'] as String)
        .toSet();
    final triggers = catalogue
        .where((row) => row['type'] == 'trigger')
        .map((row) => row['name'] as String)
        .toSet();

    if (!tables.contains(tablePackingList) ||
        !tables.contains(tablePackingListItem)) {
      await _createPackingListTables(db);
    }

    // The v4 sync shape. Without this, a file stamped v4 but never actually
    // migrated fails at runtime on the first write with "no such column: uuid".
    if (!tables.contains(tableSyncState) ||
        !tables.contains(tableTombstone) ||
        !tables.contains(tableSyncMeta)) {
      await _createSyncTables(db);
    }
    for (final table in syncedTables) {
      // Also re-runs the uuid backfill, which repairs any row inserted without
      // one — cheap at this scale and the only thing standing between a missed
      // write path and an unsyncable row.
      await _addSyncColumns(db, table);
    }
    if (syncedTables.any((t) => !triggers.contains('trg_${t}_tombstone'))) {
      await _createTombstoneTriggers(db);
    }
  }

  /// Steps a database up to [_dbVersion], one version at a time.
  ///
  /// Each step spells out the DDL it needs rather than calling the current
  /// `CREATE TABLE` helpers: those track the latest schema and would silently
  /// change what an old migration produces.
  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // v1 scoped items to an optional stay. Items are now always trip-wide, so
    // rebuild the table without `stayId`, keeping every existing item.
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableItem RENAME TO ${tableItem}_old');
      await db.execute('''
        CREATE TABLE $tableItem (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tripId INTEGER NOT NULL,
          name TEXT NOT NULL,
          packed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (tripId) REFERENCES $tableTrip (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        INSERT INTO $tableItem (id, tripId, name, packed)
        SELECT id, tripId, name, packed FROM ${tableItem}_old
      ''');
      await db.execute('DROP TABLE ${tableItem}_old');
    }

    // v3 adds categories and quantities to items, plus saved packing lists.
    // Existing items land in "other" with a quantity of one.
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE $tableItem ADD COLUMN category TEXT NOT NULL "
        "DEFAULT 'other'",
      );
      await db.execute(
        'ALTER TABLE $tableItem ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1',
      );
      await _createPackingListTables(db);
    }

    // v4 adds sync metadata to every table, plus the bookkeeping tables and
    // the tombstone triggers a sync engine needs.
    //
    // Deliberately `ALTER TABLE ADD COLUMN` rather than rebuilding the tables:
    // a rebuild risks silently renumbering integer ids, and notification ids
    // are derived from stay ids (`reminder_scheduler.dart`), so a shifted id
    // would orphan every scheduled reminder.
    if (oldVersion < 4) {
      for (final table in syncedTables) {
        await _addSyncColumns(db, table);
      }
      await _createSyncTables(db);
      await _createTombstoneTriggers(db);
    }
  }

  /// Generates a canonical v4 UUID in pure SQL, so backfilling an existing
  /// database needs no round trip through Dart.
  static const _uuidExpression = '''
    lower(
      hex(randomblob(4)) || '-' ||
      hex(randomblob(2)) || '-4' ||
      substr(hex(randomblob(2)), 2) || '-' ||
      substr('89ab', (random() & 3) + 1, 1) ||
      substr(hex(randomblob(2)), 2) || '-' ||
      hex(randomblob(6))
    )
  ''';

  /// Adds the sync columns to [table] and backfills them, if they're absent.
  ///
  /// Shared by the v4 migration and [_ensureSchema]; safe only because v4 is
  /// the newest step. **The moment a v5 exists, freeze a copy of this inside
  /// the v4 block** — migrations must not track the latest schema.
  ///
  /// `dirty` defaults to 1 so every pre-existing row is queued for the first
  /// push: that is what makes "claim my existing data" free.
  /// True when [table] is present. `PRAGMA table_info` returns nothing for a
  /// table that doesn't exist, which is the cheapest way to ask.
  Future<bool> _tableExists(Database db, String table) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.isNotEmpty;
  }

  Future<void> _addSyncColumns(Database db, String table) async {
    final columns = (await db.rawQuery('PRAGMA table_info($table)'))
        .map((row) => row['name'] as String)
        .toSet();

    // No such table. Happens for databases that predate one, and for any file
    // that lost one — leave it alone rather than throwing; whatever creates the
    // table will come back through here on the next open.
    if (columns.isEmpty) return;

    if (!columns.contains('uuid')) {
      // Added nullable then backfilled: SQLite cannot add a UNIQUE column, nor
      // one whose DEFAULT is an expression. The uniqueness is an index instead.
      await db.execute('ALTER TABLE $table ADD COLUMN uuid TEXT');
    }
    if (!columns.contains('updatedAt')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN updatedAt INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columns.contains('dirty')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!columns.contains('serverUpdatedAt')) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN serverUpdatedAt INTEGER',
      );
    }

    // A no-op on healthy data; repairs any row that reached the table without
    // a uuid (see the batch write paths).
    await db.execute(
      'UPDATE $table SET uuid = $_uuidExpression WHERE uuid IS NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_uuid ON $table(uuid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${table}_dirty '
      'ON $table(dirty) WHERE dirty = 1',
    );
  }

  Future<void> _createSyncTables(Database db) async {
    // How far each table has been pulled, in server time.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSyncState (
        tableName TEXT PRIMARY KEY,
        cursorMs INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // Rows are hard-deleted locally so no SELECT needs a "not deleted" filter;
    // the delete itself is remembered here until it has been pushed.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableTombstone (
        tableName TEXT NOT NULL,
        uuid TEXT NOT NULL,
        deletedAt INTEGER NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (tableName, uuid)
      )
    ''');
    // Holds the account id the local data belongs to, so signing into a
    // different account can be detected instead of silently merging.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSyncMeta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  /// One `AFTER DELETE` trigger per table. With `recursive_triggers` on, these
  /// also fire for rows removed by a foreign key cascade, so deleting a trip
  /// tombstones its stays, transport, items, and documents too.
  Future<void> _createTombstoneTriggers(Database db) async {
    for (final table in syncedTables) {
      if (!await _tableExists(db, table)) continue;
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${table}_tombstone
        AFTER DELETE ON $table
        WHEN OLD.uuid IS NOT NULL
        BEGIN
          INSERT INTO $tableTombstone (tableName, uuid, deletedAt, dirty)
          VALUES (
            '$table',
            OLD.uuid,
            CAST(strftime('%s', 'now') AS INTEGER) * 1000,
            1
          )
          ON CONFLICT(tableName, uuid) DO UPDATE SET
            deletedAt = excluded.deletedAt,
            dirty = 1;
        END
      ''');
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableTrip (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        startDate INTEGER NOT NULL,
        endDate INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableStay (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        hotelName TEXT NOT NULL,
        checkInAt INTEGER NOT NULL,
        checkOutAt INTEGER NOT NULL,
        FOREIGN KEY (tripId) REFERENCES $tableTrip (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTransport (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        type TEXT NOT NULL,
        departureAt INTEGER NOT NULL,
        fromLocation TEXT NOT NULL,
        toLocation TEXT NOT NULL,
        FOREIGN KEY (tripId) REFERENCES $tableTrip (id) ON DELETE CASCADE
      )
    ''');

    await _createItemTable(db);
    await _createPackingListTables(db);

    await db.execute('''
      CREATE TABLE $tableDocument (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        photoPath TEXT NOT NULL,
        label TEXT NOT NULL,
        FOREIGN KEY (tripId) REFERENCES $tableTrip (id) ON DELETE CASCADE
      )
    ''');

    // Deliberately the same code the v4 migration runs, rather than inlining
    // the columns above: a fresh install and an upgraded database must end up
    // with byte-identical schemas, and the only way to guarantee that is for
    // both to travel the same path. The backfill is a no-op on empty tables.
    for (final table in syncedTables) {
      await _addSyncColumns(db, table);
    }
    await _createSyncTables(db);
    await _createTombstoneTriggers(db);
  }

  /// Items are trip-scoped only — no stay column, so nothing to cascade when a
  /// stay is deleted.
  Future<void> _createItemTable(Database db) async {
    await db.execute('''
      CREATE TABLE $tableItem (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'other',
        quantity INTEGER NOT NULL DEFAULT 1,
        packed INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (tripId) REFERENCES $tableTrip (id) ON DELETE CASCADE
      )
    ''');
  }

  /// Saved lists live outside any trip — that's the point of them.
  ///
  /// `IF NOT EXISTS` so [_ensureSchema] can call this when only one of the two
  /// tables is missing.
  Future<void> _createPackingListTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePackingList (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablePackingListItem (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        listId INTEGER NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'other',
        quantity INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (listId) REFERENCES $tablePackingList (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ---------------------------------------------------------------------------
  // Sync stamping
  //
  // Every write goes through one of these two, which is the whole reason no
  // screen and no model has to know sync exists. Models deliberately never
  // carry `uuid`/`updatedAt`/`dirty` in their `toMap()` — those live only here.
  // ---------------------------------------------------------------------------

  static final _uuidGen = Uuid();

  /// Bumped by every write. Something that wants to react to changes — the sync
  /// engine — listens here rather than every screen having to remember to tell
  /// it, which is how the reminder rescheduling calls ended up scattered
  /// through the widget layer.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// Column values for a brand new row: a fresh identity plus bookkeeping.
  Map<String, Object?> _stampNew(Map<String, Object?> values) {
    revision.value++;
    return {
      ...values,
      'uuid': _uuidGen.v4(),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'dirty': 1,
    };
  }

  /// Column values for a changed row. Leaves `uuid` alone — a row's identity to
  /// the server must never change, or other devices see a delete and an insert.
  Map<String, Object?> _stampChanged(Map<String, Object?> values) {
    revision.value++;
    return {
      ...values,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'dirty': 1,
    };
  }


  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------
  //
  // The server owns the data; this database is a cache of it. So every write
  // goes to the server first and is only mirrored locally once accepted. If the
  // server refuses or cannot be reached, nothing is written here either — a
  // cached row the server never saw would simply vanish at the next refresh,
  // which is worse than an honest failure.
  //
  // With no [remote] set, these are pure local writes. That is what the tests
  // use, and what the app does before anyone signs in.

  /// Inserts, returning the new local id.
  Future<int> _insertRow(String table, Map<String, Object?> values) async {
    final db = await database;
    final stamped = _stampNew(values);
    await _pushUpsert(table, stamped);
    return db.insert(table, stamped);
  }

  /// Updates the row with [id], returning rows changed.
  Future<int> _updateRow(
    String table,
    Map<String, Object?> values,
    int id,
  ) async {
    final db = await database;
    final stamped = _stampChanged(values);
    final uuid = await _uuidOf(table, id);
    if (uuid != null) {
      // Send the whole row, not just the changed fields: the server upserts,
      // and a partial row would blank the columns left out.
      final full = await _rowOf(table, id);
      if (full != null) await _pushUpsert(table, {...full, ...stamped});
    }
    return db.update(table, stamped, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the row with [id], returning rows deleted.
  Future<int> _deleteRow(String table, int id) async {
    final db = await database;
    final uuid = await _uuidOf(table, id);
    if (uuid != null && remote != null && remoteTableFor(table) != null) {
      await remote!.remove(table, uuid);
    }
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _pushUpsert(String table, Map<String, Object?> row) async {
    final spec = remoteTableFor(table);
    if (remote == null || spec == null) return;

    final wire = <String, Object?>{};
    for (final entry in row.entries) {
      if (localOnlyColumns.contains(entry.key)) continue;
      if (entry.key == spec.parentColumn) continue;
      wire[entry.key] = entry.value;
    }
    if (spec.hasParent) {
      final parentUuid =
          await _uuidOf(spec.parentTable!, row[spec.parentColumn!] as int);
      if (parentUuid == null) return;
      wire[spec.parentWireColumn!] = parentUuid;
    }
    await remote!.upsert(table, wire);
  }

  Future<String?> _uuidOf(String table, int id) async {
    final db = await database;
    final rows = await db.query(table,
        columns: ['uuid'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first['uuid'] as String?;
  }

  Future<Map<String, Object?>?> _rowOf(String table, int id) async {
    final db = await database;
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  /// Empties the cache, without touching the server.
  ///
  /// Used on sign-out: this holds one account's trips, and leaving them for
  /// whoever signs in next would be both confusing and a small privacy leak.
  Future<void> clearCache() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in remoteTables.reversed) {
        await txn.delete(table.name);
      }
      await txn.delete(tableDocument);
    });
  }

  /// Replaces the cache with what the server holds.
  ///
  /// The server is the source of truth, so this is a straight overwrite rather
  /// than a merge — there is nothing to reconcile, because nothing is ever
  /// written here that the server did not already accept.
  ///
  /// Parents before children, so a row's foreign key resolves as it lands.
  Future<void> refreshFromServer() async {
    final store = remote;
    if (store == null) return;

    final db = await database;
    final fetched = <String, List<Map<String, Object?>>>{};
    for (final table in remoteTables) {
      fetched[table.name] = await store.fetchAll(table.name);
    }

    // Everything arrived before anything is dropped: a failure halfway through
    // must not leave the phone with less than it started with.
    await db.transaction((txn) async {
      for (final table in remoteTables.reversed) {
        await txn.delete(table.name);
      }
      final idsByUuid = <String, Map<String, int>>{};
      for (final table in remoteTables) {
        final localIds = <String, int>{};
        for (final row in fetched[table.name]!) {
          final values = <String, Object?>{};
          for (final entry in row.entries) {
            if (entry.key == table.parentWireColumn) continue;
            if (entry.key == 'userId') continue;
            if (entry.key.endsWith('At') && entry.value == null) continue;
            values[entry.key] = entry.value;
          }
          if (table.hasParent) {
            final parentUuid = row[table.parentWireColumn!] as String?;
            final parentId = idsByUuid[table.parentTable!]?[parentUuid];
            // Orphaned by a parent the server did not return: skip it rather
            // than fail the whole refresh.
            if (parentId == null) continue;
            values[table.parentColumn!] = parentId;
          }
          final id = await txn.insert(table.name, values);
          localIds[row['uuid'] as String] = id;
        }
        idsByUuid[table.name] = localIds;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Trip CRUD
  // ---------------------------------------------------------------------------

  Future<Trip> createTrip(Trip trip) async {
    final id = await _insertRow(tableTrip, trip.toMap()..remove('id'));
    return trip.copyWith(id: id);
  }

  Future<List<Trip>> getTrips() async {
    final db = await database;
    final maps = await db.query(tableTrip, orderBy: 'startDate ASC');
    return maps.map(Trip.fromMap).toList();
  }

  Future<Trip?> getTrip(int id) async {
    final db = await database;
    final maps =
        await db.query(tableTrip, where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Trip.fromMap(maps.first);
  }

  Future<int> updateTrip(Trip trip) async {
    return _updateRow(tableTrip, trip.toMap(), trip.id!);
  }

  Future<int> deleteTrip(int id) async {
    return _deleteRow(tableTrip, id);
  }

  // ---------------------------------------------------------------------------
  // Stay CRUD
  // ---------------------------------------------------------------------------

  Future<Stay> createStay(Stay stay) async {
    final id = await _insertRow(tableStay, stay.toMap()..remove('id'));
    return stay.copyWith(id: id);
  }

  Future<List<Stay>> getStaysForTrip(int tripId) async {
    final db = await database;
    final maps = await db.query(tableStay,
        where: 'tripId = ?', whereArgs: [tripId], orderBy: 'checkOutAt ASC');
    return maps.map(Stay.fromMap).toList();
  }

  Future<Stay?> getStay(int id) async {
    final db = await database;
    final maps =
        await db.query(tableStay, where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return Stay.fromMap(maps.first);
  }

  Future<int> updateStay(Stay stay) async {
    return _updateRow(tableStay, stay.toMap(), stay.id!);
  }

  Future<int> deleteStay(int id) async {
    return _deleteRow(tableStay, id);
  }

  // ---------------------------------------------------------------------------
  // TransportLeg CRUD
  // ---------------------------------------------------------------------------

  Future<TransportLeg> createTransportLeg(TransportLeg leg) async {
    final id = await _insertRow(tableTransport, leg.toMap()..remove('id'));
    return leg.copyWith(id: id);
  }

  Future<List<TransportLeg>> getTransportLegsForTrip(int tripId) async {
    final db = await database;
    final maps = await db.query(tableTransport,
        where: 'tripId = ?', whereArgs: [tripId], orderBy: 'departureAt ASC');
    return maps.map(TransportLeg.fromMap).toList();
  }

  Future<TransportLeg?> getTransportLeg(int id) async {
    final db = await database;
    final maps = await db
        .query(tableTransport, where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return TransportLeg.fromMap(maps.first);
  }

  Future<int> updateTransportLeg(TransportLeg leg) async {
    return _updateRow(tableTransport, leg.toMap(), leg.id!);
  }

  Future<int> deleteTransportLeg(int id) async {
    return _deleteRow(tableTransport, id);
  }

  // ---------------------------------------------------------------------------
  // Item CRUD
  // ---------------------------------------------------------------------------

  Future<Item> createItem(Item item) async {
    final id = await _insertRow(tableItem, item.toMap()..remove('id'));
    return item.copyWith(id: id);
  }

  Future<List<Item>> getItemsForTrip(int tripId) async {
    final db = await database;
    final maps = await db.query(tableItem,
        where: 'tripId = ?', whereArgs: [tripId], orderBy: 'id ASC');
    return maps.map(Item.fromMap).toList();
  }

  /// Every unpacked item on the trip. Since items are never hotel-specific,
  /// this is also the list behind a checkout reminder for any single stay.
  Future<List<Item>> getUnpackedItemsForTrip(int tripId) async {
    final db = await database;
    final maps = await db.query(
      tableItem,
      where: 'tripId = ? AND packed = 0',
      whereArgs: [tripId],
      orderBy: 'id ASC',
    );
    return maps.map(Item.fromMap).toList();
  }

  Future<int> updateItem(Item item) async {
    return _updateRow(tableItem, item.toMap(), item.id!);
  }

  Future<int> setItemPacked(int id, bool packed) async {
    return _updateRow(tableItem, {'packed': packed ? 1 : 0}, id);
  }

  /// Sets how many of [id] to bring. Never drops below one — removing the last
  /// one means deleting the item, not owning zero of it.
  Future<int> setItemQuantity(int id, int quantity) async {
    return _updateRow(tableItem, {'quantity': quantity < 1 ? 1 : quantity}, id);
  }

  /// Packs or unpacks every item on a trip, or just one category of it.
  /// Returns the number of rows changed.
  Future<int> setAllItemsPacked(
    int tripId,
    bool packed, {
    ItemCategory? category,
  }) async {
    final db = await database;

    // Locally this is one statement. The server has no bulk verb, so with a
    // remote attached each row goes up individually — a packing list is tens
    // of rows, not thousands, and correctness beats a round trip saved.
    if (remote != null) {
      final affected = await db.query(
        tableItem,
        columns: ['id'],
        where: category == null ? 'tripId = ?' : 'tripId = ? AND category = ?',
        whereArgs: category == null ? [tripId] : [tripId, category.name],
      );
      for (final row in affected) {
        await _updateRow(tableItem, {'packed': packed ? 1 : 0}, row['id'] as int);
      }
      return affected.length;
    }

    return db.update(
      tableItem,
      _stampChanged({'packed': packed ? 1 : 0}),
      where: category == null
          ? 'tripId = ?'
          : 'tripId = ? AND category = ?',
      whereArgs: category == null ? [tripId] : [tripId, category.name],
    );
  }

  Future<int> deleteItem(int id) async {
    return _deleteRow(tableItem, id);
  }

  // ---------------------------------------------------------------------------
  // Saved packing lists
  // ---------------------------------------------------------------------------

  /// Saves [items] as a reusable list called [name]. Packed state is dropped —
  /// a saved list is what to bring, not how far along you were.
  Future<PackingList> savePackingList(String name, List<Item> items) async {
    final list = PackingList(name: name, createdAt: DateTime.now());

    // Deliberately not a transaction once a remote is attached: each row has
    // to reach the server, and a rolled-back local transaction would not undo
    // what was already accepted there.
    final listId = await _insertRow(
      tablePackingList,
      list.toMap()..remove('id'),
    );
    for (final item in items) {
      await _insertRow(tablePackingListItem, {
        'listId': listId,
        'name': item.name,
        'category': item.category.name,
        'quantity': item.quantity,
      });
    }
    return list.copyWith(id: listId, itemCount: items.length);
  }

  /// Every saved list, newest first, each carrying its entry count.
  Future<List<PackingList>> getPackingLists() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, COUNT(i.id) AS itemCount
      FROM $tablePackingList l
      LEFT JOIN $tablePackingListItem i ON i.listId = l.id
      GROUP BY l.id
      -- id breaks ties: two lists saved in the same millisecond would
      -- otherwise come back in whatever order SQLite felt like.
      ORDER BY l.createdAt DESC, l.id DESC
    ''');
    return maps.map(PackingList.fromMap).toList();
  }

  /// Starts an empty list, to be filled in item by item.
  Future<PackingList> createPackingList(String name) async {
    final list = PackingList(name: name, createdAt: DateTime.now());
    final id = await _insertRow(tablePackingList, list.toMap()..remove('id'));
    return list.copyWith(id: id);
  }

  Future<int> renamePackingList(int id, String name) async {
    return _updateRow(tablePackingList, {'name': name}, id);
  }

  Future<PackingList?> getPackingList(int id) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT l.*, COUNT(i.id) AS itemCount
      FROM $tablePackingList l
      LEFT JOIN $tablePackingListItem i ON i.listId = l.id
      WHERE l.id = ?
      GROUP BY l.id
    ''', [id]);
    if (maps.isEmpty) return null;
    return PackingList.fromMap(maps.first);
  }

  Future<PackingListEntry> addPackingListEntry(PackingListEntry entry) async {
    final id = await _insertRow(
      tablePackingListItem,
      entry.toMap()..remove('id'),
    );
    return entry.copyWith(id: id);
  }

  Future<int> updatePackingListEntry(PackingListEntry entry) async {
    return _updateRow(tablePackingListItem, entry.toMap(), entry.id!);
  }

  /// Same floor as trip items: one is the minimum, deleting is how you get to
  /// none.
  Future<int> setPackingListEntryQuantity(int id, int quantity) async {
    return _updateRow(
      tablePackingListItem,
      {'quantity': quantity < 1 ? 1 : quantity},
      id,
    );
  }

  Future<int> deletePackingListEntry(int id) async {
    return _deleteRow(tablePackingListItem, id);
  }

  Future<List<PackingListEntry>> getPackingListEntries(int listId) async {
    final db = await database;
    final maps = await db.query(tablePackingListItem,
        where: 'listId = ?', whereArgs: [listId], orderBy: 'id ASC');
    return maps.map(PackingListEntry.fromMap).toList();
  }

  Future<int> deletePackingList(int id) async {
    return _deleteRow(tablePackingList, id);
  }

  /// Copies a saved list onto a trip as unpacked items, skipping anything the
  /// trip already has under the same name and category (case-insensitive), so
  /// applying a list twice doesn't duplicate the whole thing.
  ///
  /// Returns how many items were actually added.
  Future<int> applyPackingListToTrip(int listId, int tripId) async {
    final entries = await getPackingListEntries(listId);
    if (entries.isEmpty) return 0;

    final existing = await getItemsForTrip(tripId);
    final seen = existing
        .map((i) => '${i.name.toLowerCase()}|${i.category.name}')
        .toSet();

    var added = 0;
    for (final entry in entries) {
      final key = '${entry.name.toLowerCase()}|${entry.category.name}';
      if (!seen.add(key)) continue;
      // Row by row rather than a batch: each has to reach the server too.
      await _insertRow(tableItem, {
        'tripId': tripId,
        'name': entry.name,
        'category': entry.category.name,
        'quantity': entry.quantity,
        'packed': 0,
      });
      added++;
    }
    return added;
  }

  // ---------------------------------------------------------------------------
  // Document CRUD
  // ---------------------------------------------------------------------------

  Future<Document> createDocument(Document document) async {
    final id = await _insertRow(tableDocument, document.toMap()..remove('id'));
    return document.copyWith(id: id);
  }

  Future<List<Document>> getDocumentsForTrip(int tripId) async {
    final db = await database;
    final maps = await db.query(tableDocument,
        where: 'tripId = ?', whereArgs: [tripId], orderBy: 'id ASC');
    return maps.map(Document.fromMap).toList();
  }

  Future<int> updateDocument(Document document) async {
    return _updateRow(tableDocument, document.toMap(), document.id!);
  }

  Future<int> deleteDocument(int id) async {
    return _deleteRow(tableDocument, id);
  }
}
