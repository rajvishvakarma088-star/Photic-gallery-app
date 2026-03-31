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
  AssetPathEntity? _allPhotosPathCache;
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
          type: RequestType.image,
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
  }

  Future<List<AssetEntity>> fetchImages({
    int page = 0,
    int size = 120,
  }) async {
    if (!await _hasPermission()) return [];
    final allPhotos = await _getAllPhotosPath();
    if (allPhotos == null) return [];

    final images = await allPhotos.getAssetListPaged(page: page, size: size);
    images.sort(compareAssetsByNewestFirst);
    return images;
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
    int size = 120,
  }) async {
    if (!await _hasPermission()) return [];

    final images = await album.getAssetListPaged(page: page, size: size);
    images.sort(compareAssetsByNewestFirst);
    return images;
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
      return 'All Photos';
    }
    if (lower == 'dcim' || lower.contains('camera')) {
      return 'Camera';
    }
    if (lower.contains('whatsapp')) {
      return 'WhatsApp';
    }
    if (lower.contains('screenshot')) {
      return 'Screenshots';
    }
    return trimmed;
  }
}
