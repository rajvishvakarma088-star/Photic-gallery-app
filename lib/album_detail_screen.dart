import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'glass_container.dart';
import 'services/gallery_service.dart';
import 'services/recycle_bin_database.dart';
import 'theme_provider.dart';
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
  static const double pinchStepOutThreshold = 1.08;
  static const double pinchStepInThreshold = 0.92;
  static const int pinchStepCooldownMs = 55;
  final GalleryService service = GalleryService();
  final RecycleBinDatabase recycleBinDatabase = RecycleBinDatabase.instance;
  final PageController mediaPageController = PageController();
  final ScrollController photoScrollController = ScrollController();
  final ScrollController videoScrollController = ScrollController();
  final Map<String, AssetEntityImageProvider> thumbnailProviderCache = {};
  final Map<String, GlobalKey> _gridTileKeys = {};
  final Set<String> selectedAssetIds = {};
  late List<AssetEntity> albumImages;
  List<AssetEntity> albumVideos = [];
  int albumGridCount = 3;
  int selectedMediaTab = 0;
  double _lastPinchScale = 1.0;
  double _pinchAccumulator = 1.0;
  int _activePointers = 0;
  DateTime _lastGridStepAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pinchStepConsumed = false;
  bool isRecycleActionInProgress = false;
  bool isLoadingVideos = false;
  bool? _dragSelectionTargetValue;
  final Set<String> _dragSelectionTouchedIds = {};
  Timer? _dragAutoScrollTimer;
  double _dragAutoScrollVelocity = 0;
  Offset? _lastDragGlobalPosition;
  Timer? _thumbnailWarmupTimer;

  bool get _isPinching => _activePointers >= 2;
  bool get isSelectionMode => selectedAssetIds.isNotEmpty;
  List<AssetEntity> get visibleAssets =>
      selectedMediaTab == 0 ? albumImages : albumVideos;

  int get albumThumbPx {
    return 180;
  }

  Route<T> buildCinematicRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => page,
    );
  }

  Widget buildImage(AssetEntity asset) {
    return buildImageWithSize(asset, albumThumbPx);
  }

  void _toggleSelectAllInCurrentTab() {
    final assets = visibleAssets;
    if (assets.isEmpty || isRecycleActionInProgress) return;
    final assetIds = assets.map((asset) => asset.id).toSet();
    final allSelected = assetIds.every(selectedAssetIds.contains);

    setState(() {
      if (allSelected) {
        selectedAssetIds.removeAll(assetIds);
      } else {
        selectedAssetIds.addAll(assetIds);
      }
      _gridTileKeys.clear();
    });
  }

  void _startDragSelection(AssetEntity asset) {
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

  ScrollController get _activeGridScrollController =>
      selectedMediaTab == 0 ? photoScrollController : videoScrollController;

  void _updateDragSelection(Offset globalPosition, List<AssetEntity> assets) {
    _lastDragGlobalPosition = globalPosition;
    final targetValue = _dragSelectionTargetValue;
    if (targetValue == null) return;

    for (final asset in assets) {
      final key = _gridTileKeys[asset.id];
      final context = key?.currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPosition)) {
        _applyDragSelection(asset);
        break;
      }
    }

    _updateDragAutoScroll(globalPosition, assets);
  }

  void _endDragSelection() {
    _dragSelectionTargetValue = null;
    _dragSelectionTouchedIds.clear();
    _lastDragGlobalPosition = null;
    _dragAutoScrollVelocity = 0;
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
  }

  void _updateDragAutoScroll(Offset globalPosition, List<AssetEntity> assets) {
    final controller = _activeGridScrollController;
    if (!controller.hasClients) return;

    final scrollContext = controller.position.context.notificationContext;
    if (scrollContext == null) return;
    final box = scrollContext.findRenderObject() as RenderBox?;
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
    _dragAutoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (
      _,
    ) {
      final dragPosition = _lastDragGlobalPosition;
      if (_dragSelectionTargetValue == null ||
          !_activeGridScrollController.hasClients ||
          dragPosition == null) {
        _dragAutoScrollTimer?.cancel();
        _dragAutoScrollTimer = null;
        return;
      }

      final position = _activeGridScrollController.position;
      final nextOffset = (position.pixels + _dragAutoScrollVelocity).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      if ((nextOffset - position.pixels).abs() < 0.1) return;
      _activeGridScrollController.jumpTo(nextOffset);
      _updateDragSelection(dragPosition, assets);
    });
  }

  @override
  void initState() {
    super.initState();
    albumImages = List<AssetEntity>.from(widget.images);
    photoScrollController.addListener(_onGridScroll);
    videoScrollController.addListener(_onGridScroll);
    unawaited(_loadAlbumVideos());
  }

  void _onGridScroll() {
    _scheduleThumbnailWarmup();
  }

  void _scheduleThumbnailWarmup() {
    if (!mounted) return;
    _thumbnailWarmupTimer?.cancel();
    _thumbnailWarmupTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _warmVisibleThumbnailBand();
    });
  }

  void _warmVisibleThumbnailBand() {
    if (!mounted) return;
    final controller =
        selectedMediaTab == 0 ? photoScrollController : videoScrollController;
    final assets = selectedMediaTab == 0 ? albumImages : albumVideos;
    if (!controller.hasClients || assets.isEmpty) return;

    final viewportWidth = MediaQuery.of(context).size.width;
    const gridHorizontalPadding = 20.0;
    const spacing = 6.0;
    final contentWidth =
        viewportWidth - gridHorizontalPadding - (albumGridCount - 1) * spacing;
    final tileExtent = (contentWidth / albumGridCount) + spacing;

    final scrollOffset = controller.offset;
    final viewportHeight = controller.position.viewportDimension;

    final firstRow = (scrollOffset / tileExtent).floor();
    final visibleRows = (viewportHeight / tileExtent).ceil() + 2;

    final startIndex = (firstRow * albumGridCount).clamp(0, assets.length);
    final endIndex = ((firstRow + visibleRows + 4) * albumGridCount)
        .clamp(0, assets.length);

    for (int i = startIndex; i < endIndex; i++) {
      final asset = assets[i];
      final id = '${asset.id}@$albumThumbPx';
      if (!thumbnailProviderCache.containsKey(id)) {
        final provider = AssetEntityImageProvider(
          asset,
          isOriginal: false,
          thumbnailSize: ThumbnailSize.square(albumThumbPx),
          thumbnailFormat: ThumbnailFormat.jpeg,
        );
        thumbnailProviderCache[id] = provider;
        unawaited(precacheImage(provider, context));
      }
    }
  }

  @override
  void dispose() {
    _thumbnailWarmupTimer?.cancel();
    _dragAutoScrollTimer?.cancel();
    photoScrollController.removeListener(_onGridScroll);
    videoScrollController.removeListener(_onGridScroll);
    _gridTileKeys.clear();
    photoScrollController.dispose();
    videoScrollController.dispose();
    mediaPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final topBarColor = isDark
        ? const Color(0xFF120C24)
        : const Color(0xFFF1E8FF);

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: isSelectionMode
            ? IconButton(
                tooltip: 'Close selection',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  setState(() {
                    selectedAssetIds.clear();
                  });
                },
              )
            : null,
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
          if (isSelectionMode)
            IconButton(
              tooltip:
                  visibleAssets.isNotEmpty &&
                      visibleAssets.every(
                        (asset) => selectedAssetIds.contains(asset.id),
                      )
                  ? 'Deselect all'
                  : 'Select all',
              icon: Icon(
                visibleAssets.isNotEmpty &&
                        visibleAssets.every(
                          (asset) => selectedAssetIds.contains(asset.id),
                        )
                    ? Icons.remove_done_rounded
                    : Icons.select_all_rounded,
              ),
              onPressed: _toggleSelectAllInCurrentTab,
            ),
          if (isSelectionMode)
            IconButton(
              tooltip: 'Move to recycle bin',
              icon: const Icon(Icons.delete_rounded),
              onPressed: isRecycleActionInProgress
                  ? null
                  : _moveSelectionToRecycleBin,
            ),
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
            top: -70,
            right: -30,
            child: IgnorePointer(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFFA855F7,
                  ).withOpacity(isDark ? 0.18 : 0.24),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
            child: GlassContainer(
              borderRadius: BorderRadius.circular(30),
              child: Listener(
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
                    int nextCount = albumGridCount;
                    var updatedAccumulator = _pinchAccumulator;

                    if (updatedAccumulator >= pinchStepOutThreshold &&
                        nextCount > 2) {
                      nextCount--;
                      updatedAccumulator /= pinchStepOutThreshold;
                    } else if (updatedAccumulator <= pinchStepInThreshold &&
                        nextCount < 6) {
                      nextCount++;
                      updatedAccumulator /= pinchStepInThreshold;
                    }

                    _pinchAccumulator = updatedAccumulator
                        .clamp(0.75, 1.25)
                        .toDouble();
                    if (nextCount == albumGridCount) return;

                    final now = DateTime.now();
                    if (now.difference(_lastGridStepAt).inMilliseconds <
                        pinchStepCooldownMs) {
                      return;
                    }

                    setState(() {
                      albumGridCount = nextCount;
                      _lastGridStepAt = now;
                    });
                    _pinchStepConsumed = true;
                  },
                  onScaleEnd: (details) {
                    _lastPinchScale = 1.0;
                    _pinchAccumulator = 1.0;
                    _pinchStepConsumed = false;
                  },
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                        child: _buildMediaToggle(isDark),
                      ),
                      Expanded(
                        child: PageView(
                          controller: mediaPageController,
                          onPageChanged: (index) {
                            setState(() {
                              selectedMediaTab = index;
                              selectedAssetIds.clear();
                              _gridTileKeys.clear();
                            });
                          },
                          children: [
                            _buildAssetGrid(albumImages),
                            _buildAssetGrid(albumVideos),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildImageWithSize(AssetEntity asset, int size) {
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

    final provider = thumbnailProviderCache.putIfAbsent(
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
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return placeholder;
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }

  Widget _buildAssetGrid(List<AssetEntity> assets) {
    return GridView.builder(
      key: ValueKey(
        'album-grid-$albumGridCount-$selectedMediaTab-${assets.length}',
      ),
      controller: selectedMediaTab == 0
          ? photoScrollController
          : videoScrollController,
      padding: const EdgeInsets.all(10),
      cacheExtent: 1500,
      itemCount: assets.length,
      physics: _isPinching
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: albumGridCount,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final asset = assets[index];
        final tileKey = _gridTileKeys.putIfAbsent(asset.id, GlobalKey.new);
        final ImageProvider<Object> previewProvider = thumbnailProviderCache
            .putIfAbsent(
              '${asset.id}@$albumThumbPx',
              () => AssetEntityImageProvider(
                asset,
                isOriginal: false,
                thumbnailSize: ThumbnailSize.square(albumThumbPx),
                thumbnailFormat: ThumbnailFormat.jpeg,
              ),
            );
        return _AlbumReveal(
          order: index,
          child: RepaintBoundary(
            child: GestureDetector(
              key: tileKey,
              onLongPress: () {},
              onLongPressStart: (_) {
                _startDragSelection(asset);
              },
              onLongPressMoveUpdate: (details) {
                _updateDragSelection(details.globalPosition, assets);
              },
              onLongPressEnd: (_) {
                _endDragSelection();
              },
              onTap: () async {
                if (isSelectionMode) {
                  setState(() {
                    if (!selectedAssetIds.add(asset.id)) {
                      selectedAssetIds.remove(asset.id);
                    }
                  });
                  return;
                }

                if (asset.type == AssetType.video) {
                  final viewerAction = await Navigator.push<String>(
                    context,
                    buildCinematicRoute(
                      VideoViewerScreen(
                        videos: albumVideos,
                        initialIndex: index,
                      ),
                    ),
                  );
                  if ((viewerAction != 'recycle' && viewerAction != 'vault') ||
                      !mounted) {
                    return;
                  }
                  setState(() {
                    albumVideos = albumVideos
                        .where((item) => item.id != asset.id)
                        .toList(growable: false);
                  });
                } else {
                  final openingProvider = ViewerScreen.openingImageProvider(
                    context,
                    asset,
                  );
                  unawaited(precacheImage(openingProvider, context));
                  final dynamic result = await Navigator.push<dynamic>(
                    context,
                    buildCinematicRoute(
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
                    setState(() {
                      albumImages.insert(0, result);
                    });
                    return;
                  }

                  final String viewerAction = result is String ? result : '';
                  if (viewerAction != 'recycle' && viewerAction != 'vault') {
                    return;
                  }
                  setState(() {
                    albumImages = albumImages
                        .where((item) => item.id != asset.id)
                        .toList(growable: false);
                  });
                }

                ScaffoldMessenger.of(this.context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Removed from gallery'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: asset.id,
                      child: buildImageWithSize(asset, albumThumbPx),
                    ),
                    if (asset.type == AssetType.video)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
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
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaToggle(bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF211A33);
    return GlassContainer(
      borderRadius: BorderRadius.circular(24),
      enableBlur: false,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: _buildMediaTabButton(
                label: 'Photos',
                count: albumImages.length,
                selected: selectedMediaTab == 0,
                textColor: textColor,
                onTap: () {
                  if (selectedMediaTab == 0) return;
                  mediaPageController.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildMediaTabButton(
                label: 'Videos',
                count: albumVideos.length,
                selected: selectedMediaTab == 1,
                textColor: textColor,
                loading: isLoadingVideos,
                onTap: () {
                  if (selectedMediaTab == 1) return;
                  mediaPageController.animateToPage(
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

  Widget _buildMediaTabButton({
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

  Future<void> _loadAlbumVideos() async {
    setState(() {
      isLoadingVideos = true;
    });

    final videos = await service.fetchAlbumVideos(widget.album);
    if (!mounted) return;

    setState(() {
      albumVideos = videos;
      isLoadingVideos = false;
    });
  }

  Future<bool> _confirmMoveToRecycleBin(int count) async {
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
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.12 : 0.32,
                          ),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Move To Recycle Bin?',
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
                    count == 1
                        ? 'This item will be moved to the recycle bin and can be restored later.'
                        : '$count items will be moved to the recycle bin and can be restored later.',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.76),
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
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

  Future<void> _moveSelectionToRecycleBin() async {
    final ids = selectedAssetIds.toSet();
    if (ids.isEmpty || isRecycleActionInProgress) return;

    final shouldMove = await _confirmMoveToRecycleBin(ids.length);
    if (!shouldMove || !mounted) return;

    setState(() {
      isRecycleActionInProgress = true;
    });
    try {
      await recycleBinDatabase.addAssets(
        albumImages.where((asset) => ids.contains(asset.id)).toList(),
      );
      if (!mounted) return;

      setState(() {
        albumImages = albumImages
            .where((asset) => !ids.contains(asset.id))
            .toList(growable: false);
        albumVideos = albumVideos
            .where((asset) => !ids.contains(asset.id))
            .toList(growable: false);
        selectedAssetIds.clear();
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${ids.length} item${ids.length == 1 ? '' : 's'} moved to recycle bin',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          isRecycleActionInProgress = false;
        });
      }
    }
  }
}

class _AlbumReveal extends StatelessWidget {
  const _AlbumReveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = order.clamp(0, 10).toInt() * 24;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 340 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, builtChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: Transform.scale(
              scale: 0.99 + (value * 0.01),
              child: builtChild,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
