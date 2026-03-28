import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'album_detail_screen.dart';
import 'glass_container.dart';
import 'services/gallery_service.dart';
import 'viewer_screen.dart';
import 'theme_provider.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with WidgetsBindingObserver {
  final GalleryService service = GalleryService();
  final ScrollController scrollController = ScrollController();
  final ScrollController albumsScrollController = ScrollController();

  List<AssetEntity> images = [];
  List<AlbumSummary> albums = [];
  final Set<String> favorites = {};
  final Set<String> animating = {};

  final Map<String, Uint8List?> thumbnailCache = {};
  final Map<String, ValueNotifier<Uint8List?>> thumbnailNotifiers = {};
  final Set<String> loadingThumbs = {};

  bool isLoading = true;
  bool isLoadingMore = false;
  bool isLoadingAlbums = true;
  PermissionState? permissionState;
  bool hasMore = true;
  int currentPage = 0;
  int selectedIndex = 0;
  static const int pageSize = 120;
  static const double pinchStepOutThreshold = 1.07;
  static const double pinchStepInThreshold = 0.93;
  static const int pinchStepCooldownMs = 55;
  int galleryGridCount = 3;
  double _lastPinchScale = 1.0;
  double _pinchAccumulator = 1.0;
  int _activePointers = 0;
  DateTime _lastGridStepAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pinchStepConsumed = false;

  bool get _isPinching => _activePointers >= 2;

  int get galleryThumbPx {
    switch (galleryGridCount) {
      case 2:
        return 320;
      case 3:
        return 220;
      case 4:
        return 180;
      case 5:
        return 140;
      default:
        return 120;
    }
  }

  List<_GallerySection> buildSections(List<AssetEntity> items) {
    if (items.isEmpty) return const [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final monthNames = const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final sections = <_GallerySection>[];
    String? currentTitle;
    List<AssetEntity> currentItems = [];

    String titleFor(AssetEntity asset) {
      final date = service.resolveAssetDate(asset);
      final day = DateTime(date.year, date.month, date.day);
      if (day == today) return 'Today';
      if (day == yesterday) return 'Yesterday';
      return '${monthNames[date.month - 1]} ${date.year}';
    }

    for (final asset in items) {
      final title = titleFor(asset);
      if (currentTitle != title) {
        if (currentTitle != null) {
          sections.add(_GallerySection(title: currentTitle, items: currentItems));
        }
        currentTitle = title;
        currentItems = [asset];
      } else {
        currentItems.add(asset);
      }
    }

    if (currentTitle != null) {
      sections.add(_GallerySection(title: currentTitle, items: currentItems));
    }

    return sections;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scrollController.addListener(onScroll);
    loadAlbums();
    loadImages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scrollController.dispose();
    albumsScrollController.dispose();
    for (final notifier in thumbnailNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    service.clearCache();
    loadAlbums();
    loadImages();
  }

  Future<void> loadImages({bool loadMore = false}) async {
    if (loadMore) {
      if (isLoadingMore || isLoading || !hasMore || selectedIndex != 0) {
        return;
      }
      setState(() => isLoadingMore = true);
    } else {
      setState(() => isLoading = true);
      currentPage = 0;
      hasMore = true;
    }

    if (!loadMore) {
      final permission = await service.requestImagePermission();
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
        images.sort(service.compareAssetsByNewestFirst);
        isLoadingMore = false;
        currentPage = nextPage;
        hasMore = data.length == pageSize;
      } else {
        images = data;
        images.sort(service.compareAssetsByNewestFirst);
        isLoading = false;
        currentPage = data.isEmpty ? 0 : nextPage;
        hasMore = data.length == pageSize;
      }
    });
  }

  Future<void> loadAlbums() async {
    final permission = await service.requestImagePermission();
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
    if (!scrollController.hasClients || isLoading || isLoadingMore) return;

    final position = scrollController.position;
    if (position.pixels > position.maxScrollExtent - 800) {
      loadImages(loadMore: true);
    }
  }

  Widget buildImage(
    AssetEntity asset, {
    int thumbPx = 220,
  }) {
    final id = '${asset.id}@$thumbPx';

    thumbnailNotifiers.putIfAbsent(id, () => ValueNotifier(null));

    final cached = thumbnailCache[id];
    if (cached != null) {
          return Image.memory(
            cached,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          );
        }

    if (!loadingThumbs.contains(id)) {
      loadingThumbs.add(id);
      asset
          .thumbnailDataWithSize(
            ThumbnailSize(thumbPx, thumbPx),
          )
          .then((data) {
        if (!mounted) return;

        if (data != null) {
          thumbnailCache[id] = data;
          thumbnailNotifiers[id]!.value = data;
        }
      }).whenComplete(() {
        loadingThumbs.remove(id);
      });
    }

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: thumbnailNotifiers[id]!,
      builder: (context, value, child) {
        if (value != null) {
          return Image.memory(
            value,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          );
        }
        return DecoratedBox(
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
      },
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
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.035, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
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

  Widget buildStatsChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      key: ValueKey(label),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
                        buildStatsChip(
                          icon: Icons.folder_open_rounded,
                          label: '${albums.length} folders',
                          color: colorScheme.primaryContainer.withOpacity(0.9),
                          textColor: colorScheme.onPrimaryContainer,
                        ),
                        buildStatsChip(
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
                    child: buildFeaturedAlbumCard(
                      album: album,
                      colorScheme: colorScheme,
                      isDark: isDark,
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
                    child: buildAlbumListTile(
                      album: album,
                      colorScheme: colorScheme,
                      isDark: isDark,
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

  Widget buildFeaturedAlbumCard({
    required AlbumSummary album,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () => openAlbum(album),
      child: SizedBox(
        width: 176,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: album.coverAsset != null
                    ? buildImage(album.coverAsset!, thumbPx: 180)
                    : Container(color: colorScheme.surfaceContainerHigh),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(isDark ? 0.44 : 0.4),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Featured',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${album.count} photos',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.86),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildAlbumListTile({
    required AlbumSummary album,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () => openAlbum(album),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(26),
        enableBlur: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 74,
                  height: 74,
                  child: album.coverAsset != null
                      ? buildImage(album.coverAsset!, thumbPx: 96)
                      : Container(color: colorScheme.surfaceContainerHigh),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${album.count} images',
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.68),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildGridView(
    List<AssetEntity> visibleImages,
    ColorScheme colorScheme,
  ) {
    final sections = buildSections(visibleImages);
    final indexByAssetId = <String, int>{
      for (var i = 0; i < visibleImages.length; i++) visibleImages[i].id: i,
    };

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
          _pinchStepConsumed = true;
        },
        onScaleEnd: (details) {
          _lastPinchScale = 1.0;
          _pinchAccumulator = 1.0;
          _pinchStepConsumed = false;
        },
        child: CustomScrollView(
          controller: scrollController,
          cacheExtent: 900,
          physics: _isPinching
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 110),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, sectionIndex) {
                if (sectionIndex >= sections.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 88,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                  final section = sections[sectionIndex];
                  final isFirstSection = sectionIndex == 0;
                  return Transform.translate(
                    offset: Offset(0, isFirstSection ? 0 : -18),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                            child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withOpacity(0.28),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.22),
                                ),
                              ),
                              child: Text(
                                section.title,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer
                                    .withOpacity(0.56),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${section.items.length}',
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 1,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      colorScheme.primary.withOpacity(0.16),
                                      colorScheme.primary.withOpacity(0.02),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                            ),
                          ),
                          GridView.builder(
                            key: ValueKey('grid-${section.title}-$galleryGridCount'),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: section.items.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: galleryGridCount,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              childAspectRatio: 1,
                            ),
                            itemBuilder: (context, index) {
                              final asset = section.items[index];
                              final absoluteIndex =
                                  indexByAssetId[asset.id] ?? 0;

                              return RepaintBoundary(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      buildCinematicRoute(
                                        ViewerScreen(
                                          images: visibleImages,
                                          index: absoluteIndex,
                                        ),
                                      ),
                                    );
                                  },
                                  onDoubleTap: () {
                                    final id = asset.id;

                                    setState(() {
                                      if (favorites.contains(id)) {
                                        favorites.remove(id);
                                      } else {
                                        favorites.add(id);
                                        animating.add(id);
                                      }
                                    });

                                    Future.delayed(
                                      const Duration(milliseconds: 500),
                                      () {
                                        if (mounted) {
                                          setState(() {
                                            animating.remove(id);
                                          });
                                        }
                                      },
                                    );
                                  },
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: buildImage(
                                          asset,
                                          thumbPx: galleryThumbPx,
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
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: sections.length + (isLoadingMore ? 1 : 0),
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
    if (selectedIndex == 1) {
      return KeyedSubtree(
        key: const ValueKey('albums'),
        child: buildAlbumsView(colorScheme, isDark),
      );
    }
    if (isLoading) {
      return const KeyedSubtree(
        key: ValueKey('loading'),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (selectedIndex == 0 && permissionState != null && !permissionState!.hasAccess) {
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
                    loadAlbums();
                    loadImages();
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
      return KeyedSubtree(
        key: ValueKey('empty-$selectedIndex'),
        child: Center(
          child: Text(
            selectedIndex == 0 ? 'No images found' : 'No favorite images yet',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.8),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return KeyedSubtree(
      key: ValueKey('grid-$selectedIndex-${visibleImages.length}'),
      child: buildGridView(visibleImages, colorScheme),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final topBarColor =
        isDark ? const Color(0xFF120C24) : const Color(0xFFF1E8FF);
    final titles = ['Gallery', 'Albums', 'Favorites'];
    final visibleImages = selectedIndex == 2
        ? images
            .where((asset) => favorites.contains(asset.id))
            .toList(growable: false)
        : images;

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

class _GallerySection {
  const _GallerySection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<AssetEntity> items;
}
