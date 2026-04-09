import 'package:photo_manager/photo_manager.dart';

class AlbumSummary {
  AlbumSummary({
    required this.album,
    required this.name,
    required this.count,
    required this.coverAsset,
    required this.isFeatured,
  });

  final AssetPathEntity album;
  final String name;
  final int count;
  final AssetEntity? coverAsset;
  final bool isFeatured;
}

class GalleryService {
  static const int mediaPageSize = 120;
  static const int albumPageSize = 120;

  AssetPathEntity? _allPhotosPathCache;
  AssetPathEntity? _allVideosPathCache;
  AssetPathEntity? _allMediaPathCache;
  List<AssetEntity>? _allAssetsCache;
  final FilterOptionGroup _galleryFilter = FilterOptionGroup(
    orders: const [
      OrderOption(type: OrderOptionType.createDate, asc: false),
      OrderOption(type: OrderOptionType.updateDate, asc: false),
    ],
  );

  Future<PermissionState> requestImagePermission() async {
    return PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
  }

  Future<bool> _hasPermission() async {
    final permission = await requestImagePermission();
    // Treat both full and limited gallery access as usable permission.
    return permission.hasAccess;
  }

  void clearCache() {
    _allPhotosPathCache = null;
    _allVideosPathCache = null;
    _allMediaPathCache = null;
    _allAssetsCache = null;
  }

  Future<List<AssetEntity>> fetchImages({
    int page = 0,
    int size = mediaPageSize,
  }) async {
    if (!await _hasPermission()) return [];
    final allPhotos = await _getAllPhotosPath();
    if (allPhotos == null) return [];

    final images = await allPhotos.getAssetListPaged(page: page, size: size);
    images.sort(compareAssetsByNewestFirst);
    return images;
  }

  Future<List<AssetEntity>> fetchAllAssets({bool forceRefresh = false}) async {
    if (!forceRefresh && _allAssetsCache != null) return _allAssetsCache!;
    if (!await _hasPermission()) return [];
    
    // Fetch both images and videos
    final pathList = await PhotoManager.getAssetPathList(
      type: RequestType.common, // common = images + videos
      hasAll: true,
      filterOption: _galleryFilter,
    );

    if (pathList.isEmpty) return [];
    
    final allPath = pathList.firstWhere((a) => a.isAll, orElse: () => pathList.first);
    final count = await allPath.assetCountAsync;
    
    // Fetch all handles - this is metadata only, relatively fast
    final all = await allPath.getAssetListRange(start: 0, end: count);
    all.sort(compareAssetsByNewestFirst);
    _allAssetsCache = all;
    return all;
  }

  Future<List<AssetEntity>> fetchVideos({
    int page = 0,
    int size = mediaPageSize,
  }) async {
    if (!await _hasPermission()) return [];
    final allVideos = await _getAllVideosPath();
    if (allVideos == null) return [];

    final videos = await allVideos.getAssetListPaged(page: page, size: size);
    videos.sort(compareAssetsByNewestFirst);
    return videos;
  }

  Future<List<AlbumSummary>> fetchAlbums() async {
    if (!await _hasPermission()) return [];

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      filterOption: _galleryFilter,
    );

    final summaries = <AlbumSummary>[];

    for (final album in albums) {
      final count = await album.assetCountAsync;
      if (count == 0) continue;

      final coverItems = await album.getAssetListPaged(page: 0, size: 1);
      final normalized = _normalizeAlbumName(album.name);
      final lowerName = normalized.toLowerCase();

      summaries.add(
        AlbumSummary(
          album: album,
          name: normalized,
          count: count,
          coverAsset: coverItems.isNotEmpty ? coverItems.first : null,
          isFeatured: lowerName.contains('camera') ||
              lowerName.contains('whatsapp') ||
              lowerName.contains('screenshot'),
        ),
      );
    }

    summaries.sort((a, b) {
      if (a.isFeatured != b.isFeatured) {
        return a.isFeatured ? -1 : 1;
      }
      return b.count.compareTo(a.count);
    });

    return summaries;
  }

  Future<List<AssetEntity>> fetchAlbumImages(
    AssetPathEntity album, {
    int page = 0,
    int size = albumPageSize,
  }) async {
    if (!await _hasPermission()) return [];

    final images = await album.getAssetListPaged(page: page, size: size);
    images.sort(compareAssetsByNewestFirst);
    return images;
  }

  /// Fetches ALL images from an album across all pages.
  Future<List<AssetEntity>> fetchAllAlbumImages(
    AssetPathEntity album,
  ) async {
    if (!await _hasPermission()) return [];
    const batchSize = 200;
    final all = <AssetEntity>[];
    var page = 0;
    while (true) {
      final batch =
          await album.getAssetListPaged(page: page, size: batchSize);
      all.addAll(batch);
      if (batch.length < batchSize) break;
      page++;
    }
    all.sort(compareAssetsByNewestFirst);
    return all;
  }

  Future<List<AssetEntity>> fetchAlbumVideos(
    AssetPathEntity album, {
    int page = 0,
    int size = albumPageSize,
  }) async {
    if (!await _hasPermission()) return [];

    final videoAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
      filterOption: _galleryFilter,
    );

    AssetPathEntity? matchingAlbum;
    for (final candidate in videoAlbums) {
      if (candidate.id == album.id || candidate.name == album.name) {
        matchingAlbum = candidate;
        break;
      }

      if (_normalizeAlbumName(candidate.name) ==
          _normalizeAlbumName(album.name)) {
        matchingAlbum = candidate;
        break;
      }
    }

    if (matchingAlbum == null) return [];

    final videos =
        await matchingAlbum.getAssetListPaged(page: page, size: size);
    videos.sort(compareAssetsByNewestFirst);
    return videos;
  }

  /// Fetches ALL videos from an album across all pages.
  Future<List<AssetEntity>> fetchAllAlbumVideos(
    AssetPathEntity album,
  ) async {
    if (!await _hasPermission()) return [];

    final videoAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
      filterOption: _galleryFilter,
    );

    AssetPathEntity? matchingAlbum;
    for (final candidate in videoAlbums) {
      if (candidate.id == album.id || candidate.name == album.name) {
        matchingAlbum = candidate;
        break;
      }
      if (_normalizeAlbumName(candidate.name) ==
          _normalizeAlbumName(album.name)) {
        matchingAlbum = candidate;
        break;
      }
    }
    if (matchingAlbum == null) return [];

    const batchSize = 200;
    final all = <AssetEntity>[];
    var page = 0;
    while (true) {
      final batch =
          await matchingAlbum.getAssetListPaged(page: page, size: batchSize);
      all.addAll(batch);
      if (batch.length < batchSize) break;
      page++;
    }
    all.sort(compareAssetsByNewestFirst);
    return all;
  }

  Future<List<AssetEntity>> fetchImagesByIds(Set<String> assetIds) async {
    if (assetIds.isEmpty || !await _hasPermission()) return [];

    final matches = await Future.wait(
      assetIds.map(AssetEntity.fromId),
    );

    final validMatches = matches
        .whereType<AssetEntity>()
        .toList(growable: false);
    validMatches.sort(compareAssetsByNewestFirst);
    return validMatches;
  }

  Future<List<AssetEntity>> fetchAssetsPage({
    int page = 0,
    int size = mediaPageSize,
  }) async {
    if (!await _hasPermission()) return [];
    final allMedia = await _getAllMediaPath();
    if (allMedia == null) return [];

    final assets = await allMedia.getAssetListPaged(page: page, size: size);
    assets.sort(compareAssetsByNewestFirst);
    return assets;
  }

  Future<AssetPathEntity?> _getAllPhotosPath() async {
    final cached = _allPhotosPathCache;
    if (cached != null) return cached;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      filterOption: _galleryFilter,
    );
    if (albums.isEmpty) return null;

    _allPhotosPathCache = albums.firstWhere(
      (album) => album.isAll,
      orElse: () => albums.first,
    );
    return _allPhotosPathCache;
  }

  Future<AssetPathEntity?> _getAllVideosPath() async {
    final cached = _allVideosPathCache;
    if (cached != null) return cached;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
      filterOption: _galleryFilter,
    );
    if (albums.isEmpty) return null;

    _allVideosPathCache = albums.firstWhere(
      (album) => album.isAll,
      orElse: () => albums.first,
    );
    return _allVideosPathCache;
  }

  Future<AssetPathEntity?> _getAllMediaPath() async {
    final cached = _allMediaPathCache;
    if (cached != null) return cached;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      filterOption: _galleryFilter,
    );
    if (albums.isEmpty) return null;

    _allMediaPathCache = albums.firstWhere(
      (album) => album.isAll,
      orElse: () => albums.first,
    );
    return _allMediaPathCache;
  }

  DateTime resolveAssetDate(AssetEntity asset) {
    final created = asset.createDateTime;
    if (created.year >= 2000) {
      return created;
    }

    final modified = asset.modifiedDateTime;
    if (modified.year >= 2000) {
      return modified;
    }

    return created.isAfter(modified) ? created : modified;
  }

  int compareAssetsByNewestFirst(AssetEntity a, AssetEntity b) {
    final primaryComparison = resolveAssetDate(b).compareTo(resolveAssetDate(a));
    if (primaryComparison != 0) return primaryComparison;

    final createdComparison = b.createDateTime.compareTo(a.createDateTime);
    if (createdComparison != 0) return createdComparison;

    final modifiedComparison =
        b.modifiedDateTime.compareTo(a.modifiedDateTime);
    if (modifiedComparison != 0) return modifiedComparison;

    return b.id.compareTo(a.id);
  }

  String _normalizeAlbumName(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return 'Untitled Album';

    final lower = trimmed.toLowerCase();
    if (lower == 'all' || lower == 'recent' || lower == 'recently added') {
      return 'All Photos and Videos';
    }
    if (lower == 'dcim' || lower.contains('camera')) {
      return 'Camera';
    }
    if (lower == 'whatsapp') {
      return 'WhatsApp';
    }
    if (lower.contains('whatsapp image')) {
      return 'WhatsApp Images';
    }
    if (lower.contains('whatsapp video')) {
      return 'WhatsApp Video';
    }
    if (lower.contains('whatsapp document')) {
      return 'WhatsApp Documents';
    }
    if (lower.contains('screenshot')) {
      return 'Screenshots';
    }
    return trimmed;
  }
}
