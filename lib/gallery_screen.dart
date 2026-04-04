import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'album_detail_screen.dart';
import 'gallery/gallery_album_widgets.dart' as gallery_album_widgets;
import 'gallery/gallery_grid_widgets.dart' as gallery_grid_widgets;
import 'gallery/gallery_section.dart';
import 'gallery/gallery_section_builder.dart';
import 'glass_container.dart';
import 'services/favorites_database.dart';
import 'services/gallery_service.dart';
import 'services/recycle_bin_database.dart';
import 'viewer_screen.dart';
import 'video_viewer_screen.dart';
import 'vault_lock_screen.dart';
import 'services/vault_service.dart';
import 'services/music_service.dart';
import 'theme_provider.dart';
import 'music_screen.dart';
import 'services/audio_player_service.dart';
import 'mini_music_player.dart';
import 'music_player_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with WidgetsBindingObserver {
  final GalleryService service = GalleryService();
  final FavoritesDatabase favoritesDatabase = FavoritesDatabase.instance;
  final RecycleBinDatabase recycleBinDatabase = RecycleBinDatabase.instance;
  late AudioPlayerService audioPlayerService;
  final ScrollController scrollController = ScrollController();
  final ScrollController videosScrollController = ScrollController();
  final ScrollController favoritesScrollController = ScrollController();
  final ScrollController albumsScrollController = ScrollController();
  final ScrollController recycleBinScrollController = ScrollController();
  final ScrollController musicScrollController = ScrollController();
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
  List<AssetEntity> recycleBinItems = [];
  final Map<String, RecycleBinItem> recycleBinRecords = {};
  List<AlbumSummary> albums = [];
  final Set<String> favorites = {};
  final Set<String> animating = {};
  final Set<String> recycleBinIds = {};
  final Set<String> selectedAssetIds = {};
  final Map<String, GlobalKey> _gridTileKeys = {};
  int? _dragSelectionStartIndex;
  Set<String>? _dragSelectionInitialIds;

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
  bool isLoadingRecycleBin = true;
  bool isRecycleActionInProgress = false;
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
  bool? _dragSelectionTargetValue;
  final Set<String> _dragSelectionTouchedIds = {};
  Timer? _dragAutoScrollTimer;
  double _dragAutoScrollVelocity = 0;
  Offset? _lastDragGlobalPosition;
  List<AssetEntity>? _prefetchedImages;
  int? _prefetchedPage;
  Timer? _thumbnailWarmupTimer;
  Timer? _vaultHoldTimer;
  int _lastWarmedStart = -1;
  int _lastWarmedEnd = -1;
  bool _isVaultEntryPressing = false;
  bool _isOpeningVault = false;
  final Set<AssetEntity> _pendingAssets = {};

  bool get _isPinching => _activePointers >= 2;
  bool get isSelectionMode => selectedAssetIds.isNotEmpty;

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
    audioPlayerService = AudioPlayerService();
    WidgetsBinding.instance.addObserver(this);
    scrollController.addListener(onScroll);
    videosScrollController.addListener(onScroll);
    recycleBinScrollController.addListener(onScroll);
    loadFavorites();
    unawaited(loadRecycleBin());
    unawaited(loadInitialMediaData());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _thumbnailWarmupTimer?.cancel();
    _dragAutoScrollTimer?.cancel();
    _vaultHoldTimer?.cancel();
    thumbnailProviderCache.clear();
    _gridTileKeys.clear();
    scrollController.dispose();
    videosScrollController.dispose();
    favoritesScrollController.dispose();
    albumsScrollController.dispose();
    recycleBinScrollController.dispose();
    musicScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(VaultService.instance.lock());
      return;
    }
    service.clearCache();
    _gridTileKeys.clear();
    clearSelection();
    loadFavorites();
    unawaited(loadRecycleBin());
    unawaited(loadInitialMediaData());
  }

  void _startVaultEntryPress() {
    if (selectedIndex != 0 || isSelectionMode || _isOpeningVault) return;
    _vaultHoldTimer?.cancel();
    setState(() {
      _isVaultEntryPressing = true;
    });
    _vaultHoldTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      await _openVault();
    });
  }

  void _cancelVaultEntryPress() {
    _vaultHoldTimer?.cancel();
    if (!_isVaultEntryPressing) return;
    setState(() {
      _isVaultEntryPressing = false;
    });
  }

  Future<void> _openVault() async {
    if (_isOpeningVault) return;
    _vaultHoldTimer?.cancel();
    setState(() {
      _isOpeningVault = true;
      _isVaultEntryPressing = false;
    });

    final changed = await Navigator.push<bool>(
      context,
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: const VaultLockScreen(),
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      _isOpeningVault = false;
    });

    if (changed == true) {
      service.clearCache();
      await loadInitialMediaData();
      await syncFavoriteImages(showLoading: false);
    }
  }

  Future<void> loadInitialMediaData() async {
    _gridTileKeys.clear();
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

  Future<void> syncFavoriteImages({bool showLoading = true}) async {
    if (favorites.isEmpty) {
      if (!mounted) return;
      setState(() {
        favoriteImages = [];
        isLoadingFavoriteImages = false;
      });
      return;
    }

    if (showLoading) {
      setState(() => isLoadingFavoriteImages = true);
    }
    final data = filterRecycleBinItems(
      await service.fetchImagesByIds(favorites),
    );
    if (!mounted) return;

    setState(() {
      favoriteImages = data;
      isLoadingFavoriteImages = false;
    });
  }

  Future<void> loadRecycleBin() async {
    setState(() {
      isLoadingRecycleBin = true;
    });

    final items = await recycleBinDatabase.loadItems();
    final ids = items.map((item) => item.assetId).toSet();
    final assets = await service.fetchImagesByIds(ids);
    final validIds = assets.map((asset) => asset.id).toSet();
    final staleIds = ids.difference(validIds);
    if (staleIds.isNotEmpty) {
      await recycleBinDatabase.removeAssets(staleIds);
    }

    if (!mounted) return;

    setState(() {
      recycleBinIds
        ..clear()
        ..addAll(validIds);
      recycleBinItems = assets;
      recycleBinRecords
        ..clear()
        ..addEntries(
          items
              .where((item) => validIds.contains(item.assetId))
              .map((item) => MapEntry(item.assetId, item)),
        );
      isLoadingRecycleBin = false;
    });
  }

  void clearSelection() {
    if (selectedAssetIds.isEmpty) return;
    setState(() {
      selectedAssetIds.clear();
      _gridTileKeys.clear();
    });
  }

  void toggleSelection(AssetEntity asset) {
    if (isRecycleActionInProgress) return;
    setState(() {
      if (!selectedAssetIds.add(asset.id)) {
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

  ScrollController? get _activeDragSelectionScrollController {
    if (selectedIndex == 0) return scrollController;
    if (selectedIndex == 1) return videosScrollController;
    if (selectedIndex == 4) return favoritesScrollController;
    if (selectedIndex == 3) return albumsScrollController;
    if (selectedIndex == 5) return recycleBinScrollController;
    return null;
  }

  void _startDragSelection(AssetEntity asset) {
    if (isRecycleActionInProgress) return;
    _dragSelectionTargetValue = !selectedAssetIds.contains(asset.id);
    _dragSelectionTouchedIds
      ..clear()
      ..add(asset.id);
    
    // Find index of start asset in visible items to support range selection
    final visibleItems = _getVisibleItemsForCurrentTab();
    _dragSelectionStartIndex = visibleItems.indexWhere((e) => e.id == asset.id);
    _dragSelectionInitialIds = Set.from(selectedAssetIds);

    setState(() {
      if (_dragSelectionTargetValue!) {
        selectedAssetIds.add(asset.id);
      } else {
        selectedAssetIds.remove(asset.id);
      }
    });
  }

  List<AssetEntity> _getVisibleItemsForCurrentTab() {
    switch (selectedIndex) {
      case 1: // Videos
        return videos;
      case 4: // Favorites
        return favoriteImages;
      case 5: // Recycle Bin
        return recycleBinItems;
      case 2: // Songs
        return MusicService().musicCache.map((m) => m.asset).whereType<AssetEntity>().toList();
      case 0:
      default:
        return images;
    }
  }

  void _updateDragSelection(
    Offset globalPosition,
    List<AssetEntity> visibleImages,
  ) {
    _lastDragGlobalPosition = globalPosition;
    final targetValue = _dragSelectionTargetValue;
    if (targetValue == null) return;

    final visibleItems = _getVisibleItemsForCurrentTab();
    int? currentHoverIndex;

    for (var i = 0; i < visibleItems.length; i++) {
      final asset = visibleItems[i];
      // Note: grid tiles use tab-specific keys to avoid conflicts
      final key = _gridTileKeys['tab_${selectedIndex}_${asset.id}'];
      final context = key?.currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      
      // Expand hit detection slightly for better feel when dragging
      if (rect.inflate(4).contains(globalPosition)) {
        currentHoverIndex = i;
        break;
      }
    }

    if (currentHoverIndex != null && _dragSelectionStartIndex != null) {
      final start = _dragSelectionStartIndex!;
      final end = currentHoverIndex;
      final minIdx = start < end ? start : end;
      final maxIdx = start < end ? end : start;

      setState(() {
        // Reset to initial and apply current range
        selectedAssetIds.clear();
        selectedAssetIds.addAll(_dragSelectionInitialIds ?? {});
        
        for (var i = minIdx; i <= maxIdx; i++) {
          final id = visibleItems[i].id;
          if (targetValue) {
            selectedAssetIds.add(id);
          } else {
            selectedAssetIds.remove(id);
          }
        }
      });
    }

    _updateDragAutoScroll(globalPosition, visibleItems);
  }

  void _endDragSelection() {
    _dragSelectionTargetValue = null;
    _dragSelectionTouchedIds.clear();
    _dragSelectionStartIndex = null;
    _dragSelectionInitialIds = null;
    _lastDragGlobalPosition = null;
    _dragAutoScrollVelocity = 0;
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
  }

  void _updateDragAutoScroll(
    Offset globalPosition,
    List<AssetEntity> visibleImages,
  ) {
    final controller = _activeDragSelectionScrollController;
    if (controller == null || !controller.hasClients) return;

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
      final activeController = _activeDragSelectionScrollController;
      final dragPosition = _lastDragGlobalPosition;
      if (_dragSelectionTargetValue == null ||
          activeController == null ||
          !activeController.hasClients ||
          dragPosition == null) {
        _dragAutoScrollTimer?.cancel();
        _dragAutoScrollTimer = null;
        return;
      }

      final position = activeController.position;
      final nextOffset = (position.pixels + _dragAutoScrollVelocity).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      if ((nextOffset - position.pixels).abs() < 0.1) return;
      activeController.jumpTo(nextOffset);
      _updateDragSelection(dragPosition, visibleImages);
    });
  }

  Future<void> _refreshMediaAfterRecycleChange() async {
    service.clearCache(); // Force service to re-find paths (crucial for new files)
    final galleryPageToKeep = currentPage;
    final videoPageToKeep = currentVideoPage;
    await Future.wait([
      loadRecycleBin(),
      loadImages(
        permissionOverride: permissionState,
        showLoading: false,
        targetPage: galleryPageToKeep,
      ),
      loadVideos(
        permissionOverride: permissionState,
        showLoading: false,
        targetPage: videoPageToKeep,
      ),
      syncFavoriteImages(showLoading: false),
      MusicService().fetchMusicsPaged(refresh: true),
    ]);
  }

  void _toggleSelectAllForCurrentTab(List<AssetEntity> visibleImages) {
    if (visibleImages.isEmpty || isRecycleActionInProgress) return;
    final visibleIds = visibleImages.map((asset) => asset.id).toSet();
    final allSelected = visibleIds.every(selectedAssetIds.contains);

    setState(() {
      if (allSelected) {
        selectedAssetIds.removeAll(visibleIds);
      } else {
        selectedAssetIds.addAll(visibleIds);
      }
    });
  }

  void _showRecycleSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
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

  List<AssetEntity> _selectedAssetsFromVisibleItems() {
    final source = <AssetEntity>[
      ...images,
      ...videos,
      ...favoriteImages,
      ...recycleBinItems,
      ...MusicService().musicCache.map((m) => m.asset).whereType<AssetEntity>(),
    ];
    final byId = <String, AssetEntity>{};
    for (final asset in source) {
      byId[asset.id] = asset;
    }

    return selectedAssetIds
        .map((id) => byId[id])
        .whereType<AssetEntity>()
        .toList(growable: false);
  }

  Future<void> moveSelectionToRecycleBin() async {
    final ids = selectedAssetIds.toList(growable: false);
    if (ids.isEmpty || isRecycleActionInProgress) return;
    final shouldMove = await _confirmMoveToRecycleBin(ids.length);
    if (!shouldMove || !mounted) return;

    setState(() {
      isRecycleActionInProgress = true;
    });
    try {
      await recycleBinDatabase.addAssets(_selectedAssetsFromVisibleItems());
      for (final id in ids) {
        if (favorites.contains(id)) {
          await favoritesDatabase.removeFavorite(id);
        }
      }

      if (!mounted) return;

      setState(() {
        favorites.removeAll(ids);
        favoriteImages = favoriteImages
            .where((asset) => !ids.contains(asset.id))
            .toList();
        recycleBinIds.addAll(ids);
        selectedAssetIds.clear();
      });

      await _refreshMediaAfterRecycleChange();
      if (!mounted) return;
      _showRecycleSnackBar(
        '${ids.length} item${ids.length == 1 ? '' : 's'} moved to recycle bin',
      );
    } finally {
      if (mounted) {
        setState(() {
          isRecycleActionInProgress = false;
        });
      }
    }
  }

  Future<void> restoreSelectionFromRecycleBin() async {
    final ids = selectedAssetIds.toList(growable: false);
    if (ids.isEmpty || isRecycleActionInProgress) return;

    setState(() {
      isRecycleActionInProgress = true;
    });
    try {
      await recycleBinDatabase.removeAssets(ids);
      if (!mounted) return;

      setState(() {
        recycleBinIds.removeAll(ids);
        selectedAssetIds.clear();
      });

      await _refreshMediaAfterRecycleChange();
      if (!mounted) return;
      _showRecycleSnackBar(
        '${ids.length} item${ids.length == 1 ? '' : 's'} restored',
      );
    } finally {
      if (mounted) {
        setState(() {
          isRecycleActionInProgress = false;
        });
      }
    }
  }

  Future<void> deleteSelectionForever() async {
    final ids = selectedAssetIds.toList(growable: false);
    if (ids.isEmpty || isRecycleActionInProgress) return;

    setState(() {
      isRecycleActionInProgress = true;
    });
    try {
      await PhotoManager.editor.deleteWithIds(ids);
      await recycleBinDatabase.removeAssets(ids);
      if (!mounted) return;

      setState(() {
        recycleBinIds.removeAll(ids);
        selectedAssetIds.clear();
      });

      await _refreshMediaAfterRecycleChange();
      if (!mounted) return;
      _showRecycleSnackBar(
        '${ids.length} item${ids.length == 1 ? '' : 's'} deleted forever',
      );
    } finally {
      if (mounted) {
        setState(() {
          isRecycleActionInProgress = false;
        });
      }
    }
  }

  Future<bool> _confirmMoveToVault(int count) async {
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
                          Icons.lock_outline_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Move To Safe Folder?',
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
                        ? 'This item will be moved to your safe folder and hidden from your library. You can restore it later.'
                        : '$count items will be moved to your safe folder and hidden from your library. You can restore them later.',
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

  Future<void> moveSelectionToVault() async {
    final ids = selectedAssetIds.toList(growable: false);
    final assets = _selectedAssetsFromVisibleItems();
    if (ids.isEmpty || isRecycleActionInProgress) return;

    final shouldMove = await _confirmMoveToVault(ids.length);
    if (!shouldMove || !mounted) return;

    setState(() {
      isRecycleActionInProgress = true;
    });
    try {
      await VaultService.instance.moveAssetsToVault(assets);

      if (!mounted) return;

      setState(() {
        favorites.removeAll(ids);
        favoriteImages = favoriteImages
            .where((asset) => !ids.contains(asset.id))
            .toList();
        selectedAssetIds.clear();
      });

      await _refreshMediaAfterRecycleChange();
      if (!mounted) return;
      _showRecycleSnackBar(
        '${ids.length} item${ids.length == 1 ? '' : 's'} moved to Safe Folder',
      );
    } catch (e) {
      if (mounted) _showRecycleSnackBar('Failed to move to Safe Folder');
    } finally {
      if (mounted) {
        setState(() {
          isRecycleActionInProgress = false;
        });
      }
    }
  }

  Future<void> shareSelection() async {
    final assets = _selectedAssetsFromVisibleItems();
    if (assets.isEmpty) return;

    final files = <XFile>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file != null) {
        files.add(XFile(file.path));
      }
    }

    if (files.isEmpty) return;

    await SharePlus.instance.share(
      ShareParams(files: files),
    );
  }

  Future<void> _showSelectionMenu() async {
    List<AssetEntity> getVisibleImages() {
      switch (selectedIndex) {
        case 1: // Videos
          return videos;
        case 2: // Music
          return MusicService().musicCache.map((m) => m.asset).whereType<AssetEntity>().toList();
        case 4: // Favorites
          return favoriteImages;
        case 5: // Recycle Bin
          return recycleBinItems;
        case 0: // Gallery
        default:
          return images;
      }
    }

    final visibleImages = getVisibleImages();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) {
        return Stack(
          children: [
            // Dismiss background
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogContext),
                child: Container(color: Colors.transparent),
              ),
            ),
            // Menu positioned at top-right
            Positioned(
              top: 56,
              right: 16,
              child: GlassContainer(
                borderRadius: BorderRadius.circular(20),
                blurSigma: 18,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: SelectionContainer.disabled(
                            child: Text(
                              '${selectedAssetIds.length} selected',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Divider(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                            height: 1,
                          ),
                        ),
                        // Menu items
                        _buildMenuTile(
                          Icons.share_rounded,
                          'Share',
                          colorScheme,
                          () async {
                            Navigator.pop(dialogContext);
                            await shareSelection();
                          },
                        ),
                        if (selectedIndex == 4)
                          _buildMenuTile(
                            Icons.favorite_outline_rounded,
                            'Unfavorite items',
                            colorScheme,
                            () async {
                              Navigator.pop(dialogContext);
                              await unfavoriteSelection();
                            },
                          ),
                        if (selectedIndex == 4)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Divider(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                              height: 1,
                            ),
                          ),
                        _buildMenuTile(
                          Icons.lock_rounded,
                          'Move to Safe Folder',
                          colorScheme,
                          () async {
                            Navigator.pop(dialogContext);
                            await moveSelectionToVault();
                          },
                        ),
                        _buildMenuTile(
                          Icons.delete_rounded,
                          'Move to Recycle Bin',
                          colorScheme,
                          () async {
                            Navigator.pop(dialogContext);
                            await moveSelectionToRecycleBin();
                          },
                          isDestructive: true,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Divider(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                            height: 1,
                          ),
                        ),
                        _buildMenuTile(
                          Icons.select_all_rounded,
                          'Select All',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            _toggleSelectAllForCurrentTab(visibleImages);
                          },
                        ),
                        _buildMenuTile(
                          Icons.deselect_rounded,
                          'Deselect All',
                          colorScheme,
                          () {
                            Navigator.pop(dialogContext);
                            clearSelection();
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

  Future<void> unfavoriteSelection() async {
    final ids = selectedAssetIds.toList();
    if (ids.isEmpty) return;
    
    for (final id in ids) {
      await favoritesDatabase.removeFavorite(id);
    }
    
    if (!mounted) return;
    setState(() {
      favorites.removeAll(ids);
      favoriteImages.removeWhere((asset) => ids.contains(asset.id));
      selectedAssetIds.clear();
    });
    _showRecycleSnackBar('Removed ${ids.length} from favorites');
  }

  Widget _buildMenuTile(
    IconData icon,
    String label,
    ColorScheme colorScheme,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: (isDestructive ? colorScheme.error : colorScheme.primary)
          .withValues(alpha: 0.12),
      highlightColor: (isDestructive ? colorScheme.error : colorScheme.primary)
          .withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isDestructive ? colorScheme.error : colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: SelectionContainer.disabled(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isDestructive
                        ? colorScheme.error
                        : colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreRecycleBinItem(AssetEntity asset) async {
    if (isRecycleActionInProgress) return;
    setState(() {
      isRecycleActionInProgress = true;
    });
    try {
      await recycleBinDatabase.removeAssets([asset.id]);
      if (!mounted) return;
      await _refreshMediaAfterRecycleChange();
      if (!mounted) return;
      _showRecycleSnackBar('Restored successfully');
    } finally {
      if (mounted) {
        setState(() {
          isRecycleActionInProgress = false;
        });
      }
    }
  }

  Future<void> _deleteRecycleBinItemForever(AssetEntity asset) async {
    if (isRecycleActionInProgress) return;
    setState(() {
      isRecycleActionInProgress = true;
    });
    try {
      await PhotoManager.editor.deleteWithIds([asset.id]);
      await recycleBinDatabase.removeAssets([asset.id]);
      if (!mounted) return;
      await _refreshMediaAfterRecycleChange();
      if (!mounted) return;
      _showRecycleSnackBar('Deleted forever');
    } finally {
      if (mounted) {
        setState(() {
          isRecycleActionInProgress = false;
        });
      }
    }
  }

  String _formatRecycleDate(DateTime date) {
    final time = TimeOfDay.fromDateTime(date).format(context);
    return '${date.day}/${date.month}/${date.year} • $time';
  }

  Widget _buildRecycleSwipeBackground({
    required bool restore,
    required bool alignStart,
  }) {
    final color = restore ? const Color(0xFF2F9B72) : const Color(0xFFD55B65);
    final icon = restore ? Icons.restore_rounded : Icons.delete_forever_rounded;
    final label = restore ? 'Restore' : 'Delete Forever';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.88),
            color.withValues(alpha: 0.62),
          ],
          begin: alignStart ? Alignment.centerLeft : Alignment.centerRight,
          end: alignStart ? Alignment.centerRight : Alignment.centerLeft,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignStart
            ? [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]
            : [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white),
              ],
      ),
    );
  }

  Widget buildRecycleBinListView(ColorScheme colorScheme) {
    return CustomScrollView(
      controller: recycleBinScrollController,
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1400,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
          sliver: SliverFixedExtentList(
            itemExtent: 116,
            delegate: SliverChildBuilderDelegate((context, index) {
              final asset = recycleBinItems[index];
              final record = recycleBinRecords[asset.id];
              final filePath = record?.filePath ?? '';
              final title = filePath.isEmpty
                  ? 'Unknown file'
                  : path.basename(filePath);
              final subtitle = record == null
                  ? 'Recently deleted'
                  : _formatRecycleDate(record.deletedAt);
              final isSelected = selectedAssetIds.contains(asset.id);

              return RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Dismissible(
                    key: ValueKey('recycle-${asset.id}'),
                    direction: isRecycleActionInProgress || isSelectionMode
                        ? DismissDirection.none
                        : DismissDirection.horizontal,
                    background: _buildRecycleSwipeBackground(
                      restore: false,
                      alignStart: true,
                    ),
                    secondaryBackground: _buildRecycleSwipeBackground(
                      restore: true,
                      alignStart: false,
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.endToStart) {
                        await _restoreRecycleBinItem(asset);
                      } else {
                        await _deleteRecycleBinItemForever(asset);
                      }
                      return true;
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () {
                          toggleSelection(asset);
                        },
                        onTap: () async {
                          if (isSelectionMode) {
                            toggleSelection(asset);
                            return;
                          }
                          await _showRecycleBinItemSheet(asset);
                        },
                        child: GlassContainer(
                          borderRadius: BorderRadius.circular(26),
                          enableBlur: false,
                          child: Row(
                            children: [
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(26),
                                    border: Border.all(
                                      color: isSelected
                                          ? colorScheme.primary.withValues(
                                              alpha: 0.42,
                                            )
                                          : Colors.transparent,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: SizedBox(
                                          width: 74,
                                          height: 74,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              asset.type == AssetType.audio
                                                  ? Container(
                                                      color: colorScheme.primary
                                                          .withValues(alpha: 0.12),
                                                      child: Icon(
                                                        Icons.music_note_rounded,
                                                        color: colorScheme.primary,
                                                        size: 32,
                                                      ),
                                                    )
                                                  : buildImage(asset, thumbPx: 128),
                                              if (asset.type == AssetType.video)
                                                Align(
                                                  alignment:
                                                      Alignment.bottomRight,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.56,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        _formatDuration(
                                                          asset.videoDuration,
                                                        ),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
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
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: colorScheme.onSurface
                                                    .withValues(alpha: 0.68),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              asset.type == AssetType.video
                                                  ? 'Video • Swipe left to restore'
                                                  : asset.type == AssetType.audio
                                                      ? 'Music • Swipe left to restore'
                                                      : 'Photo • Swipe left to restore',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: colorScheme.onSurface
                                                    .withValues(alpha: 0.56),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? colorScheme.primaryContainer
                                                    .withValues(alpha: 0.98)
                                              : colorScheme.primaryContainer
                                                    .withValues(alpha: 0.92),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          isSelected
                                              ? Icons.check_rounded
                                              : Icons.chevron_right_rounded,
                                          color: isSelected
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }, childCount: recycleBinItems.length),
          ),
        ),
      ],
    );
  }

  Future<void> _showRecycleBinItemSheet(AssetEntity asset) async {
    final record = recycleBinRecords[asset.id];
    final filePath = record?.filePath ?? '';
    final title = filePath.isEmpty ? 'Unknown file' : path.basename(filePath);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          blurSigma: 18,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      height: 220,
                      width: double.infinity,
                      child: buildImage(asset, thumbPx: 320),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      record == null
                          ? 'Recently deleted'
                          : _formatRecycleDate(record.deletedAt),
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (filePath.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        filePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.56),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isRecycleActionInProgress
                              ? null
                              : () async {
                                  Navigator.pop(sheetContext);
                                  await _restoreRecycleBinItem(asset);
                                },
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Restore'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isRecycleActionInProgress
                              ? null
                              : () async {
                                  Navigator.pop(sheetContext);
                                  await _deleteRecycleBinItemForever(asset);
                                },
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Delete'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
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
  }

  List<AssetEntity> filterRecycleBinItems(List<AssetEntity> items) {
    if (recycleBinIds.isEmpty) return items;
    return items
        .where((asset) => !recycleBinIds.contains(asset.id))
        .toList(growable: false);
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
    bool showLoading = true,
    int? targetPage,
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
      if (showLoading || images.isEmpty) {
        setState(() => isLoading = true);
      }
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
    late final List<AssetEntity> data;
    late final int resolvedPage;
    late final bool resolvedHasMore;

    if (loadMore) {
      final rawData = await service.fetchImages(page: nextPage, size: pageSize);
      data = filterRecycleBinItems(rawData);
      resolvedPage = nextPage;
      resolvedHasMore = rawData.length == pageSize;
    } else {
      final lastTargetPage = (targetPage ?? 0).clamp(0, 100000);
      final collected = <AssetEntity>[];
      var lastLoadedPage = 0;
      var lastBatchCount = 0;

      for (var page = 0; page <= lastTargetPage; page++) {
        final rawPage = await service.fetchImages(page: page, size: pageSize);
        lastLoadedPage = page;
        lastBatchCount = rawPage.length;
        collected.addAll(filterRecycleBinItems(rawPage));
        if (rawPage.length < pageSize) {
          break;
        }
      }

      data = collected;
      resolvedPage = data.isEmpty ? 0 : lastLoadedPage;
      resolvedHasMore = lastBatchCount == pageSize;
    }

    if (!mounted) return;

    setState(() {
      if (loadMore) {
        // Prepend pending assets if they match the type and are not already present
        final toPrepend = _pendingAssets.where((a) => 
          (selectedIndex == 1 ? a.type == AssetType.video : a.type == AssetType.image) &&
          !data.any((existing) => existing.id == a.id)
        ).toList();
        
        images.addAll(data);
        isLoadingMore = false;
        currentPage = resolvedPage;
        hasMore = resolvedHasMore;
      } else {
        // Prepend pending assets that are not yet in the freshly fetched data
        final toPrepend = _pendingAssets.where((a) => 
          (selectedIndex == 1 ? a.type == AssetType.video : a.type == AssetType.image) &&
          !data.any((existing) => existing.id == a.id)
        ).toList();

        // Remove from pending if they successfully appeared in the fresh data
        _pendingAssets.removeWhere((a) => 
          data.any((existing) => existing.id == a.id)
        );

        images = [...toPrepend, ...data];
        isLoading = false;
        currentPage = resolvedPage;
        hasMore = resolvedHasMore;
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
    bool showLoading = true,
    int? targetPage,
  }) async {
    if (loadMore) {
      if (isLoadingMoreVideos ||
          isLoadingVideos ||
          !hasMoreVideos ||
          selectedIndex != 1) {
        return;
      }
      setState(() => isLoadingMoreVideos = true);
    } else {
      if (showLoading || videos.isEmpty) {
        setState(() => isLoadingVideos = true);
      }
    }

    if (!loadMore) {
      final permission =
          permissionOverride ?? await service.requestImagePermission();
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
    late final List<AssetEntity> data;
    late final int resolvedPage;
    late final bool resolvedHasMore;

    if (loadMore) {
      final rawData = await service.fetchVideos(page: nextPage, size: pageSize);
      data = filterRecycleBinItems(rawData);
      resolvedPage = nextPage;
      resolvedHasMore = rawData.length == pageSize;
    } else {
      final lastTargetPage = (targetPage ?? 0).clamp(0, 100000);
      final collected = <AssetEntity>[];
      var lastLoadedPage = 0;
      var lastBatchCount = 0;

      for (var page = 0; page <= lastTargetPage; page++) {
        final rawPage = await service.fetchVideos(page: page, size: pageSize);
        lastLoadedPage = page;
        lastBatchCount = rawPage.length;
        collected.addAll(filterRecycleBinItems(rawPage));
        if (rawPage.length < pageSize) {
          break;
        }
      }

      data = collected;
      resolvedPage = data.isEmpty ? 0 : lastLoadedPage;
      resolvedHasMore = lastBatchCount == pageSize;
    }
    if (!mounted) return;

    setState(() {
      if (loadMore) {
        // Prepend pending assets if they match the type and are not already present
        final toPrepend = _pendingAssets.where((a) => 
          a.type == AssetType.video &&
          !data.any((existing) => existing.id == a.id)
        ).toList();
        
        videos.addAll(data);
        isLoadingMoreVideos = false;
        currentVideoPage = resolvedPage;
        hasMoreVideos = resolvedHasMore;
      } else {
        // Prepend pending assets that are not yet in the freshly fetched data
        final toPrepend = _pendingAssets.where((a) => 
          a.type == AssetType.video &&
          !data.any((existing) => existing.id == a.id)
        ).toList();

        // Remove from pending if they successfully appeared in the fresh data
        _pendingAssets.removeWhere((a) => 
          a.type == AssetType.video &&
          data.any((existing) => existing.id == a.id)
        );

        videos = [...toPrepend, ...data];
        isLoadingVideos = false;
        currentVideoPage = resolvedPage;
        hasMoreVideos = resolvedHasMore;
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
      final rawData = await service.fetchImages(
        page: targetPage,
        size: pageSize,
      );
      final data = filterRecycleBinItems(rawData);
      if (!mounted || selectedIndex != 0) return;
      _prefetchedImages = data;
      _prefetchedPage = targetPage;
    } finally {
      _isPrefetchingNextPage = false;
    }
  }

  Future<void> loadAlbums({PermissionState? permissionOverride}) async {
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
      if (position.pixels >
          position.maxScrollExtent - _galleryLoadMoreThreshold) {
        loadImages(loadMore: true);
      }
    } else if (selectedIndex == 1) {
      if (!videosScrollController.hasClients ||
          isLoadingVideos ||
          isLoadingMoreVideos) {
        return;
      }
      final position = videosScrollController.position;
      if (position.pixels >
          position.maxScrollExtent - _galleryLoadMoreThreshold) {
        loadVideos(loadMore: true);
      }
    }
  }

  ImageProvider<Object> _thumbnailProviderFor(AssetEntity asset, int thumbPx) {
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
    if (!mounted || _isViewerTransitioning) {
      return;
    }

    _thumbnailWarmupTimer?.cancel();
    _thumbnailWarmupTimer = Timer(const Duration(milliseconds: 70), () {
      if (!mounted) return;
      _warmVisibleThumbnailBand();
    });
  }

  void _warmVisibleThumbnailBand() {
    ScrollController activeController = scrollController;
    List<AssetEntity> activeImages = images;

    if (selectedIndex == 1) {
      activeController = videosScrollController;
      activeImages = videos;
    } else if (selectedIndex == 4) {
      activeController = favoritesScrollController;
      activeImages = favoriteImages;
    } else if (selectedIndex == 3) {
      activeController = albumsScrollController;
    } else if (selectedIndex == 5) {
      activeController = recycleBinScrollController;
      activeImages = recycleBinItems;
    }

    if (!mounted ||
        !activeController.hasClients ||
        activeController.positions.length != 1 ||
        _isViewerTransitioning ||
        activeImages.isEmpty ||
        selectedIndex == 2 || // Skip music (it uses own ListView)
        selectedIndex == 3) { // Skip albums (it uses different layout)
      return;
    }

    final viewportWidth = MediaQuery.of(context).size.width;
    final contentWidth = (viewportWidth - 20 - ((galleryGridCount - 1) * 6))
        .clamp(120.0, 4000.0);
    final tileExtent = (contentWidth / galleryGridCount) + 6;
    final effectiveOffset = (activeController.offset - 54).clamp(
      0.0,
      double.infinity,
    );
    final firstVisibleRow = (effectiveOffset / tileExtent).floor();
    final visibleRows =
        ((activeController.position.viewportDimension / tileExtent).ceil() + 2)
            .clamp(4, 14);
    final startIndex = ((firstVisibleRow - 4) * galleryGridCount).clamp(
      0,
      activeImages.length,
    );
    final endIndex = ((firstVisibleRow + visibleRows + 7) * galleryGridCount)
        .clamp(0, activeImages.length);

    if (startIndex == _lastWarmedStart && endIndex == _lastWarmedEnd) return;
    _lastWarmedStart = startIndex;
    _lastWarmedEnd = endIndex;

    for (var i = startIndex; i < endIndex; i++) {
        if (i >= activeImages.length) break;
        final asset = activeImages[i];
        seenThumbnailAssetIds.add(asset.id);
        warmedThumbnailKeys.add('${asset.id}@$galleryThumbPx');
        precacheImage(_thumbnailProviderFor(asset, galleryThumbPx), context);
    }
  }

  Widget buildImage(AssetEntity asset, {int thumbPx = 220}) {
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
        warmedThumbnailKeys.contains(id) ||
        seenThumbnailAssetIds.contains(asset.id);

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
          setState(() {
            selectedIndex = index;
            selectedAssetIds.clear();
            _gridTileKeys.clear();
          });
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
            icon: Icon(Icons.music_note_outlined),
            selectedIcon: Icon(Icons.music_note),
            label: 'Music',
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
          NavigationDestination(
            icon: Badge.count(
              count: recycleBinItems.length,
              isLabelVisible: recycleBinItems.isNotEmpty,
              child: const Icon(Icons.delete_outline_rounded),
            ),
            selectedIcon: const Icon(Icons.delete_rounded),
            label: 'Recycle',
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
    final albumImages = filterRecycleBinItems(
      await service.fetchAlbumImages(album.album),
    );
    if (!mounted || albumImages.isEmpty) return;

    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            AlbumDetailScreen(
          title: album.name,
          album: album.album,
          images: albumImages,
        ),
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
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
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

    final featuredAlbums = albums
        .where((album) => album.isFeatured)
        .toList(growable: false);
    final otherAlbums = albums
        .where((album) => !album.isFeatured)
        .toList(growable: false);

    return CustomScrollView(
      controller: albumsScrollController,
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1400,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: RepaintBoundary(
              child: GlassContainer(
                padding: const EdgeInsets.all(18),
                borderRadius: BorderRadius.circular(32),
                blurSigma: 12,
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
                          color: colorScheme.secondaryContainer.withOpacity(
                            0.9,
                          ),
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
                cacheExtent: 1000,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  decelerationRate: ScrollDecelerationRate.fast,
                ),
                itemCount: featuredAlbums.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
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
          sliver: SliverFixedExtentList(
            itemExtent: 110,
            delegate: SliverChildBuilderDelegate((context, index) {
              final album = otherAlbums[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: gallery_album_widgets.buildAlbumListTile(
                  album: album,
                  colorScheme: colorScheme,
                  buildImage: buildImage,
                  onTap: () => openAlbum(album),
                ),
              );
            }, childCount: otherAlbums.length),
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
    final ImageProvider<Object> previewProvider = _thumbnailProviderFor(
      asset,
      galleryThumbPx,
    );
    final openingProvider = ViewerScreen.openingImageProvider(context, asset);
    final isRecycleBinTab = selectedIndex == 5;
    final isSelected = selectedAssetIds.contains(asset.id);
    // Use a tab-specific key prefix to avoid Duplicate GlobalKey error during transitions 
    // or when the same asset appears in multiple tabs (e.g. Gallery and Favorites)
    final keyString = 'tab_${selectedIndex}_${asset.id}';
    final tileKey = _gridTileKeys.putIfAbsent(keyString, GlobalKey.new);

    return gallery_grid_widgets.buildGalleryGridTile(
      asset: asset,
      image: Stack(
        fit: StackFit.expand,
        children: [
          buildImage(asset, thumbPx: galleryThumbPx),
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
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
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
        ],
      ),
      onTap: () async {
        if (isSelectionMode) {
          toggleSelection(asset);
          return;
        }

        _thumbnailWarmupTimer?.cancel();
        _isViewerTransitioning = true;

        if (asset.type == AssetType.video) {
          final videoList = visibleImages
              .where((e) => e.type == AssetType.video)
              .toList();
          var videoIndex = videoList.indexWhere((e) => e.id == asset.id);
          if (videoIndex == -1) {
            videoList.insert(0, asset);
            videoIndex = 0;
          }

          final viewerAction = await Navigator.push<String>(
            context,
            buildCinematicRoute(
              VideoViewerScreen(videos: videoList, initialIndex: videoIndex),
            ),
          );
          if ((viewerAction == 'recycle' || viewerAction == 'vault') &&
              mounted) {
            await _refreshMediaAfterRecycleChange();
            if (!mounted) return;
            _showRecycleSnackBar(
              viewerAction == 'vault'
                  ? 'Moved to Safe Folder'
                  : 'Moved to recycle bin',
            );
          }
        } else {
          unawaited(precacheImage(previewProvider, context));
          unawaited(precacheImage(openingProvider, context));

          final dynamic result = await Navigator.push<dynamic>(
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

          if (result != null && mounted) {
            String? action;
            if (result is String) {
              action = result;
            } else if (result is AssetEntity) {
              action = 'edited';
              // Perform a truly instant local update before the background refresh
              setState(() {
                _pendingAssets.add(result);
                if (result.type == AssetType.video) {
                  if (!videos.any((e) => e.id == result.id)) {
                    videos.insert(0, result);
                  }
                } else {
                  if (!images.any((e) => e.id == result.id)) {
                    images.insert(0, result);
                  }
                }
              });
            }

            if (action == 'recycle' || action == 'vault') {
              await _refreshMediaAfterRecycleChange();
              if (!mounted) return;
              _showRecycleSnackBar(
                action == 'vault'
                    ? 'Moved to Safe Folder'
                    : 'Moved to recycle bin',
              );
            } else if (action == 'edited') {
              // For edits, we handle the 'instant' update via _pendingAssets.
              // We still refresh albums and other metadata, but loadImages 
              // will now respect our _pendingAssets even if the MediaStore is slow.
              await Future.wait([
                loadAlbums(permissionOverride: permissionState),
                loadImages(permissionOverride: permissionState, showLoading: false),
                loadVideos(permissionOverride: permissionState, showLoading: false),
                syncFavoriteImages(showLoading: false),
                MusicService().fetchMusicsPaged(refresh: true),
              ]);
            }
          }
        }
        if (!mounted) return;
        _isViewerTransitioning = false;
        _scheduleThumbnailWarmup();
      },
      onDoubleTap: isRecycleBinTab ? () {} : () => toggleFavorite(asset),
      onLongPress: () {},
      onLongPressStart: (_) {
        _startDragSelection(asset);
      },
      onLongPressMoveUpdate: (details) {
        _updateDragSelection(details.globalPosition, visibleImages);
      },
      onLongPressEnd: (_) {
        _endDragSelection();
      },
      isFavorite: !isRecycleBinTab && favorites.contains(asset.id),
      isAnimating: !isRecycleBinTab && animating.contains(asset.id),
      isSelected: isSelected,
      heroTag: asset.id,
      tileKey: tileKey,
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
      for (
        var sectionIndex = 0;
        sectionIndex < sections.length;
        sectionIndex++
      ) ...[
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
            delegate: SliverChildBuilderDelegate((context, index) {
              final asset = sections[sectionIndex].items[index];
              final absoluteIndex = indexByAssetId[asset.id] ?? 0;
              return buildGridTile(asset, visibleImages, absoluteIndex);
            }, childCount: sections[sectionIndex].items.length),
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
        child: CustomScrollView(
          key: controller == scrollController
              ? _galleryScrollKey
              : controller == favoritesScrollController
              ? _favoritesScrollKey
              : PageStorageKey('grid-$selectedIndex'),
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
      ),
    );
  }

  Widget buildBody(
    List<AssetEntity> visibleImages,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    if (selectedIndex == 3) {
      return KeyedSubtree(
        key: const ValueKey('tab-albums-view'),
        child: buildAlbumsView(colorScheme, isDark),
      );
    }
    if (selectedIndex == 2) {
      return KeyedSubtree(
        key: const ValueKey('tab-music-view'),
        child: MusicScreen(
          audioPlayerService: audioPlayerService,
          selectedIds: selectedAssetIds,
          onSelectionToggle: toggleSelection,
        ),
      );
    }
    if (selectedIndex == 5) {
      if (isLoadingRecycleBin) {
        return const KeyedSubtree(
          key: ValueKey('loading-recycle'),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (recycleBinItems.isEmpty) {
        return KeyedSubtree(
          key: const ValueKey('empty-recycle'),
          child: Center(
            child: Text(
              'Recycle bin is empty',
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
        key: const ValueKey('tab-recycle-list-view'),
        child: buildRecycleBinListView(colorScheme),
      );
    }
    if ((selectedIndex == 0 && isLoading) ||
        (selectedIndex == 1 && isLoadingVideos) ||
        (selectedIndex == 4 && isLoadingFavoriteImages)) {
      return const KeyedSubtree(
        key: ValueKey('loading'),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if ((selectedIndex == 0 || selectedIndex == 1) &&
        permissionState != null &&
        !permissionState!.hasAccess) {
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
      if (selectedIndex == 1) {
        emptyText = 'No videos found';
      } else if (selectedIndex == 4) {
        emptyText = 'No favorite items yet';
      }

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
    if (selectedIndex == 1) {
      currentController = videosScrollController;
    } else if (selectedIndex == 4) {
      currentController = favoritesScrollController;
    } else if (selectedIndex == 3) {
      currentController = albumsScrollController;
    } else if (selectedIndex == 5) {
      currentController = recycleBinScrollController;
    }

    return KeyedSubtree(
      key: ValueKey('tab-grid-view-$selectedIndex'),
      child: buildGridView(visibleImages, colorScheme, currentController),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final topBarColor = isDark
        ? const Color(0xFF120C24)
        : const Color(0xFFF1E8FF);
    final titles = ['Gallery', 'Videos', 'Music', 'Albums', 'Favorites', 'Recycle Bin'];

    List<AssetEntity> visibleImages = images;
    if (selectedIndex == 1) {
      visibleImages = videos;
    } else if (selectedIndex == 4) {
      visibleImages = favoriteImages;
    } else if (selectedIndex == 5) {
      visibleImages = recycleBinItems;
    }

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        leading: isSelectionMode
            ? IconButton(
                tooltip: 'Close selection',
                icon: const Icon(Icons.close_rounded),
                onPressed: clearSelection,
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
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: isSelectionMode || selectedIndex != 0
                ? null
                : (_) => _startVaultEntryPress(),
            onTapUp: isSelectionMode || selectedIndex != 0
                ? null
                : (_) => _cancelVaultEntryPress(),
            onTapCancel: isSelectionMode || selectedIndex != 0
                ? null
                : _cancelVaultEntryPress,
            child: AnimatedScale(
              scale: _isVaultEntryPressing ? 0.96 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Text(
                isSelectionMode
                    ? '${selectedAssetIds.length} selected'
                    : titles[selectedIndex],
                key: ValueKey('${selectedIndex}_${selectedAssetIds.length}'),
              ),
            ),
          ),
        ),
        backgroundColor: topBarColor,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle.copyWith(
          statusBarColor: topBarColor,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark
              ? const Color(0xFF101916)
              : const Color(0xFFF5F6F0),
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
        actions: [
          if (isSelectionMode)
            IconButton(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: _showSelectionMenu,
            ),
          if (isSelectionMode && selectedIndex == 5)
            IconButton(
              tooltip: 'Restore',
              icon: const Icon(Icons.restore_rounded),
              onPressed: isRecycleActionInProgress
                  ? null
                  : restoreSelectionFromRecycleBin,
            ),
          if (isSelectionMode && selectedIndex == 5)
            IconButton(
              tooltip: 'Delete forever',
              icon: const Icon(Icons.delete_forever_rounded),
              onPressed: isRecycleActionInProgress
                  ? null
                  : deleteSelectionForever,
            ),
          if (selectedIndex == 5 && !isSelectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(
                  'Tap for actions • Swipe restore/delete',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (!isSelectionMode)
            IconButton(
              tooltip: isDark ? 'Light mode' : 'Dark mode',
              icon: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              ),
              onPressed: () {
                context.read<ThemeProvider>().toggleTheme(context);
              },
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
            top: -80,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFFA855F7,
                  ).withOpacity(isDark ? 0.18 : 0.24),
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
                  color: const Color(
                    0xFFDDD6FE,
                  ).withOpacity(isDark ? 0.08 : 0.4),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (audioPlayerService.currentMusic != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MiniMusicPlayer(
                  audioPlayerService: audioPlayerService,
                  onTap: () {
                    if (audioPlayerService.currentMusic != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MusicPlayerScreen(
                            music: audioPlayerService.currentMusic!,
                            audioPlayerService: audioPlayerService,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: buildBottomBar(context, isDark),
            ),
          ],
        ),
      ),
    );
  }
}
