import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

enum VaultMediaType { photo, video }

class VaultItem {
  VaultItem({
    required this.id,
    required this.fileName,
    required this.vaultPath,
    required this.originalPath,
    required this.originalRelativePath,
    required this.mediaType,
    required this.createdAt,
  });

  final int? id;
  final String fileName;
  final String vaultPath;
  final String originalPath;
  final String originalRelativePath;
  final VaultMediaType mediaType;
  final DateTime createdAt;

  bool get exists => File(vaultPath).existsSync();

  factory VaultItem.fromMap(Map<String, Object?> map) {
    return VaultItem(
      id: map['id'] as int?,
      fileName:
          map['file_name'] as String? ??
          path.basename(map['vault_path'] as String? ?? ''),
      vaultPath: map['vault_path'] as String? ?? '',
      originalPath: map['original_path'] as String? ?? '',
      originalRelativePath: map['original_relative_path'] as String? ?? '',
      mediaType: (map['media_type'] as String? ?? 'photo') == 'video'
          ? VaultMediaType.video
          : VaultMediaType.photo,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'file_name': fileName,
      'vault_path': vaultPath,
      'original_path': originalPath,
      'original_relative_path': originalRelativePath,
      'media_type': mediaType == VaultMediaType.video ? 'video' : 'photo',
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class VaultDatabase {
  VaultDatabase._();

  static final VaultDatabase instance = VaultDatabase._();

  static const _databaseName = 'vault_items.db';
  static const _databaseVersion = 1;
  static const _vaultTable = 'vault_items';

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
          CREATE TABLE $_vaultTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_name TEXT NOT NULL,
            vault_path TEXT NOT NULL,
            original_path TEXT NOT NULL,
            original_relative_path TEXT NOT NULL DEFAULT '',
            media_type TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<List<VaultItem>> loadItems() async {
    final db = await database;
    final rows = await db.query(_vaultTable, orderBy: 'created_at DESC');
    return rows.map(VaultItem.fromMap).toList(growable: false);
  }

  Future<VaultItem> addItem(VaultItem item) async {
    final db = await database;
    final id = await db.insert(
      _vaultTable,
      item.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return VaultItem(
      id: id,
      fileName: item.fileName,
      vaultPath: item.vaultPath,
      originalPath: item.originalPath,
      originalRelativePath: item.originalRelativePath,
      mediaType: item.mediaType,
      createdAt: item.createdAt,
    );
  }

  Future<void> removeItem(int id) async {
    final db = await database;
    await db.delete(_vaultTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete(_vaultTable);
  }
}
