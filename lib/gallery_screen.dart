import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'album_detail_screen.dart';
import 'gallery/gallery_album_widgets.dart' as gallery_album_widgets;
import 'gallery/gallery_grid_widgets.dart' as gallery_grid_widgets;
import 'gallery/gallery_section.dart';
import 'gallery/gallery_section_builder.dart';
import 'glass_container.dart';
import 'services/favorites_database.dart';
import 'services/gallery_service.dart';
import 'viewer_screen.dart';
import 'video_viewer_screen.dart';
import 'theme_provider.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with WidgetsBindingObserver {
  final GalleryService service = GalleryService();
  final FavoritesDatabase favoritesDatabase = FavoritesDatabase.instance;
  final ScrollController scrollController = ScrollController();
  final ScrollController videosScrollController = ScrollController();
  final ScrollController favoritesScrollController = ScrollController();
  final ScrollController albumsScrollController = ScrollController();
  final PageStorageKey _galleryScrollKey = const PageStorageKey(
    'gallery-scroll',
  );
  final PageStorageKey _favoritesScrollKey = const PageStorageKey(
    'favorites-scroll',
  );
  List<GallerySection>? _cachedSections;
  List<AssetEntity>? _cachedSectionSource;
  int _cachedSectionLength = -1;

  List<AssetEntity> images = [];
  List<AssetEntity> videos = [];
  List<AssetEntity> favoriteImages = [];
  List<AlbumSummary> albums = [];
  final Set<String> favorites = {};
  final Set<String> animating = {};

  final Map<String, AssetEntityImageProvider> thumbnailProviderCache = {};
  final Set<String> warmedThumbnailKeys = {};
  final Set<String> seenThumbnailAssetIds = {};

  bool isLoading = true;
  bool isLoadingVideos = true;
  bool isLoadingFavorites = true;
  bool isLoadingFavoriteImages = false;
  bool isLoadingMore = false;
  bool isLoadingMoreVideos = false;
  bool isLoadingAlbums = true;
  PermissionState? permissionState;
  bool hasMore = true;
  bool hasMoreVideos = true;
  int currentPage = 0;
  int currentVideoPage = 0;
  int selectedIndex = 0;
  static const int pageSize = 160;
  static const double pinchStepOutThreshold = 1.07;
  static const double pinchStepInThreshold = 0.93;
  static const int pinchStepCooldownMs = 55;
  static const double _galleryLoadMoreThreshold = 2600;
  int galleryGridCount = 3;
  double _lastPinchScale = 1.0;
  double _pinchAccumulator = 1.0;
  int _activePointers = 0;
  DateTime _lastGridStepAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pinchStepConsumed = false;
  bool _isPrefetchingNextPage = false;
  bool _isViewerTransitioning = false;
  List<AssetEntity>? _prefetchedImages;
  int? _prefetchedPage;
  Timer? _thumbnailWarmupTimer;
  int _lastWarmedStart = -1;
  int _lastWarmedEnd = -1;

  bool get _isPinching => _activePointers >= 2;

  int get galleryThumbPx {
    // Keep one stable thumbnail size across grid changes so pinch-to-zoom
    // reuses the same cached providers instead of triggering a full reload.
    // Lowered to 180 for smoother scroll performance.
    return 180;
  }

  List<GallerySection> buildSections(List<AssetEntity> items) {
    if (items.isEmpty) return const [];
    if (identical(_cachedSectionSource, items) &&
        _cachedSectionLength == items.length &&
        _cachedSections != null) {
      return _cachedSections!;
    }
    final sections = buildGallerySections(items, service.resolveAssetDate);

    _cachedSectionSource = items;
    _cachedSectionLength = items.length;
    _cachedSections = sections;
    return sections;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scrollController.addListener(onScroll);
    videosScrollController.addListener(onScroll);
    loadFavorites();
    unawaited(loadInitialMediaData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _thumbnailWarmupTimer?.cancel();
    thumbnailProviderCache.clear();
    scrollController.dispose();
    videosScrollController.dispose();
    favoritesScrollController.dispose();
    albumsScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    service.clearCache();
    loadFavorites();
    unawaited(loadInitialMediaData());
  }

  Future<void> loadInitialMediaData() async {
    final permission = await service.requestImagePermission();
    if (!mounted) return;

    if (!permission.hasAccess) {
      setState(() {
        permissionState = permission;
        images = [];
        videos = [];
        albums = [];
        isLoading = false;
        isLoadingVideos = false;
        isLoadingMore = false;
        isLoadingMoreVideos = false;
        isLoadingAlbums = false;
        hasMore = false;
        hasMoreVideos = false;
      });
      return;
    }

    permissionState = permission;

    await Future.wait([
      loadAlbums(permissionOverride: permission),
      loadImages(permissionOverride: permission),
      loadVideos(permissionOverride: permission),
    ]);
  }

  Future<void> loadFavorites() async {
    try {
      final data = await favoritesDatabase.loadFavoriteIds();
      if (!mounted) return;

      setState(() {
        favorites
          ..clear()
          ..addAll(data);
        isLoadingFavorites = false;
      });

      await syncFavoriteImages();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        favorites.clear();
        favoriteImages = [];
        isLoadingFavorites = false;
        isLoadingFavoriteImages = false;
      });
    }
  }

  Future<void> syncFavoriteImages() async {
    if (favorites.isEmpty) {
      if (!mounted) return;
      setState(() {
        favoriteImages = [];
        isLoadingFavoriteImages = false;
      });
      return;
    }

    setState(() => isLoadingFavoriteImages = true);
    final data = await service.fetchImagesByIds(favorites);
    if (!mounted) return;

    setState(() {
      favoriteImages = data;
      isLoadingFavoriteImages = false;
    });
  }

  Future<void> toggleFavorite(AssetEntity asset) async {
    final assetId = asset.id;
    final wasFavorite = favorites.contains(assetId);

    setState(() {
      if (wasFavorite) {
        favorites.remove(assetId);
        animating.remove(assetId);
        favoriteImages.removeWhere((item) => item.id == assetId);
      } else {
        favorites.add(assetId);
        animating.add(assetId);
        favoriteImages = [...favoriteImages, asset]
          ..sort(service.compareAssetsByNewestFirst);
      }
    });

    if (!wasFavorite) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() {
          animating.remove(assetId);
        });
      });
    }

    try {
      if (wasFavorite) {
        await favoritesDatabase.removeFavorite(assetId);
      } else {
        await favoritesDatabase.addFavorite(assetId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          favorites.add(assetId);
          favoriteImages = [...favoriteImages, asset]
            ..sort(service.compareAssetsByNewestFirst);
        } else {
          favorites.remove(assetId);
          animating.remove(assetId);
          favoriteImages.removeWhere((item) => item.id == assetId);
        }
      });
    }
  }

  Future<void> loadImages({
    bool loadMore = false,
    PermissionState? permissionOverride,
  }) async {
    if (loadMore) {
      if (isLoadingMore || isLoading || !hasMore || selectedIndex != 0) {
        return;
      }

      final nextPage = currentPage + 1;
      if (_prefetchedPage == nextPage && _prefetchedImages != null) {
        final prefetched = _prefetchedImages!;
        setState(() {
          images.addAll(prefetched);
          currentPage = nextPage;
          hasMore = prefetched.length == pageSize;
        });
        _prefetchedImages = null;
        _prefetchedPage = null;
        unawaited(_prefetchNextImages());
        return;
      }

      setState(() => isLoadingMore = true);
    } else {
      setState(() => isLoading = true);
      currentPage = 0;
      hasMore = true;
      _prefetchedImages = null;
      _prefetchedPage = null;
    }

    if (!loadMore) {
      final permission =
          permissionOverride ?? await service.requestImagePermission();
      if (!mounted) return;

      if (!permission.hasAccess) {
        setState(() {
          permissionState = permission;
          images = [];
          isLoading = false;
          isLoadingMore = false;
          hasMore = false;
        });
        return;
      }

      permissionState = permission;
    }

    final nextPage = loadMore ? currentPage + 1 : 0;
    final data = await service.fetchImages(
      page: nextPage,
      size: pageSize,
    );

    if (!mounted) return;

    setState(() {
      if (loadMore) {
        images.addAll(data);
        isLoadingMore = false;
        currentPage = nextPage;
        hasMore = data.length == pageSize;
      } else {
        images = data;
        isLoading = false;
        currentPage = data.isEmpty ? 0 : nextPage;
        hasMore = data.length == pageSize;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleThumbnailWarmup();
    });
    unawaited(_prefetchNextImages());
  }

  Future<void> loadVideos({
    bool loadMore = false,
    PermissionState? permissionOverride,
  }) async {
    if (loadMore) {
      if (isLoadingMoreVideos || isLoadingVideos || !hasMoreVideos || selectedIndex != 1) return;
      setState(() => isLoadingMoreVideos = true);
    } else {
      setState(() => isLoadingVideos = true);
      currentVideoPage = 0;
      hasMoreVideos = true;
    }

    if (!loadMore) {
      final permission = permissionOverride ?? await service.requestImagePermission();
      if (!mounted) return;
      if (!permission.hasAccess) {
        setState(() {
          permissionState = permission;
          videos = [];
          isLoadingVideos = false;
          isLoadingMoreVideos = false;
          hasMoreVideos = false;
        });
        return;
      }
      permissionState = permission;
    }

    final nextPage = loadMore ? currentVideoPage + 1 : 0;
    final data = await service.fetchVideos(page: nextPage, size: pageSize);
    if (!mounted) return;

    setState(() {
      if (loadMore) {
        videos.addAll(data);
        isLoadingMoreVideos = false;
        currentVideoPage = nextPage;
        hasMoreVideos = data.length == pageSize;
      } else {
        videos = data;
        isLoadingVideos = false;
        currentVideoPage = data.isEmpty ? 0 : nextPage;
        hasMoreVideos = data.length == pageSize;
      }
    });
  }

  Future<void> _prefetchNextImages() async {
    if (!mounted ||
        _isPrefetchingNextPage ||
        _isViewerTransitioning ||
        isLoading ||
        isLoadingMore ||
        !hasMore ||
        selectedIndex != 0) {
      return;
    }

    final targetPage = currentPage + 1;
    if (_prefetchedPage == targetPage && _prefetchedImages != null) return;

    _isPrefetchingNextPage = true;
    try {
      final data = await service.fetchImages(
        page: targetPage,
        size: pageSize,
      );
      if (!mounted || selectedIndex != 0) return;
      _prefetchedImages = data;
      _prefetchedPage = targetPage;
    } finally {
      _isPrefetchingNextPage = false;
    }
  }

  Future<void> loadAlbums({
    PermissionState? permissionOverride,
  }) async {
    final permission =
        permissionOverride ?? await service.requestImagePermission();
    if (!mounted) return;
    if (!permission.hasAccess) {
      setState(() {
        permissionState = permission;
        albums = [];
        isLoadingAlbums = false;
      });
      return;
    }

    final data = await service.fetchAlbums();
    if (!mounted) return;

    setState(() {
      permissionState = permission;
      albums = data;
      isLoadingAlbums = false;
    });
  }

  void onScroll() {
    if (_isViewerTransitioning) return;

    if (selectedIndex == 0) {
      if (!scrollController.hasClients || isLoading || isLoadingMore) return;
      final position = scrollController.position;
      if (position.pixels > position.maxScrollExtent - _galleryLoadMoreThreshold) {
        loadImages(loadMore: true);
      }
    } else if (selectedIndex == 1) {
      if (!videosScrollController.hasClients || isLoadingVideos || isLoadingMoreVideos) return;
      final position = videosScrollController.position;
      if (position.pixels > position.maxScrollExtent - _galleryLoadMoreThreshold) {
        loadVideos(loadMore: true);
      }
    }
  }

  ImageProvider<Object> _thumbnailProviderFor(
    AssetEntity asset,
    int thumbPx,
  ) {
    final id = '${asset.id}@$thumbPx';
    return thumbnailProviderCache.putIfAbsent(
      id,
      () => AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: ThumbnailSize.square(thumbPx),
        thumbnailFormat: ThumbnailFormat.jpeg,
      ),
    );
  }


  void _scheduleThumbnailWarmup() {
    if (!mounted ||
        selectedIndex != 0 ||
        images.isEmpty ||
        _isViewerTransitioning) {
      return;
    }

    _thumbnailWarmupTimer?.cancel();
    _thumbnailWarmupTimer = Timer(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      _warmVisibleThumbnailBand();
    });
  }

  void _warmVisibleThumbnailBand() {
    if (!mounted ||
        !scrollController.hasClients ||
        selectedIndex != 0 ||
        _isViewerTransitioning ||
        images.isEmpty) {
      return;
    }

    final viewportWidth = MediaQuery.of(context).size.width;
    final contentWidth =
        (viewportWidth - 20 - ((galleryGridCount - 1) * 6)).clamp(120.0, 4000.0);
    final tileExtent = (contentWidth / galleryGridCount) + 6;
    final effectiveOffset =
        (scrollController.offset - 54).clamp(0.0, double.infinity);
    final firstVisibleRow = (effectiveOffset / tileExtent).floor();
    final visibleRows =
        ((scrollController.position.viewportDimension / tileExtent).ceil() + 2)
            .clamp(4, 14);
    final startIndex = ((firstVisibleRow - 4) * galleryGridCount)
        .clamp(0, images.length);
    final endIndex = ((firstVisibleRow + visibleRows + 7) * galleryGridCount)
        .clamp(0, images.length);

    if (startIndex == _lastWarmedStart && endIndex == _lastWarmedEnd) return;
    _lastWarmedStart = startIndex;
    _lastWarmedEnd = endIndex;

    for (var i = startIndex; i < endIndex; i++) {
      seenThumbnailAssetIds.add(images[i].id);
      warmedThumbnailKeys.add('${images[i].id}@$galleryThumbPx');
      precacheImage(
        _thumbnailProviderFor(images[i], galleryThumbPx),
        context,
      );
    }
  }

  Widget buildImage(
    AssetEntity asset, {
    int thumbPx = 220,
  }) {
    final id = '${asset.id}@$thumbPx';
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surfaceContainerHighest,
            Theme.of(context).colorScheme.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );

    final isWarm =
        warmedThumbnailKeys.contains(id) || seenThumbnailAssetIds.contains(asset.id);

    if (!isWarm && Scrollable.recommendDeferredLoadingForContext(context)) {
      return placeholder;
    }

    seenThumbnailAssetIds.add(asset.id);
    warmedThumbnailKeys.add(id);
    final provider = _thumbnailProviderFor(asset, thumbPx);

    return Image(
      image: provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return placeholder;
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }


  Widget buildBottomBar(BuildContext context, bool isDark) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(28),
      child: NavigationBar(
        height: 72,
        selectedIndex: selectedIndex,
        backgroundColor: Colors.transparent,
        onDestinationSelected: (index) {
          if (index == selectedIndex) return;
          setState(() => selectedIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: 'Gallery',
          ),
          const NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Videos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy),
            label: 'Albums',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: favorites.length,
              isLabelVisible: favorites.isNotEmpty,
              child: const Icon(Icons.favorite_border),
            ),
            selectedIcon: const Icon(Icons.favorite),
            label: 'Favorites',
          ),
        ],
      ),
    );
  }

  Route<T> buildCinematicRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => page,
    );
  }

  Future<void> openAlbum(AlbumSummary album) async {
    final albumImages = await service.fetchAlbumImages(album.album);
    if (!mounted || albumImages.isEmpty) return;

    await Navigator.push(
      context,
      buildCinematicRoute(
        AlbumDetailScreen(
          title: album.name,
          images: albumImages,
        ),
      ),
    );
  }

  Widget buildAlbumsView(ColorScheme colorScheme, bool isDark) {
    if (isLoadingAlbums) {
      return const Center(child: CircularProgressIndicator());
    }

    if (albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found',
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final featuredAlbums =
        albums.where((album) => album.isFeatured).toList(growable: false);
    final otherAlbums =
        albums.where((album) => !album.isFeatured).toList(growable: false);

    return CustomScrollView(
      controller: albumsScrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Albums',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Browse photos by folder with rich previews and quick counts.',
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.72),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        gallery_album_widgets.buildGalleryStatsChip(
                          icon: Icons.folder_open_rounded,
                          label: '${albums.length} folders',
                          color: colorScheme.primaryContainer.withOpacity(0.9),
                          textColor: colorScheme.onPrimaryContainer,
                        ),
                        gallery_album_widgets.buildGalleryStatsChip(
                          icon: Icons.photo_library_rounded,
                          label:
                              '${albums.fold<int>(0, (sum, album) => sum + album.count)} photos',
                          color: colorScheme.secondaryContainer.withOpacity(0.9),
                          textColor: colorScheme.onSecondaryContainer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (featuredAlbums.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Highlights',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${featuredAlbums.length} picked',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (featuredAlbums.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                cacheExtent: 800,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  decelerationRate: ScrollDecelerationRate.fast,
                ),
                itemCount: featuredAlbums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final album = featuredAlbums[index];
                  return RepaintBoundary(
                    child: gallery_album_widgets.buildFeaturedAlbumCard(
                      album: album,
                      colorScheme: colorScheme,
                      isDark: isDark,
                      buildImage: buildImage,
                      onTap: () => openAlbum(album),
                    ),
                  );
                },
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
            child: Text(
              featuredAlbums.isEmpty ? 'All Albums' : 'More Albums',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final album = otherAlbums[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == otherAlbums.length - 1 ? 0 : 12,
                  ),
                  child: RepaintBoundary(
                    child: gallery_album_widgets.buildAlbumListTile(
                      album: album,
                      colorScheme: colorScheme,
                      buildImage: buildImage,
                      onTap: () => openAlbum(album),
                    ),
                  ),
                );
              },
              childCount: otherAlbums.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildGridTile(
    AssetEntity asset,
    List<AssetEntity> visibleImages,
    int absoluteIndex,
  ) {
    final ImageProvider<Object>? previewProvider =
        _thumbnailProviderFor(asset, galleryThumbPx);
    final openingProvider = ViewerScreen.openingImageProvider(context, asset);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () async {
          _thumbnailWarmupTimer?.cancel();
          _isViewerTransitioning = true;
          
          if (asset.type == AssetType.video) {
            final videoList = visibleImages.where((e) => e.type == AssetType.video).toList();
            var videoIndex = videoList.indexWhere((e) => e.id == asset.id);
            if (videoIndex == -1) {
              videoList.insert(0, asset);
              videoIndex = 0;
            }

            await Navigator.push(
              context,
              buildCinematicRoute(
                VideoViewerScreen(videos: videoList, initialIndex: videoIndex),
              ),
            );
          } else {
            // Warm up both preview and opening providers so the transition is smooth.
            if (previewProvider != null) {
              unawaited(precacheImage(previewProvider, context));
            }
            unawaited(precacheImage(openingProvider, context));

            await Navigator.push(
              context,
              buildCinematicRoute(
                ViewerScreen(
                  images: visibleImages,
                  index: absoluteIndex,
                  initialPreviewProvider: previewProvider,
                  initialViewerProvider: openingProvider,
                ),
              ),
            );
          }
          if (!mounted) return;
          _isViewerTransitioning = false;
          _scheduleThumbnailWarmup();
        },
        onDoubleTap: () {
          toggleFavorite(asset);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Hero(
                tag: asset.id,
                child: buildImage(asset, thumbPx: galleryThumbPx),
              ),
            ),
            if (asset.type == AssetType.video)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 2),
                      Text(
                        _formatDuration(asset.videoDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (favorites.contains(asset.id))
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.favorite,
                  color: Colors.red,
                ),
              ),
            if (animating.contains(asset.id))
              const Center(
                child: Icon(
                  Icons.favorite,
                  color: Colors.white,
                  size: 60,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget buildGridView(
    List<AssetEntity> visibleImages,
    ColorScheme colorScheme,
    ScrollController controller,
  ) {
    final sections = buildSections(visibleImages);
    final indexByAssetId = <String, int>{
      for (var i = 0; i < visibleImages.length; i++) visibleImages[i].id: i,
    };

    final slivers = <Widget>[
      for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++)
        ...[
          SliverToBoxAdapter(
            child: gallery_grid_widgets.buildGallerySectionHeader(
              sections[sectionIndex],
              colorScheme,
              sectionIndex == 0,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(top: 6),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final asset = sections[sectionIndex].items[index];
                  final absoluteIndex = indexByAssetId[asset.id] ?? 0;
                  return buildGridTile(
                    asset,
                    visibleImages,
                    absoluteIndex,
                  );
                },
                childCount: sections[sectionIndex].items.length,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: galleryGridCount,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1,
              ),
            ),
          ),
        ],
    ];

    return Listener(
      onPointerDown: (_) {
        final wasPinching = _isPinching;
        _activePointers++;
        if (!wasPinching && _isPinching) {
          setState(() {});
        }
      },
      onPointerUp: (_) {
        final wasPinching = _isPinching;
        _activePointers = (_activePointers - 1).clamp(0, 20);
        if (wasPinching && !_isPinching) {
          setState(() {});
        }
      },
      onPointerCancel: (_) {
        final wasPinching = _isPinching;
        _activePointers = (_activePointers - 1).clamp(0, 20);
        if (wasPinching && !_isPinching) {
          setState(() {});
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _lastPinchScale = 1.0;
          _pinchAccumulator = 1.0;
          _pinchStepConsumed = false;
        },
        onScaleUpdate: (details) {
          if (_pinchStepConsumed) return;
          if (!_isPinching) {
            _lastPinchScale = details.scale;
            return;
          }

          final factor = details.scale / _lastPinchScale;
          _lastPinchScale = details.scale;
          if (!factor.isFinite || factor <= 0) return;

          _pinchAccumulator *= factor;
          int nextCount = galleryGridCount;
          var updatedAccumulator = _pinchAccumulator;

          if (updatedAccumulator >= pinchStepOutThreshold && nextCount > 2) {
            nextCount--;
            updatedAccumulator /= pinchStepOutThreshold;
          } else if (updatedAccumulator <= pinchStepInThreshold &&
              nextCount < 6) {
            nextCount++;
            updatedAccumulator /= pinchStepInThreshold;
          }

          _pinchAccumulator = updatedAccumulator.clamp(0.75, 1.25).toDouble();
          if (nextCount == galleryGridCount) return;

          final now = DateTime.now();
          if (now.difference(_lastGridStepAt).inMilliseconds <
              pinchStepCooldownMs) {
            return;
          }

          setState(() {
            galleryGridCount = nextCount;
            _lastGridStepAt = now;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scheduleThumbnailWarmup();
          });
          _pinchStepConsumed = true;
        },
        onScaleEnd: (details) {
          _lastPinchScale = 1.0;
          _pinchAccumulator = 1.0;
          _pinchStepConsumed = false;
        },
        child: Stack(
          children: [
            CustomScrollView(
              key: controller == scrollController
                  ? _galleryScrollKey
                  : _favoritesScrollKey,
              controller: controller,
              cacheExtent: 600,
              physics: _isPinching
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 110),
                  sliver: SliverMainAxisGroup(slivers: slivers),
                ),
              ],
            ),
            if (isLoadingMore && controller == scrollController)
              Positioned(
                left: 0,
                right: 0,
                bottom: 116,
                child: IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withOpacity(0.88),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildBody(
    List<AssetEntity> visibleImages,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    if (selectedIndex == 2) {
      return KeyedSubtree(
        key: const ValueKey('albums'),
        child: buildAlbumsView(colorScheme, isDark),
      );
    }
    if ((selectedIndex == 0 && isLoading) ||
        (selectedIndex == 1 && isLoadingVideos) ||
        (selectedIndex == 3 && isLoadingFavoriteImages)) {
      return const KeyedSubtree(
        key: ValueKey('loading'),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if ((selectedIndex == 0 || selectedIndex == 1) && permissionState != null && !permissionState!.hasAccess) {
      return KeyedSubtree(
        key: const ValueKey('permission-empty'),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 44,
                  color: colorScheme.onSurface.withOpacity(0.75),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gallery permission is required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Allow photos access, then tap retry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.75),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () async {
                    await PhotoManager.openSetting();
                  },
                  child: const Text('Open Settings'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    service.clearCache();
                    unawaited(loadInitialMediaData());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (visibleImages.isEmpty) {
      String emptyText = 'No images found';
      if (selectedIndex == 1) emptyText = 'No videos found';
      else if (selectedIndex == 3) emptyText = 'No favorite items yet';

      return KeyedSubtree(
        key: ValueKey('empty-$selectedIndex'),
        child: Center(
          child: Text(
            emptyText,
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.8),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    
    ScrollController currentController = scrollController;
    if (selectedIndex == 1) currentController = videosScrollController;
    else if (selectedIndex == 3) currentController = favoritesScrollController;

    return KeyedSubtree(
      key: ValueKey('grid-$selectedIndex'),
      child: buildGridView(
        visibleImages,
        colorScheme,
        currentController,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final topBarColor =
        isDark ? const Color(0xFF120C24) : const Color(0xFFF1E8FF);
    final titles = ['Gallery', 'Videos', 'Albums', 'Favorites'];

    List<AssetEntity> visibleImages = images;
    if (selectedIndex == 1) visibleImages = videos;
    else if (selectedIndex == 3) visibleImages = favoriteImages;

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            titles[selectedIndex],
            key: ValueKey(selectedIndex),
          ),
        ),
        backgroundColor: topBarColor,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle.copyWith(
          statusBarColor: topBarColor,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor:
              isDark ? const Color(0xFF101916) : const Color(0xFFF5F6F0),
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Light mode' : 'Dark mode',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme();
            },
          )
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [
                        Color(0xFF120C24),
                        Color(0xFF1E163A),
                        Color(0xFF2C1F52),
                      ]
                    : const [
                        Color(0xFFF0E5FF),
                        Color(0xFFE4D3FF),
                        Color(0xFFD5BDFF),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFA855F7).withOpacity(
                    isDark ? 0.18 : 0.24,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: 80,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDDD6FE).withOpacity(
                    isDark ? 0.08 : 0.4,
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.02, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: buildBody(visibleImages, colorScheme, isDark),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: buildBottomBar(context, isDark),
        ),
      ),
    );
  }
}
