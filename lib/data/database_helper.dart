import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/trip.dart';
import '../models/stay.dart';
import '../models/transport_leg.dart';
import '../models/item.dart';
import '../models/document.dart';

/// Single point of access to the on-device SQLite database. Owns the schema,
/// the connection, and CRUD for all five tables. No network, no auth.
///
/// Use [DatabaseHelper.instance] everywhere. For tests, call
/// [DatabaseHelper.forTesting] with an in-memory path.
class DatabaseHelper {
  static const _dbName = 'trip_inventory.db';
  static const _dbVersion = 1;

  static const tableTrip = 'trips';
  static const tableStay = 'stays';
  static const tableTransport = 'transport_legs';
  static const tableItem = 'items';
  static const tableDocument = 'documents';

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
      },
      onCreate: _createSchema,
    );
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

    await db.execute('''
      CREATE TABLE $tableItem (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        stayId INTEGER,
        name TEXT NOT NULL,
        packed INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (tripId) REFERENCES $tableTrip (id) ON DELETE CASCADE,
        FOREIGN KEY (stayId) REFERENCES $tableStay (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableDocument (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tripId INTEGER NOT NULL,
        photoPath TEXT NOT NULL,
        label TEXT NOT NULL,
        FOREIGN KEY (tripId) REFERENCES $tableTrip (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ---------------------------------------------------------------------------
  // Trip CRUD
  // ---------------------------------------------------------------------------

  Future<Trip> createTrip(Trip trip) async {
    final db = await database;
    final id = await db.insert(tableTrip, trip.toMap()..remove('id'));
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
    return db.update(tableTrip, trip.toMap(),
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
    final id = await db.insert(tableStay, stay.toMap()..remove('id'));
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
    return db.update(tableStay, stay.toMap(),
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
    final id = await db.insert(tableTransport, leg.toMap()..remove('id'));
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
    return db.update(tableTransport, leg.toMap(),
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
    final id = await db.insert(tableItem, item.toMap()..remove('id'));
    return item.copyWith(id: id);
  }

  Future<List<Item>> getItemsForTrip(int tripId) async {
    final db = await database;
    final maps = await db.query(tableItem,
        where: 'tripId = ?', whereArgs: [tripId], orderBy: 'id ASC');
    return maps.map(Item.fromMap).toList();
  }

  /// Items scoped to a specific stay only (excludes whole-trip items).
  Future<List<Item>> getItemsForStay(int stayId) async {
    final db = await database;
    final maps = await db.query(tableItem,
        where: 'stayId = ?', whereArgs: [stayId], orderBy: 'id ASC');
    return maps.map(Item.fromMap).toList();
  }

  /// Unpacked items relevant to a notification for a stay: whole-trip items
  /// (stayId IS NULL) plus items tied to this stay. Used to build reminder text.
  Future<List<Item>> getUnpackedItemsForStay(int tripId, int stayId) async {
    final db = await database;
    final maps = await db.query(
      tableItem,
      where: 'tripId = ? AND packed = 0 AND (stayId IS NULL OR stayId = ?)',
      whereArgs: [tripId, stayId],
      orderBy: 'id ASC',
    );
    return maps.map(Item.fromMap).toList();
  }

  /// Unpacked items for a whole-trip reminder (e.g. a transport leg): every
  /// unpacked item on the trip regardless of stay assignment.
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
    return db.update(tableItem, item.toMap(),
        where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> setItemPacked(int id, bool packed) async {
    final db = await database;
    return db.update(tableItem, {'packed': packed ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return db.delete(tableItem, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Document CRUD
  // ---------------------------------------------------------------------------

  Future<Document> createDocument(Document document) async {
    final db = await database;
    final id = await db.insert(tableDocument, document.toMap()..remove('id'));
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
    return db.update(tableDocument, document.toMap(),
        where: 'id = ?', whereArgs: [document.id]);
  }

  Future<int> deleteDocument(int id) async {
    final db = await database;
    return db.delete(tableDocument, where: 'id = ?', whereArgs: [id]);
  }
}
