import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class FavoritesDatabase {
  FavoritesDatabase._();

  static final FavoritesDatabase instance = FavoritesDatabase._();

  static const _databaseName = 'gallery_app.db';
  static const _databaseVersion = 1;
  static const _favoritesTable = 'favorite_images';

  Database? _database;

  Future<Database> get database async {
    final cached = _database;
    if (cached != null) return cached;

    final db = await _openDatabase();
    _database = db;
    return db;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = path.join(databasesPath, _databaseName);

    return openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_favoritesTable (
            asset_id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<Set<String>> loadFavoriteIds() async {
    final db = await database;
    final rows = await db.query(
      _favoritesTable,
      columns: ['asset_id'],
      orderBy: 'created_at DESC',
    );

    return rows
        .map((row) => row['asset_id'])
        .whereType<String>()
        .toSet();
  }

  Future<void> addFavorite(String assetId) async {
    final db = await database;
    await db.insert(
      _favoritesTable,
      {
        'asset_id': assetId,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavorite(String assetId) async {
    final db = await database;
    await db.delete(
      _favoritesTable,
      where: 'asset_id = ?',
      whereArgs: [assetId],
    );
  }

  Future<bool> isFavorite(String assetId) async {
    final db = await database;
    final rows = await db.query(
      _favoritesTable,
      columns: ['asset_id'],
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
