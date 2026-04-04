import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

class MusicFile {
  final String id;
  final String name;
  final String path;
  final Duration duration;
  final DateTime modified;
  final int sizeBytes;
  final String? albumArtPath; 
  final Uint8List? albumArtBytes;
  final AssetEntity? asset; 

  Uint8List? _cachedArt; 
  Future<Uint8List?>? _thumbnailFuture;
  Future<Uint8List?>? _artFuture;

  MusicFile({
    required this.id,
    required this.name,
    required this.path,
    required this.duration,
    required this.modified,
    required this.sizeBytes,
    this.albumArtPath,
    this.albumArtBytes,
    this.asset,
  });

  String get displayName {
    // Remove extension from name
    return name.replaceAll(RegExp(r'\.(mp3|wav|m4a|aac|ogg|flac|opus)$', caseSensitive: false), '');
  }

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Consistent app theme color for all songs
  Color get themeColor {
    return const Color(0xFF6366F1); // Indigo - consistent app theme
  }

  /// Get gradient colors for the thumbnail - uses consistent theme
  List<Color> get thumbnailGradient {
    return [
      themeColor,
      themeColor.withOpacity(0.7),
    ];
  }

  /// Check if album art image exists
  bool get hasAlbumArt => albumArtBytes != null || (albumArtPath != null && File(albumArtPath!).existsSync());

  /// Lazy load thumbnail from AssetEntity with ID3 fallback
  Future<Uint8List?> getThumbnail() {
    if (_thumbnailFuture != null) return _thumbnailFuture!;
    _thumbnailFuture = _fetchThumbnailInternal();
    return _thumbnailFuture!;
  }

  Future<Uint8List?> _fetchThumbnailInternal() async {
    if (albumArtBytes != null) return albumArtBytes;
    if (_cachedArt != null) return _cachedArt;
    
    // Try PhotoManager thumbnail first (fast)
    if (asset != null) {
      try {
        final data = await asset!.thumbnailDataWithSize(const ThumbnailSize(150, 150));
        if (data != null) {
          _cachedArt = data;
          return data;
        }
      } catch (_) {}
    }

    // Try embedded art (lazy)
    return await fetchAlbumArt();
  }

  /// High-resolution album art fetcher
  Future<Uint8List?> fetchAlbumArt() {
    if (_artFuture != null) return _artFuture!;
    _artFuture = _fetchAlbumArtInternal();
    return _artFuture!;
  }

  Future<Uint8List?> _fetchAlbumArtInternal() async {
    if (albumArtBytes != null) return albumArtBytes;
    if (_cachedArt != null) return _cachedArt;
    
    try {
      // 1. Try local file if path exists
      if (albumArtPath != null) {
        final file = File(albumArtPath!);
        if (await file.exists()) {
          _cachedArt = await file.readAsBytes();
          return _cachedArt;
        }
      }

      // 2. Try embedded metadata
      final file = File(path);
      if (await file.exists()) {
        final metadata = await MetadataRetriever.fromFile(file);
        if (metadata.albumArt != null) {
          _cachedArt = metadata.albumArt;
          return _cachedArt;
        }
      }
    } catch (e) {
      print('Error fetching album art for $name: $e');
    }
    return null;
  }
}

class MusicService {
  static final MusicService _instance = MusicService._internal();

  factory MusicService() {
    return _instance;
  }

  MusicService._internal();

  AssetPathEntity? _audioPathCache;
  final List<MusicFile> _musicCache = [];
  bool _hasScannedAll = false;
  int _currentLoadPage = 0;
  static const int pageSize = 50;
  final Set<String> _binnedIds = {}; // IDs to exclude (moved to bin)

  void setBinnedIds(Set<String> ids) {
    _binnedIds.clear();
    _binnedIds.addAll(ids);
  }

  final List<String> _supportedExtensions = ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'opus'];

  List<MusicFile> get musicCache => _musicCache;

  void clearCache() {
    _musicCache.clear();
    _audioPathCache = null;
    _hasScannedAll = false;
    _currentLoadPage = 0;
  }

  Future<bool> requestMusicPermission() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    return ps.hasAccess;
  }

  /// Find album art image in the same directory as the music file
  String? _findAlbumArtSync(String musicFilePath) {
    final musicFile = File(musicFilePath);
    final directory = musicFile.parent;
    
    // Common album art file names to check (exact matches)
    final imageNames = [
      'cover.jpg', 'cover.png', 'album.jpg', 'album.png',
      'folder.jpg', 'folder.png', 'art.jpg', 'art.png',
      'front.jpg', 'front.png', 'Cover.jpg', 'Cover.png',
      'Album.jpg', 'Album.png', 'Folder.jpg', 'Folder.png',
    ];
    
    try {
      for (final imageName in imageNames) {
        final imagePath = '${directory.path}/$imageName';
        if (FileSystemEntity.isFileSync(imagePath)) {
          return imagePath;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<AssetPathEntity?> _getAudioPath() async {
    if (_audioPathCache != null) return _audioPathCache;

    final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
      type: RequestType.audio,
      hasAll: true,
      filterOption: FilterOptionGroup(
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
          OrderOption(type: OrderOptionType.updateDate, asc: false),
        ],
      ),
    );

    if (paths.isEmpty) return null;
    _audioPathCache = paths.firstWhere((p) => p.isAll, orElse: () => paths.first);
    return _audioPathCache;
  }

  Future<List<MusicFile>> fetchMusicsPaged({bool refresh = false}) async {
    if (refresh) clearCache();
    
    if (_hasScannedAll) return _musicCache;

    final path = await _getAudioPath();
    if (path == null) return [];

    final assets = await path.getAssetListPaged(page: _currentLoadPage, size: pageSize);
    if (assets.isEmpty) {
      _hasScannedAll = true;
      return _musicCache;
    }

    final List<MusicFile> newFiles = [];
    for (final asset in assets) {
      if (_binnedIds.contains(asset.id)) continue; // Skip binned items
      
      final file = await asset.file;
      if (file == null) continue;

      // Small optimization: look for local art files during discovery
      final localArtPath = _findAlbumArtSync(file.path);

      newFiles.add(MusicFile(
        id: asset.id,
        name: asset.title ?? file.path.split('/').last,
        path: file.path,
        duration: asset.videoDuration,
        modified: asset.modifiedDateTime,
        sizeBytes: await file.length(),
        albumArtPath: localArtPath,
        asset: asset,
      ));
    }

    _musicCache.addAll(newFiles);
    _currentLoadPage++;
    
    if (assets.length < pageSize) {
      _hasScannedAll = true;
    }

    return _musicCache;
  }

  /// Keep for legacy support but make it use the cache
  Future<List<MusicFile>> fetchMusicsFromDevice() async {
    if (_musicCache.isNotEmpty && _hasScannedAll) return _musicCache;
    
    // If not scanned all, keep fetching until done (caution: could be slow if many files, 
    // but paged UI should use fetchMusicsPaged instead)
    while (!_hasScannedAll) {
      await fetchMusicsPaged();
      if (_musicCache.length > 500) break; // Safety cap for legacy method
    }
    
    return _musicCache;
  }

  Future<List<MusicFile>> searchMusics(String query) async {
    final allMusics = await fetchMusicsFromDevice();
    return allMusics
        .where((music) =>
            music.displayName.toLowerCase().contains(query.toLowerCase()) ||
            music.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}


