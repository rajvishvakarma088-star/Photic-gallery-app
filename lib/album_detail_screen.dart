import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'glass_container.dart';
import 'services/favorites_database.dart';
import 'services/gallery_service.dart';
import 'services/recycle_bin_database.dart';
import 'services/vault_service.dart';
import 'theme_provider.dart';
import 'utils/lru_cache.dart';
import 'video_viewer_screen.dart';
import 'viewer_screen.dart';

class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.title,
    required this.album,
    required this.images,
  });

  final String title;
  final AssetPathEntity album;
  final List<AssetEntity> images;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  // ── Pinch constants (exact copy of gallery_screen) ─────────────────────────
  static const double pinchStepOutThreshold = 1.07;
  static const double pinchStepInThreshold = 0.93;
  static const int pinchStepCooldownMs = 55;

  final GalleryService service = GalleryService();
  final RecycleBinDatabase recycleBinDatabase = RecycleBinDatabase.instance;
  final VaultService vaultService = VaultService.instance;

  // PageController drives the Photos / Videos tab swipe
  final PageController _pageController = PageController();

  // Each tab has its OWN dedicated scroll controller – passed explicitly to
  // each grid so that there is never any ambiguity about which controller is
  // attached to which list.
  final ScrollController _photoScrollController = ScrollController();
  final ScrollController _videoScrollController = ScrollController();

  // Shared thumbnail cache keyed by  "${assetId}@${px}"
  final LruMap<String, AssetEntityImageProvider> _thumbCache =
      LruMap<String, AssetEntityImageProvider>(_maxThumbCacheEntries);

  // Grid-tile GlobalKeys – prefixed with tab index to avoid duplicate-key
  // errors when the same asset appears in both Photos and Videos tabs.
  final Map<String, GlobalKey> _gridTileKeys = {};

  final Set<String> selectedAssetIds = {};

  late List<AssetEntity> albumImages;
  List<AssetEntity> albumVideos = [];
  int _currentPhotoPage = 0;
  int _currentVideoPage = -1;
  bool _hasMorePhotos = true;
  bool _hasMoreVideos = true;
  bool _isLoadingMorePhotos = false;
  bool _isLoadingMoreVideos = false;

  int albumGridCount = 3;
  int selectedMediaTab = 0; // 0 = Photos, 1 = Videos

  // ── Pinch state ────────────────────────────────────────────────────────────
  double _lastPinchScale = 1.0;
  double _pinchAccumulator = 1.0;
  int _activePointers = 0;
  DateTime _lastGridStepAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pinchStepConsumed = false;

  // ── Other state ────────────────────────────────────────────────────────────
  bool isRecycleActionInProgress = false;
  bool isLoadingPhotos = false;
  bool isLoadingVideos = false;

  // ── Drag-selection state ───────────────────────────────────────────────────
  bool? _dragSelectionTargetValue;
  final Set<String> _dragSelectionTouchedIds = {};
  Timer? _dragAutoScrollTimer;
  double _dragAutoScrollVelocity = 0;
  Offset? _lastDragGlobalPosition;

  // ── Thumbnail warmup ───────────────────────────────────────────────────────
  Timer? _thumbnailWarmupTimer;

  // ── Convenience getters ────────────────────────────────────────────────────
  bool get _isPinching => _activePointers >= 2;
  bool get isSelectionMode => selectedAssetIds.isNotEmpty;
  List<AssetEntity> get visibleAssets =>
      selectedMediaTab == 0 ? albumImages : albumVideos;

  static const int _thumbPx = 180;
  static const int _pageSize = GalleryService.albumPageSize;
  static const double _loadMoreThreshold = 1400;
  static const int _maxThumbCacheEntries = 1800;

  // ══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    albumImages = List<AssetEntity>.from(widget.images);
    _hasMorePhotos = widget.images.length >= _pageSize;
    _photoScrollController.addListener(_onPhotoScroll);
    _videoScrollController.addListener(_onVideoScroll);
    unawaited(_syncPhotoPaginationState());
    unawaited(_loadInitialAlbumVideos());
  }

  void _onPhotoScroll() {
    if (selectedMediaTab == 0) {
      _scheduleThumbnailWarmup();
    }
    if (!_photoScrollController.hasClients ||
        _isLoadingMorePhotos ||
        !_hasMorePhotos) {
      return;
    }
    final position = _photoScrollController.position;
    if (position.pixels > position.maxScrollExtent - _loadMoreThreshold) {
      unawaited(_loadMoreAlbumPhotos());
    }
  }

  void _onVideoScroll() {
    if (selectedMediaTab == 1) {
      _scheduleThumbnailWarmup();
    }
    if (!_videoScrollController.hasClients ||
        _isLoadingMoreVideos ||
        !_hasMoreVideos) {
      return;
    }
    final position = _videoScrollController.position;
    if (position.pixels > position.maxScrollExtent - _loadMoreThreshold) {
      unawaited(_loadMoreAlbumVideos());
    }
  }

  @override
  void dispose() {
    _thumbnailWarmupTimer?.cancel();
    _dragAutoScrollTimer?.cancel();
    _photoScrollController
      ..removeListener(_onPhotoScroll)
      ..dispose();
    _videoScrollController
      ..removeListener(_onVideoScroll)
      ..dispose();
    _pageController.dispose();
    _gridTileKeys.clear();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Thumbnail warmup (same logic as gallery_screen)
  // ══════════════════════════════════════════════════════════════════════════

  void _scheduleThumbnailWarmup() {
    if (!mounted) return;
    _thumbnailWarmupTimer?.cancel();
    _thumbnailWarmupTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _warmVisibleThumbnailBand();
    });
  }

  void _warmVisibleThumbnailBand() {
    if (!mounted) return;
    final controller =
        selectedMediaTab == 0 ? _photoScrollController : _videoScrollController;
    final assets = selectedMediaTab == 0 ? albumImages : albumVideos;
    if (!controller.hasClients || assets.isEmpty) return;

    final viewportWidth = MediaQuery.of(context).size.width;
    // Approximate the grid padding (10 left + 10 right = 20) and spacing
    const spacing = 6.0;
    final contentWidth =
        viewportWidth - 20 - (albumGridCount - 1) * spacing;
    final tileExtent = (contentWidth / albumGridCount) + spacing;

    final scrollOffset = controller.offset;
    final viewportHeight = controller.position.viewportDimension;

    final firstRow = (scrollOffset / tileExtent).floor();
    final visibleRows = (viewportHeight / tileExtent).ceil() + 2;

    final startIndex =
        ((firstRow - 2) * albumGridCount).clamp(0, assets.length);
    final endIndex =
        ((firstRow + visibleRows + 4) * albumGridCount).clamp(0, assets.length);

    for (int i = startIndex; i < endIndex; i++) {
      final asset = assets[i];
      final id = '${asset.id}@$_thumbPx';
      if (!_thumbCache.containsKey(id)) {
        final provider = _thumbCache.putIfAbsent(
          id,
          () => AssetEntityImageProvider(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(_thumbPx),
            thumbnailFormat: ThumbnailFormat.jpeg,
          ),
        );
        unawaited(precacheImage(provider, context));
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Drag selection
  // ══════════════════════════════════════════════════════════════════════════

  void _startDragSelection(AssetEntity asset, int tab) {
    if (isRecycleActionInProgress) return;
    _dragSelectionTargetValue = !selectedAssetIds.contains(asset.id);
    _dragSelectionTouchedIds
      ..clear()
      ..add(asset.id);
    setState(() {
      if (_dragSelectionTargetValue!) {
        selectedAssetIds.add(asset.id);
      } else {
        selectedAssetIds.remove(asset.id);
      }
    });
  }

  void _applyDragSelection(AssetEntity asset) {
    final targetValue = _dragSelectionTargetValue;
    if (targetValue == null || _dragSelectionTouchedIds.contains(asset.id)) {
      return;
    }
    _dragSelectionTouchedIds.add(asset.id);
    final isSelected = selectedAssetIds.contains(asset.id);
    if (isSelected == targetValue) return;
    setState(() {
      if (targetValue) {
        selectedAssetIds.add(asset.id);
      } else {
        selectedAssetIds.remove(asset.id);
      }
    });
  }

  void _updateDragSelection(
    Offset globalPosition,
    List<AssetEntity> assets,
    int tab,
  ) {
    _lastDragGlobalPosition = globalPosition;
    if (_dragSelectionTargetValue == null) return;

    for (final asset in assets) {
      final key = _gridTileKeys['t${tab}_${asset.id}'];
      final ctx = key?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.inflate(4).contains(globalPosition)) {
        _applyDragSelection(asset);
        break;
      }
    }

    _updateDragAutoScroll(globalPosition, assets, tab);
  }

  void _endDragSelection() {
    _dragSelectionTargetValue = null;
    _dragSelectionTouchedIds.clear();
    _lastDragGlobalPosition = null;
    _dragAutoScrollVelocity = 0;
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
  }

  void _updateDragAutoScroll(
    Offset globalPosition,
    List<AssetEntity> assets,
    int tab,
  ) {
    final controller =
        tab == 0 ? _photoScrollController : _videoScrollController;
    if (!controller.hasClients) return;

    final scrollCtx = controller.position.context.notificationContext;
    if (scrollCtx == null) return;
    final box = scrollCtx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final rect = box.localToGlobal(Offset.zero) & box.size;
    const edgeThreshold = 92.0;
    double velocity = 0;

    if (globalPosition.dy < rect.top + edgeThreshold) {
      velocity =
          -(((rect.top + edgeThreshold) - globalPosition.dy) / edgeThreshold)
              .clamp(0.2, 1.0) *
          18;
    } else if (globalPosition.dy > rect.bottom - edgeThreshold) {
      velocity =
          (((globalPosition.dy - (rect.bottom - edgeThreshold)) / edgeThreshold)
              .clamp(0.2, 1.0)) *
          18;
    }

    if (velocity == 0) {
      _dragAutoScrollVelocity = 0;
      _dragAutoScrollTimer?.cancel();
      _dragAutoScrollTimer = null;
      return;
    }

    _dragAutoScrollVelocity = velocity;
    _dragAutoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final dragPos = _lastDragGlobalPosition;
      final ctrl = tab == 0 ? _photoScrollController : _videoScrollController;
      if (_dragSelectionTargetValue == null ||
          !ctrl.hasClients ||
          dragPos == null) {
        _dragAutoScrollTimer?.cancel();
        _dragAutoScrollTimer = null;
        return;
      }

      final pos = ctrl.position;
      final nextOffset = (pos.pixels + _dragAutoScrollVelocity).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if ((nextOffset - pos.pixels).abs() < 0.1) return;
      ctrl.jumpTo(nextOffset);
      _updateDragSelection(dragPos, assets, tab);
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Route helper
  // ══════════════════════════════════════════════════════════════════════════

  Route<T> _cinematicRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => page,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Image building (same pattern as gallery_screen.buildImage)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildThumb(AssetEntity asset, [int size = _thumbPx]) {
    final id = '${asset.id}@$size';
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerHighest,
            colorScheme.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );

    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      return placeholder;
    }

    final provider = _thumbCache.putIfAbsent(
      id,
      () => AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: ThumbnailSize.square(size),
        thumbnailFormat: ThumbnailFormat.jpeg,
      ),
    );
    return Image(
      image: provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
      frameBuilder: (_, child, frame, sync) {
        if (sync || frame != null) return child;
        return placeholder;
      },
      errorBuilder: (_, __, ___) => placeholder,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final topBarColor =
        isDark ? const Color(0xFF120C24) : const Color(0xFFF1E8FF);
    final overlayStyle =
        isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: isSelectionMode
            ? IconButton(
                tooltip: 'Close selection',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => selectedAssetIds.clear()),
              )
            : null,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            isSelectionMode
                ? '${selectedAssetIds.length} selected'
                : widget.title,
            key: ValueKey('${widget.title}-${selectedAssetIds.length}'),
          ),
        ),
        backgroundColor: topBarColor,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle.copyWith(
          statusBarColor: topBarColor,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        actions: [
          if (isSelectionMode) ...[
            IconButton(
              tooltip: 'Favorite',
              icon: const Icon(Icons.favorite_border_rounded),
              onPressed: _toggleFavoriteAll,
            ),
            IconButton(
              tooltip: 'Move to Safe Folder',
              icon: const Icon(Icons.lock_outline_rounded),
              onPressed: _moveToVault,
            ),
            IconButton(
              tooltip: 'Move to Recycle Bin',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _moveToRecycleBin,
            ),
            IconButton(
              tooltip: 'Selection actions',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: _showSelectionMenu,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // Background gradient
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
          // Decorative orb
          Positioned(
            top: -70,
            right: -30,
            child: IgnorePointer(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFA855F7)
                      .withOpacity(isDark ? 0.18 : 0.24),
                ),
              ),
            ),
          ),
          // Main content card
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
            child: GlassContainer(
              borderRadius: BorderRadius.circular(30),
              child: _buildPinchWrapper(isDark),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Pinch wrapper – exact copy of gallery_screen's buildGridView Listener +
  // GestureDetector, but scoped to the album.
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPinchWrapper(bool isDark) {
    return Listener(
      onPointerDown: (_) {
        final was = _isPinching;
        _activePointers++;
        if (!was && _isPinching) setState(() {});
      },
      onPointerUp: (_) {
        final was = _isPinching;
        _activePointers = (_activePointers - 1).clamp(0, 20);
        if (was && !_isPinching) setState(() {});
      },
      onPointerCancel: (_) {
        final was = _isPinching;
        _activePointers = (_activePointers - 1).clamp(0, 20);
        if (was && !_isPinching) setState(() {});
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) {
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
          int nextCount = albumGridCount;
          var acc = _pinchAccumulator;

          if (acc >= pinchStepOutThreshold && nextCount > 2) {
            nextCount--;
            acc /= pinchStepOutThreshold;
          } else if (acc <= pinchStepInThreshold && nextCount < 6) {
            nextCount++;
            acc /= pinchStepInThreshold;
          }

          _pinchAccumulator = acc.clamp(0.75, 1.25).toDouble();
          if (nextCount == albumGridCount) return;

          final now = DateTime.now();
          if (now.difference(_lastGridStepAt).inMilliseconds <
              pinchStepCooldownMs) return;

          setState(() {
            albumGridCount = nextCount;
            _lastGridStepAt = now;
          });
          // Schedule warmup after the new grid has been laid out
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scheduleThumbnailWarmup();
          });
          _pinchStepConsumed = true;
        },
        onScaleEnd: (_) {
          _lastPinchScale = 1.0;
          _pinchAccumulator = 1.0;
          _pinchStepConsumed = false;
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: _buildTabToggle(isDark),
            ),
            Expanded(child: _buildTabPages()),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tab pages – a simple PageView. Each page owns the correct scroll controller
  // and is keyed by its own tab index so Flutter never confuses them.
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTabPages() {
    return PageView(
      controller: _pageController,
      physics: _isPinching
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      onPageChanged: (index) {
        setState(() {
          selectedMediaTab = index;
          // Clear selection when switching tabs but keep grid size
          selectedAssetIds.clear();
          _gridTileKeys.clear();
        });
        // Warm up thumbnails for the newly revealed tab
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scheduleThumbnailWarmup();
        });
      },
      children: [
        // Page 0 – Photos (always uses _photoScrollController)
        _buildGrid(
          assets: albumImages,
          scrollController: _photoScrollController,
          tab: 0,
        ),
        // Page 1 – Videos (always uses _videoScrollController)
        _buildGrid(
          assets: albumVideos,
          scrollController: _videoScrollController,
          tab: 1,
          isLoading: isLoadingVideos,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Grid – receives its scroll controller and tab index explicitly.
  // The grid itself never reads `selectedMediaTab` so there is no stale-state
  // risk when both pages are alive inside PageView.
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildGrid({
    required List<AssetEntity> assets,
    required ScrollController scrollController,
    required int tab,
    bool isLoading = false,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (assets.isEmpty) {
      return Center(
        child: Text(
          tab == 0 ? 'No photos in this album' : 'No videos in this album',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.7),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return GridView.builder(
      // No ValueKey here – we never want the grid to be recreated during a
      // pinch, which would reset scroll position and cause jank.
      controller: scrollController,
      padding: const EdgeInsets.all(10),
      cacheExtent: 1500,
      physics: _isPinching
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: albumGridCount,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        // Tab-prefixed key avoids GlobalKey conflicts when the same asset
        // appears in both Photos and Videos tabs.
        final tileKey =
            _gridTileKeys.putIfAbsent('t${tab}_${asset.id}', GlobalKey.new);

        final previewProvider = _thumbCache.putIfAbsent(
          '${asset.id}@$_thumbPx',
          () => AssetEntityImageProvider(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(_thumbPx),
            thumbnailFormat: ThumbnailFormat.jpeg,
          ),
        );

        return RepaintBoundary(
          child: GestureDetector(
            key: tileKey,
            onLongPress: () {},
            onLongPressStart: (_) => _startDragSelection(asset, tab),
            onLongPressMoveUpdate: (d) =>
                _updateDragSelection(d.globalPosition, assets, tab),
            onLongPressEnd: (_) => _endDragSelection(),
            onTap: () async {
              if (isSelectionMode) {
                setState(() {
                  if (!selectedAssetIds.add(asset.id)) {
                    selectedAssetIds.remove(asset.id);
                  }
                });
                return;
              }

              if (asset.type == AssetType.video || tab == 1) {
                // ── Video viewer ──────────────────────────────────────────
                final videos =
                    tab == 1 ? albumVideos : [asset];
                final videoIndex = videos.indexWhere((e) => e.id == asset.id);
                final viewerAction = await Navigator.push<String>(
                  context,
                  _cinematicRoute(
                    VideoViewerScreen(
                      videos: videos,
                      initialIndex: videoIndex < 0 ? 0 : videoIndex,
                    ),
                  ),
                );
                if ((viewerAction == 'recycle' || viewerAction == 'vault') &&
                    mounted) {
                  setState(() {
                    albumVideos = albumVideos
                        .where((v) => v.id != asset.id)
                        .toList(growable: false);
                  });
                }
              } else {
                // ── Photo viewer ──────────────────────────────────────────
                final openingProvider =
                    ViewerScreen.openingImageProvider(context, asset);
                unawaited(precacheImage(openingProvider, context));
                final dynamic result = await Navigator.push<dynamic>(
                  context,
                  _cinematicRoute(
                    ViewerScreen(
                      images: albumImages,
                      index: index,
                      initialPreviewProvider: previewProvider,
                      initialViewerProvider: openingProvider,
                    ),
                  ),
                );

                if (result == null || !mounted) return;

                if (result is AssetEntity) {
                  setState(() => albumImages.insert(0, result));
                  return;
                }

                final action = result is String ? result : '';
                if (action == 'recycle' || action == 'vault') {
                  setState(() {
                    albumImages = albumImages
                        .where((img) => img.id != asset.id)
                        .toList(growable: false);
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Removed from album'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  }
                }
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: asset.id,
                    child: _buildThumb(asset),
                  ),
                  // Video badge
                  if (asset.type == AssetType.video || tab == 1)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  // Selection overlay
                  if (selectedAssetIds.contains(asset.id))
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.check_circle, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Tab toggle (Photos / Videos pill)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTabToggle(bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF211A33);
    return GlassContainer(
      borderRadius: BorderRadius.circular(24),
      enableBlur: false,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: _tabButton(
                label: 'Photos',
                count: albumImages.length,
                selected: selectedMediaTab == 0,
                textColor: textColor,
                onTap: () {
                  if (selectedMediaTab == 0) return;
                  _pageController.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _tabButton(
                label: 'Videos',
                count: albumVideos.length,
                selected: selectedMediaTab == 1,
                textColor: textColor,
                loading: isLoadingVideos,
                onTap: () {
                  if (selectedMediaTab == 1) return;
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required int count,
    required bool selected,
    required Color textColor,
    required VoidCallback onTap,
    bool loading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.28)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              if (loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: textColor,
                  ),
                )
              else
                Text(
                  '$count',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.72),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Data loading
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadInitialAlbumVideos() async {
    setState(() => isLoadingVideos = true);
    final videos = await service.fetchAlbumVideos(
      widget.album,
      page: 0,
      size: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      albumVideos = videos;
      _currentVideoPage = videos.isEmpty ? -1 : 0;
      _hasMoreVideos = videos.length == _pageSize;
      isLoadingVideos = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (selectedMediaTab == 1) _scheduleThumbnailWarmup();
    });
  }

  Future<void> _syncPhotoPaginationState() async {
    final count = await widget.album.assetCountAsync;
    if (!mounted) return;
    setState(() {
      _hasMorePhotos = count > albumImages.length;
    });
  }

  Future<void> _loadMoreAlbumPhotos() async {
    if (_isLoadingMorePhotos || !_hasMorePhotos) return;
    _isLoadingMorePhotos = true;
    try {
      final nextPage = _currentPhotoPage + 1;
      final photos = await service.fetchAlbumImages(
        widget.album,
        page: nextPage,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        albumImages.addAll(
          photos.where((asset) => !albumImages.any((e) => e.id == asset.id)),
        );
        _currentPhotoPage = nextPage;
        _hasMorePhotos = photos.length == _pageSize;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || selectedMediaTab != 0) return;
        _scheduleThumbnailWarmup();
      });
    } finally {
      _isLoadingMorePhotos = false;
    }
  }

  Future<void> _loadMoreAlbumVideos() async {
    if (_isLoadingMoreVideos || !_hasMoreVideos) return;
    _isLoadingMoreVideos = true;
    try {
      final nextPage = _currentVideoPage + 1;
      final videos = await service.fetchAlbumVideos(
        widget.album,
        page: nextPage,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        albumVideos.addAll(
          videos.where((asset) => !albumVideos.any((e) => e.id == asset.id)),
        );
        _currentVideoPage = nextPage;
        _hasMoreVideos = videos.length == _pageSize;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || selectedMediaTab != 1) return;
        _scheduleThumbnailWarmup();
      });
    } finally {
      _isLoadingMoreVideos = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Selection helpers
  // ══════════════════════════════════════════════════════════════════════════

  void _toggleSelectAll() {
    final assets = visibleAssets;
    if (assets.isEmpty || isRecycleActionInProgress) return;
    final ids = assets.map((a) => a.id).toSet();
    final allSelected = ids.every(selectedAssetIds.contains);
    setState(() {
      if (allSelected) {
        selectedAssetIds.removeAll(ids);
      } else {
        selectedAssetIds.addAll(ids);
      }
      _gridTileKeys.clear();
    });
  }

  Future<void> _showSelectionMenu() async {
    final colorScheme = Theme.of(context).colorScheme;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SelectionMenu',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = Curves.easeOutBack;
        final curvedAnimation = CurvedAnimation(parent: animation, curve: curve);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          alignment: Alignment.topRight,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogContext),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              right: 16,
              child: GlassContainer(
                borderRadius: BorderRadius.circular(24),
                blurSigma: 22,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          child: SelectionContainer.disabled(
                            child: Text(
                              '${selectedAssetIds.length} selected',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Divider(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                            height: 1,
                          ),
                        ),
                        _buildMenuTile(
                          Icons.share_rounded,
                          'Share',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            _shareSelected();
                          },
                        ),
                        _buildMenuTile(
                          Icons.favorite_rounded,
                          'Favorite',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            _toggleFavoriteAll();
                          },
                        ),
                        _buildMenuTile(
                          Icons.visibility_off_rounded,
                          'Move to Vault',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            _moveToVault();
                          },
                        ),
                        _buildMenuTile(
                          Icons.delete_rounded,
                          'Recycle Bin',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            _moveToRecycleBin();
                          },
                          isDestructive: true,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          child: Divider(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                            height: 1,
                          ),
                        ),
                        _buildMenuTile(
                          Icons.select_all_rounded,
                          'Select All',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            _toggleSelectAll();
                          },
                        ),
                        _buildMenuTile(
                          Icons.deselect_rounded,
                          'Deselect All',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            setState(() => selectedAssetIds.clear());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuTile(
    IconData icon,
    String label,
    ColorScheme colorScheme,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      splashColor: (isDestructive ? colorScheme.error : colorScheme.primary).withValues(alpha: 0.12),
      highlightColor: (isDestructive ? colorScheme.error : colorScheme.primary).withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDestructive ? colorScheme.error : colorScheme.onSurface.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isDestructive ? colorScheme.error : colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareSelected() async {
    final ids = selectedAssetIds.toSet();
    if (ids.isEmpty) return;

    final List<AssetEntity> toShare = [];
    toShare.addAll(albumImages.where((a) => ids.contains(a.id)));
    toShare.addAll(albumVideos.where((a) => ids.contains(a.id)));

    final List<XFile> files = [];
    for (final asset in toShare) {
      final f = await asset.file;
      if (f != null) files.add(XFile(f.path));
    }

    if (files.isNotEmpty) {
      await Share.shareXFiles(files);
    }
    setState(() => selectedAssetIds.clear());
  }

  Future<void> _moveToVault() async {
    final ids = selectedAssetIds.toSet();
    if (ids.isEmpty) return;

    final shouldMove = await _confirmVault(ids.length);
    if (!shouldMove) return;

    final List<AssetEntity> toMove = [];
    toMove.addAll(albumImages.where((a) => ids.contains(a.id)));
    toMove.addAll(albumVideos.where((a) => ids.contains(a.id)));

    try {
      for (final asset in toMove) {
        await vaultService.moveAssetToVault(asset);
      }
      setState(() {
        albumImages = albumImages.where((a) => !ids.contains(a.id)).toList();
        albumVideos = albumVideos.where((a) => !ids.contains(a.id)).toList();
        selectedAssetIds.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} moved to Safe Folder'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to move some items to Vault'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleFavoriteAll() async {
    final ids = selectedAssetIds.toSet();
    if (ids.isEmpty) return;

    final List<AssetEntity> toFav = [];
    toFav.addAll(albumImages.where((a) => ids.contains(a.id)));
    toFav.addAll(albumVideos.where((a) => ids.contains(a.id)));

    bool anyAdded = false;
    for (final asset in toFav) {
      final isFav = await FavoritesDatabase.instance.isFavorite(asset.id);
      if (isFav) {
        await FavoritesDatabase.instance.removeFavorite(asset.id);
      } else {
        await FavoritesDatabase.instance.addFavorite(asset.id);
        anyAdded = true;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(anyAdded ? 'Added to Favorites' : 'Removed from Favorites'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    setState(() => selectedAssetIds.clear());
  }

  Future<bool> _confirmVault(int count) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(34),
            blurSigma: 18,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.32),
                        ),
                        child: Icon(Icons.visibility_off_rounded, color: colorScheme.onSurface),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Move to Safe Folder?',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Moved items will be hidden from the gallery and require your vault password to view.',
                    style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.76), height: 1.42),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: const Text('Move'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Recycle bin
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _moveToRecycleBin() async {
    final ids = selectedAssetIds.toSet();
    if (ids.isEmpty || isRecycleActionInProgress) return;

    final shouldMove = await _confirmRecycle(ids.length);
    if (!shouldMove || !mounted) return;

    setState(() => isRecycleActionInProgress = true);
    try {
      await recycleBinDatabase.addAssets(
        albumImages.where((a) => ids.contains(a.id)).toList(),
      );
      if (!mounted) return;
      setState(() {
        albumImages = albumImages
            .where((a) => !ids.contains(a.id))
            .toList(growable: false);
        albumVideos = albumVideos
            .where((a) => !ids.contains(a.id))
            .toList(growable: false);
        selectedAssetIds.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                  '${ids.length} item${ids.length == 1 ? '' : 's'} moved to recycle bin'),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => isRecycleActionInProgress = false);
    }
  }

  Future<bool> _confirmRecycle(int count) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(34),
            blurSigma: 18,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white
                              .withValues(alpha: dark ? 0.12 : 0.32),
                        ),
                        child: Icon(Icons.delete_outline_rounded,
                            color: cs.onSurface),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Move To Recycle Bin?',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    count == 1
                        ? 'This item will be moved to the recycle bin and can be restored later.'
                        : '$count items will be moved to the recycle bin and can be restored later.',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.76),
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Move'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }
}
