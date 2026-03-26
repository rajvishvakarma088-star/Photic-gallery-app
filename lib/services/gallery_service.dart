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
  List<AssetEntity>? _allImagesCache;

  Future<bool> _hasPermission() async {
    final permission = await PhotoManager.requestPermissionExtend();
    return permission.isAuth;
  }

  Future<List<AssetEntity>> fetchImages({
    int page = 0,
    int size = 120,
  }) async {
    if (!await _hasPermission()) return [];

    final allImages = await _loadAllImages();
    final start = page * size;
    if (start >= allImages.length) {
      return [];
    }

    final end = start + size > allImages.length
        ? allImages.length
        : start + size;
    return allImages.sublist(start, end);
  }

  Future<List<AssetEntity>> _loadAllImages() async {
    if (_allImagesCache != null) {
      return _allImagesCache!;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
    );

    if (albums.isEmpty) {
      _allImagesCache = <AssetEntity>[];
      return _allImagesCache!;
    }

    final allImages = <AssetEntity>[];
    final seenIds = <String>{};

    for (final album in albums) {
      int currentPage = 0;

      while (true) {
        final batch = await album.getAssetListPaged(
          page: currentPage,
          size: 200,
        );

        if (batch.isEmpty) break;

        for (final asset in batch) {
          if (seenIds.add(asset.id)) {
            allImages.add(asset);
          }
        }

        currentPage++;
      }
    }

    allImages.sort(compareAssetsByNewestFirst);
    _allImagesCache = allImages;
    return allImages;
  }

  Future<List<AlbumSummary>> fetchAlbums() async {
    if (!await _hasPermission()) return [];

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
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

  int compareAssetsByNewestFirst(AssetEntity a, AssetEntity b) {
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
