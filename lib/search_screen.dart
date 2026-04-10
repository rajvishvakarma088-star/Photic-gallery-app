import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gallery/gallery_grid_widgets.dart' as grid_widgets;
import 'glass_container.dart';
import 'services/gallery_service.dart';
import 'video_viewer_screen.dart';
import 'viewer_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const int _pageSize = GalleryService.mediaPageSize;
  static const int _resultTarget = 90;
  static const int _maxThumbCacheEntries = 1200;

  final GalleryService _service = GalleryService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _resultsScrollController = ScrollController();
  final Map<String, AssetEntityImageProvider> _thumbnailProviders = {};

  final List<AssetEntity> _loadedAssets = [];
  List<AssetEntity> _filteredAssets = [];
  List<String> _recentSearches = [];
  Timer? _searchDebounce;

  String _currentQuery = '';
  int _nextPage = 0;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _isScanningQuery = false;
  bool _hasMoreAssets = true;

  final List<Map<String, dynamic>> _quickFilters = const [
    {'label': 'Camera', 'icon': Icons.camera_alt_rounded},
    {'label': 'Downloads', 'icon': Icons.download_rounded},
    {'label': 'Screenshots', 'icon': Icons.screenshot_rounded},
    {'label': 'Videos', 'icon': Icons.videocam_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _resultsScrollController.addListener(_onResultsScroll);
    _loadRecentSearches();
    unawaited(_loadNextPage(showInitialLoading: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    _resultsScrollController.dispose();
    _thumbnailProviders.clear();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  Future<void> _saveSearch(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_searches') ?? [];
    searches.remove(normalized);
    searches.insert(0, normalized);
    if (searches.length > 5) searches.removeLast();
    await prefs.setStringList('recent_searches', searches);
    unawaited(_loadRecentSearches());
  }

  Future<void> _loadNextPage({bool showInitialLoading = false}) async {
    if (_isLoadingMore || !_hasMoreAssets) return;

    setState(() {
      if (showInitialLoading) {
        _isLoadingInitial = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final assets = await _service.fetchAssetsPage(
        page: _nextPage,
        size: _pageSize,
      );
      if (!mounted) return;

      final existingIds = _loadedAssets.map((asset) => asset.id).toSet();
      final uniqueAssets = assets
          .where((asset) => !existingIds.contains(asset.id))
          .toList(growable: false);

      _loadedAssets.addAll(uniqueAssets);
      _nextPage++;
      _hasMoreAssets = assets.length == _pageSize;

      if (_currentQuery.trim().isNotEmpty) {
        _applyQuery(_currentQuery, scanUntilEnough: false);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onResultsScroll() {
    if (!_resultsScrollController.hasClients ||
        _isLoadingMore ||
        _currentQuery.trim().isEmpty) {
      return;
    }

    final position = _resultsScrollController.position;
    if (position.pixels > position.maxScrollExtent - 900) {
      if (_hasMoreAssets) {
        unawaited(_progressivelyScanForQuery(_currentQuery.trim()));
      }
    }
  }

  bool _matchesQuery(AssetEntity asset, String lowerQuery) {
    if (lowerQuery.isEmpty) return false;
    if (lowerQuery == 'videos') return asset.type == AssetType.video;

    final title = asset.title?.toLowerCase() ?? '';
    final relativePath = asset.relativePath?.toLowerCase() ?? '';
    if (title.contains(lowerQuery) || relativePath.contains(lowerQuery)) {
      return true;
    }

    if (lowerQuery == 'camera' && relativePath.contains('dcim')) return true;
    if (lowerQuery == 'downloads' && relativePath.contains('download')) {
      return true;
    }
    if (lowerQuery == 'screenshots' && relativePath.contains('screenshot')) {
      return true;
    }
    return false;
  }

  void _applyQuery(String rawQuery, {required bool scanUntilEnough}) {
    final query = rawQuery.trim().toLowerCase();
    if (!mounted) return;

    if (query.isEmpty) {
      setState(() {
        _currentQuery = '';
        _filteredAssets = [];
        _isScanningQuery = false;
      });
      return;
    }

    final filtered = _loadedAssets
        .where((asset) => _matchesQuery(asset, query))
        .toList(growable: false);

    setState(() {
      _currentQuery = rawQuery;
      _filteredAssets = filtered;
    });

    if (scanUntilEnough) {
      unawaited(_progressivelyScanForQuery(rawQuery));
    }
  }

  Future<void> _progressivelyScanForQuery(String rawQuery) async {
    final normalized = rawQuery.trim().toLowerCase();
    if (normalized.isEmpty || _isScanningQuery) return;

    _isScanningQuery = true;
    if (mounted) {
      setState(() {});
    }

    try {
      while (mounted &&
          _currentQuery.trim().toLowerCase() == normalized &&
          _hasMoreAssets &&
          _filteredAssets.length < _resultTarget) {
        await _loadNextPage();
      }
    } finally {
      _isScanningQuery = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _applyQuery(query, scanUntilEnough: true);
    });
  }

  void _applyFilter(String label) {
    _searchController.text = label;
    _onSearchChanged(label);
    unawaited(_saveSearch(label));
  }

  void _onAssetTap(AssetEntity asset) {
    unawaited(_saveSearch(_currentQuery));
    if (asset.type == AssetType.video) {
      final relevantVideos = _filteredAssets
          .where((candidate) => candidate.type == AssetType.video)
          .toList(growable: false);
      final index = relevantVideos.indexWhere((entry) => entry.id == asset.id);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoViewerScreen(
            videos: relevantVideos,
            initialIndex: index < 0 ? 0 : index,
          ),
        ),
      );
      return;
    }

    final index = _filteredAssets.indexWhere((entry) => entry.id == asset.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewerScreen(
          images: _filteredAssets,
          index: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  ImageProvider<Object> _thumbnailProviderFor(AssetEntity asset) {
    final key = '${asset.id}@180';
    final provider = _thumbnailProviders.putIfAbsent(
      key,
      () => AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(180),
        thumbnailFormat: ThumbnailFormat.jpeg,
      ),
    );
    if (_thumbnailProviders.length > _maxThumbCacheEntries) {
      _thumbnailProviders.remove(_thumbnailProviders.keys.first);
    }
    return provider;
  }

  Widget _buildSearchThumb(AssetEntity asset) {
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

    return Image(
      image: _thumbnailProviderFor(asset),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [
                          Color(0xFF0A0614),
                          Color(0xFF160D2A),
                          Color(0xFF251242),
                        ]
                      : const [
                          Color(0xFFF4ECFF),
                          Color(0xFFE9DAFF),
                          Color(0xFFD8C1FF),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                color: (isDark ? Colors.black : Colors.white).withOpacity(
                  isDark ? 0.42 : 0.14,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: GlassContainer(
                borderRadius: BorderRadius.circular(32),
                enableBlur: false,
                blurSigma: 0,
                backgroundColor: isDark
                    ? const Color(0xFF121212).withValues(alpha: 0.94)
                    : const Color(0xFFFFFFFF).withValues(alpha: 0.96),
                child: Column(
                  children: [
                    _buildSearchBar(isDark, colorScheme),
                    Expanded(
                      child: _currentQuery.isEmpty
                          ? _buildSuggestions(colorScheme)
                          : _buildResults(colorScheme),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Hero(
        tag: 'search_icon',
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(isDark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
              onSubmitted: (value) => unawaited(_saveSearch(value)),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
              decoration: InputDecoration(
                hintText: 'Search photos and videos...',
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.4),
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                  color: colorScheme.onSurface.withOpacity(0.72),
                ),
                suffixIcon: _currentQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _applyQuery('', scanUntilEnough: false);
                        },
                        color: colorScheme.onSurface.withOpacity(0.72),
                      )
                    : Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurface.withOpacity(0.4),
                        size: 22,
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions(ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_recentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Text(
              'Recent Searches',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ..._recentSearches.map(
            (search) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Icon(
                Icons.history_rounded,
                color: colorScheme.onSurface.withOpacity(0.5),
                size: 20,
              ),
              title: Text(
                search,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 15,
                ),
              ),
              onTap: () {
                _searchController.text = search;
                _onSearchChanged(search);
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Text(
            'Quick Filters',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
        children: _quickFilters.map((filter) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  avatar: Icon(
                    filter['icon'] as IconData,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  label: Text(filter['label'] as String),
                  onPressed: () => _applyFilter(filter['label'] as String),
                  backgroundColor:
                      colorScheme.surface.withOpacity(isDark ? 0.28 : 0.44),
                  side: BorderSide(color: Colors.white.withOpacity(0.1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ),
        const SizedBox(height: 20),
        if (_isLoadingInitial)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '${_loadedAssets.length} media items indexed so far',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.65),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResults(ColorScheme colorScheme) {
    if (_isLoadingInitial && _loadedAssets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredAssets.isEmpty && !_isScanningQuery && !_isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 64,
                color: colorScheme.onSurface.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              Text(
                'No results found',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try searching "camera" or "screenshots"',
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final subtitle = _isScanningQuery || _hasMoreAssets
        ? 'Search results (${_filteredAssets.length} so far)'
        : 'Search results (${_filteredAssets.length})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Row(
            children: [
              Text(
                subtitle,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_isScanningQuery || _isLoadingMore)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _resultsScrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 900,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _filteredAssets.length,
            itemBuilder: (context, index) {
              final asset = _filteredAssets[index];
              return grid_widgets.buildGalleryGridTile(
                asset: asset,
                image: _buildSearchThumb(asset),
                onTap: () => _onAssetTap(asset),
                onDoubleTap: () {},
                isFavorite: false,
                isAnimating: false,
              );
            },
          ),
        ),
      ],
    );
  }
}
