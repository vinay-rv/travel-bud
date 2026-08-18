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
  // Trip CRUD
  // ---------------------------------------------------------------------------

  Future<Trip> createTrip(Trip trip) async {
    final db = await database;
    final id = await db.insert(tableTrip, _stampNew(trip.toMap()..remove('id')));
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
    final db = await database;
    return db.update(tableTrip, _stampChanged(trip.toMap()),
        where: 'id = ?', whereArgs: [trip.id]);
  }

  Future<int> deleteTrip(int id) async {
    final db = await database;
    return db.delete(tableTrip, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Stay CRUD
  // ---------------------------------------------------------------------------

  Future<Stay> createStay(Stay stay) async {
    final db = await database;
    final id = await db.insert(tableStay, _stampNew(stay.toMap()..remove('id')));
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
    final db = await database;
    return db.update(tableStay, _stampChanged(stay.toMap()),
        where: 'id = ?', whereArgs: [stay.id]);
  }

  Future<int> deleteStay(int id) async {
    final db = await database;
    return db.delete(tableStay, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // TransportLeg CRUD
  // ---------------------------------------------------------------------------

  Future<TransportLeg> createTransportLeg(TransportLeg leg) async {
    final db = await database;
    final id = await db.insert(tableTransport, _stampNew(leg.toMap()..remove('id')));
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
    final db = await database;
    return db.update(tableTransport, _stampChanged(leg.toMap()),
        where: 'id = ?', whereArgs: [leg.id]);
  }

  Future<int> deleteTransportLeg(int id) async {
    final db = await database;
    return db.delete(tableTransport, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Item CRUD
  // ---------------------------------------------------------------------------

  Future<Item> createItem(Item item) async {
    final db = await database;
    final id = await db.insert(tableItem, _stampNew(item.toMap()..remove('id')));
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
    final db = await database;
    return db.update(tableItem, _stampChanged(item.toMap()),
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> setItemPacked(int id, bool packed) async {
    final db = await database;
    return db.update(tableItem, _stampChanged({'packed': packed ? 1 : 0}),
        where: 'id = ?', whereArgs: [id]);
  }

  /// Sets how many of [id] to bring. Never drops below one — removing the last
  /// one means deleting the item, not owning zero of it.
  Future<int> setItemQuantity(int id, int quantity) async {
    final db = await database;
    return db.update(tableItem, _stampChanged({'quantity': quantity < 1 ? 1 : quantity}),
        where: 'id = ?', whereArgs: [id]);
  }

  /// Packs or unpacks every item on a trip, or just one category of it.
  /// Returns the number of rows changed.
  Future<int> setAllItemsPacked(
    int tripId,
    bool packed, {
    ItemCategory? category,
  }) async {
    final db = await database;
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
    final db = await database;
    return db.delete(tableItem, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Saved packing lists
  // ---------------------------------------------------------------------------

  /// Saves [items] as a reusable list called [name]. Packed state is dropped —
  /// a saved list is what to bring, not how far along you were.
  Future<PackingList> savePackingList(String name, List<Item> items) async {
    final db = await database;
    final list = PackingList(name: name, createdAt: DateTime.now());

    return db.transaction((txn) async {
      final listId = await txn.insert(
        tablePackingList,
        _stampNew(list.toMap()..remove('id')),
      );
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          tablePackingListItem,
          _stampNew({
            'listId': listId,
            'name': item.name,
            'category': item.category.name,
            'quantity': item.quantity,
          }),
        );
      }
      await batch.commit(noResult: true);
      return list.copyWith(id: listId, itemCount: items.length);
    });
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
    final db = await database;
    final list = PackingList(name: name, createdAt: DateTime.now());
    final id = await db.insert(tablePackingList, _stampNew(list.toMap()..remove('id')));
    return list.copyWith(id: id);
  }

  Future<int> renamePackingList(int id, String name) async {
    final db = await database;
    return db.update(tablePackingList, _stampChanged({'name': name}),
        where: 'id = ?', whereArgs: [id]);
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
    final db = await database;
    final id = await db.insert(
      tablePackingListItem,
      _stampNew(entry.toMap()..remove('id')),
    );
    return entry.copyWith(id: id);
  }

  Future<int> updatePackingListEntry(PackingListEntry entry) async {
    final db = await database;
    return db.update(tablePackingListItem, _stampChanged(entry.toMap()),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  /// Same floor as trip items: one is the minimum, deleting is how you get to
  /// none.
  Future<int> setPackingListEntryQuantity(int id, int quantity) async {
    final db = await database;
    return db.update(
      tablePackingListItem,
      _stampChanged({'quantity': quantity < 1 ? 1 : quantity}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePackingListEntry(int id) async {
    final db = await database;
    return db.delete(tablePackingListItem, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PackingListEntry>> getPackingListEntries(int listId) async {
    final db = await database;
    final maps = await db.query(tablePackingListItem,
        where: 'listId = ?', whereArgs: [listId], orderBy: 'id ASC');
    return maps.map(PackingListEntry.fromMap).toList();
  }

  Future<int> deletePackingList(int id) async {
    final db = await database;
    return db.delete(tablePackingList, where: 'id = ?', whereArgs: [id]);
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

    final db = await database;
    var added = 0;
    final batch = db.batch();
    for (final entry in entries) {
      final key = '${entry.name.toLowerCase()}|${entry.category.name}';
      if (!seen.add(key)) continue;
      batch.insert(
        tableItem,
        _stampNew({
          'tripId': tripId,
          'name': entry.name,
          'category': entry.category.name,
          'quantity': entry.quantity,
          'packed': 0,
        }),
      );
      added++;
    }
    await batch.commit(noResult: true);
    return added;
  }

  // ---------------------------------------------------------------------------
  // Document CRUD
  // ---------------------------------------------------------------------------

  Future<Document> createDocument(Document document) async {
    final db = await database;
    final id = await db.insert(tableDocument, _stampNew(document.toMap()..remove('id')));
    return document.copyWith(id: id);
  }

  Future<List<Document>> getDocumentsForTrip(int tripId) async {
    final db = await database;
    final maps = await db.query(tableDocument,
        where: 'tripId = ?', whereArgs: [tripId], orderBy: 'id ASC');
    return maps.map(Document.fromMap).toList();
  }

  Future<int> updateDocument(Document document) async {
    final db = await database;
    return db.update(tableDocument, _stampChanged(document.toMap()),
        where: 'id = ?', whereArgs: [document.id]);
  }

  Future<int> deleteDocument(int id) async {
    final db = await database;
    return db.delete(tableDocument, where: 'id = ?', whereArgs: [id]);
  }
}
