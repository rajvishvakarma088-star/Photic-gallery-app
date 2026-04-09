import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

class ThumbnailDiskCache {
  ThumbnailDiskCache._();

  static final ThumbnailDiskCache instance = ThumbnailDiskCache._();

  static const String _dirName = 'thumb_cache_v1';
  static const int _maxFiles = 8000;
  static const int _maxBytes = 200 << 20; // 200MB
  static const Duration _minPruneInterval = Duration(minutes: 2);

  String? _dirPath;
  Future<void>? _ensureFuture;

  bool _isPruning = false;
  DateTime _lastPruneAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, Future<File?>> _inflight = <String, Future<File?>>{};

  bool get isReady => _dirPath != null;

  Future<void> ensureReady() {
    final existing = _ensureFuture;
    if (existing != null) return existing;
    final future = _init();
    _ensureFuture = future;
    return future;
  }

  Future<void> _init() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _dirName));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _dirPath = dir.path;
  }

  File? cachedFileSync(String assetId, int thumbPx) {
    final dirPath = _dirPath;
    if (dirPath == null) return null;
    final file = File(_filePath(dirPath, assetId, thumbPx));
    return file.existsSync() ? file : null;
  }

  Future<File?> prefetch(AssetEntity asset, int thumbPx) async {
    await ensureReady();
    final dirPath = _dirPath;
    if (dirPath == null) return null;

    final key = '${asset.id}@$thumbPx';
    final existingInflight = _inflight[key];
    if (existingInflight != null) return existingInflight;

    final future = _prefetchInternal(dirPath, asset, thumbPx);
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  Future<void> prefetchMany(
    List<AssetEntity> assets,
    int thumbPx, {
    int maxCount = 96,
    int concurrency = 4,
  }) async {
    if (assets.isEmpty) return;
    await ensureReady();

    final capped = assets.length < maxCount ? assets.length : maxCount;
    final running = <Future<void>>{};

    for (var i = 0; i < capped; i++) {
      final task = prefetch(assets[i], thumbPx).then((_) {});
      running.add(task);
      task.whenComplete(() => running.remove(task));
      if (running.length >= concurrency) {
        await Future.any(running);
      }
    }

    if (running.isNotEmpty) {
      await Future.wait(running);
    }
  }

  Future<File?> _prefetchInternal(
    String dirPath,
    AssetEntity asset,
    int thumbPx,
  ) async {
    final file = File(_filePath(dirPath, asset.id, thumbPx));
    if (file.existsSync()) return file;

    final data = await asset.thumbnailDataWithSize(
      ThumbnailSize.square(thumbPx),
    );
    if (data == null || data.isEmpty) return null;

    try {
      await file.writeAsBytes(data, flush: false);
    } catch (_) {
      return null;
    }

    _maybeSchedulePrune(dirPath);
    return file;
  }

  String _filePath(String dirPath, String assetId, int thumbPx) {
    // Asset id is safe as filename on Android/iOS in practice; still strip
    // path separators defensively.
    final safeId = assetId.replaceAll(RegExp(r'[/\\\\]'), '_');
    return p.join(dirPath, '${safeId}_$thumbPx.jpg');
  }

  void _maybeSchedulePrune(String dirPath) {
    if (_isPruning) return;
    final now = DateTime.now();
    if (now.difference(_lastPruneAt) < _minPruneInterval) return;

    _isPruning = true;
    _lastPruneAt = now;
    scheduleMicrotask(() async {
      try {
        await _prune(dirPath);
      } finally {
        _isPruning = false;
      }
    });
  }

  Future<void> _prune(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    final files = <FileSystemEntity>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    if (files.length <= _maxFiles) {
      final total = await _totalBytes(files);
      if (total <= _maxBytes) return;
    }

    final stats = <({File file, DateTime modified, int size})>[];
    for (final entity in files) {
      final file = File(entity.path);
      try {
        final s = await file.stat();
        stats.add((file: file, modified: s.modified, size: s.size));
      } catch (_) {}
    }

    stats.sort((a, b) => a.modified.compareTo(b.modified));
    var totalBytes = stats.fold<int>(0, (sum, e) => sum + e.size);

    var idx = 0;
    while ((stats.length - idx) > _maxFiles || totalBytes > _maxBytes) {
      if (idx >= stats.length) break;
      final entry = stats[idx];
      idx++;
      totalBytes -= entry.size;
      try {
        await entry.file.delete();
      } catch (_) {}
    }
  }

  Future<int> _totalBytes(List<FileSystemEntity> entities) async {
    var total = 0;
    for (final entity in entities) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } catch (_) {}
    }
    return total;
  }
}
