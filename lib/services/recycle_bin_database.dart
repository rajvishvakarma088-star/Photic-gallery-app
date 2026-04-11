import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite/sqflite.dart';

class RecycleBinItem {
  RecycleBinItem({
    required this.assetId,
    required this.filePath,
    required this.deletedAt,
  });

  final String assetId;
  final String filePath;
  final DateTime deletedAt;

  factory RecycleBinItem.fromMap(Map<String, Object?> map) {
    return RecycleBinItem(
      assetId: map['asset_id'] as String,
      filePath: map['file_path'] as String? ?? '',
      deletedAt:
          DateTime.tryParse(map['deleted_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class RecycleBinDatabase {
  RecycleBinDatabase._();

  static final RecycleBinDatabase instance = RecycleBinDatabase._();

  static const _databaseName = 'recycle_bin.db';
  static const _databaseVersion = 2;
  static const _recycleBinTable = 'recycle_bin_items';

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
        await _ensureSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureSchema(db);
      },
      onOpen: (db) async {
        await _ensureSchema(db);
      },
    );
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_recycleBinTable (
        asset_id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');

    final columns = await db.rawQuery('PRAGMA table_info($_recycleBinTable)');
    final hasFilePath = columns.any((column) => column['name'] == 'file_path');
    if (!hasFilePath) {
      await db.execute(
        'ALTER TABLE $_recycleBinTable ADD COLUMN file_path TEXT NOT NULL DEFAULT \'\'',
      );
    }
  }

  Future<List<RecycleBinItem>> loadItems() async {
    final db = await database;
    final rows = await db.query(
      _recycleBinTable,
      orderBy: 'deleted_at DESC',
    );

    return rows.map(RecycleBinItem.fromMap).toList(growable: false);
  }

  Future<Set<String>> loadAssetIds() async {
    final items = await loadItems();
    return items.map((item) => item.assetId).toSet();
  }

  Future<void> addAsset(AssetEntity asset) async {
    await addAssets([asset]);
  }

  Future<void> addAssets(Iterable<AssetEntity> assets) async {
    final uniqueAssets = <String, AssetEntity>{};
    for (final asset in assets) {
      uniqueAssets[asset.id] = asset;
    }
    if (uniqueAssets.isEmpty) return;

    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (final asset in uniqueAssets.values) {
      final file = await asset.file;
      batch.insert(
        _recycleBinTable,
        {
          'asset_id': asset.id,
          'file_path': file?.path ?? '',
          'deleted_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> removeAssets(Iterable<String> assetIds) async {
    final ids = assetIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;

    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.delete(
      _recycleBinTable,
      where: 'asset_id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_recycleBinTable);
  }
}
