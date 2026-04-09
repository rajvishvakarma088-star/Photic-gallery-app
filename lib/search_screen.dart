import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gallery_service.dart';
import 'glass_container.dart';
import 'viewer_screen.dart';
import 'video_viewer_screen.dart';
import 'gallery/gallery_grid_widgets.dart' as grid_widgets;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final GalleryService _service = GalleryService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  List<AssetEntity> _allAssets = [];
  List<AssetEntity> _filteredAssets = [];
  List<String> _recentSearches = [];
  String _currentQuery = '';
  
  final List<Map<String, dynamic>> _quickFilters = [
    {'label': 'Camera', 'icon': Icons.camera_alt_rounded},
    {'label': 'Downloads', 'icon': Icons.download_rounded},
    {'label': 'Screenshots', 'icon': Icons.screenshot_rounded},
    {'label': 'Videos', 'icon': Icons.videocam_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadRecentSearches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadInitialData() async {
    final assets = await _service.fetchAllAssets();
    if (mounted) {
      setState(() {
        _allAssets = assets;
        _filteredAssets = assets;
      });
    }
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  Future<void> _saveSearch(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList('recent_searches') ?? [];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 5) searches.removeLast();
    await prefs.setStringList('recent_searches', searches);
    _loadRecentSearches();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _currentQuery = query;
      if (query.isEmpty) {
        _filteredAssets = _allAssets;
      } else {
        final lowerQuery = query.toLowerCase();
        
        // Spec: match Name, Folder, or File type
        _filteredAssets = _allAssets.where((asset) {
          // Special case for "Videos" chip/search
          if (lowerQuery == 'videos' && asset.type == AssetType.video) return true;
          
          final titleMatch = asset.title?.toLowerCase().contains(lowerQuery) ?? false;
          final pathMatch = asset.relativePath?.toLowerCase().contains(lowerQuery) ?? false;
          
          // For chips like "Camera", "Screenshots", "Downloads", ensure we match the folder
          if (lowerQuery == 'camera' && (pathMatch || (asset.relativePath?.contains('DCIM') ?? false))) return true;
          if (lowerQuery == 'downloads' && (pathMatch || (asset.relativePath?.contains('Download') ?? false))) return true;
          if (lowerQuery == 'screenshots' && (pathMatch || (asset.relativePath?.contains('Screenshots') ?? false))) return true;
          
          return titleMatch || pathMatch;
        }).toList();
      }
    });
  }

  void _applyFilter(String label) {
    setState(() {
      _searchController.text = label;
      _onSearchChanged(label);
    });
    _saveSearch(label);
  }

  void _onAssetTap(AssetEntity asset) {
    _saveSearch(_currentQuery);
    if (asset.type == AssetType.video) {
      final relevantVideos =
          _filteredAssets.where((a) => a.type == AssetType.video).toList();
      final index = relevantVideos.indexWhere((e) => e.id == asset.id);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoViewerScreen(
            videos: relevantVideos,
            initialIndex: index != -1 ? index : 0,
          ),
        ),
      );
    } else {
      final index = _filteredAssets.indexWhere((e) => e.id == asset.id);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ViewerScreen(
            images: _filteredAssets,
            index: index != -1 ? index : 0,
          ),
        ),
      );
    }
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
          // Background Backdrop Filter for subtle glass effect on Gallery
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: (isDark ? Colors.black : Colors.white).withOpacity(isDark ? 0.42 : 0.22),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: GlassContainer(
                borderRadius: BorderRadius.circular(32),
                blurSigma: 28,
                child: Column(
                  children: [
                    _buildSearchBar(isDark, colorScheme),
                    Expanded(
                      child: _currentQuery.isEmpty
                          ? _buildSuggestions(isDark, colorScheme)
                          : _buildResults(isDark, colorScheme),
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
              color: colorScheme.onSurface.withOpacity(isDark ? 0.06 : 0.04),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
              onSubmitted: (val) => _saveSearch(val),
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
              decoration: InputDecoration(
                hintText: 'Search photos...',
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.4),
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  onPressed: () => Navigator.pop(context),
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
                suffixIcon: _currentQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        color: colorScheme.onSurface.withOpacity(0.7),
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

  Widget _buildSuggestions(bool isDark, ColorScheme colorScheme) {
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
          ..._recentSearches.map((search) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: Icon(Icons.history_rounded, 
                  color: colorScheme.onSurface.withOpacity(0.5), size: 20),
                title: Text(search, 
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 15)),
                onTap: () {
                  _searchController.text = search;
                  _onSearchChanged(search);
                },
              )),
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
                  avatar: Icon(filter['icon'], size: 16, 
                    color: colorScheme.primary),
                  label: Text(filter['label']),
                  onPressed: () => _applyFilter(filter['label']),
                  backgroundColor: colorScheme.surface.withOpacity(0.3),
                  side: BorderSide(color: Colors.white.withOpacity(0.12)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildResults(bool isDark, ColorScheme colorScheme) {
    if (_filteredAssets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 64, 
                color: colorScheme.onSurface.withOpacity(0.2)),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Text(
            'Search results (${_filteredAssets.length})',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: _buildPhotoGrid(_filteredAssets, colorScheme)),
      ],
    );
  }

  Widget _buildPhotoGrid(List<AssetEntity> assets, ColorScheme colorScheme) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: assets.length > 30 && _currentQuery.isEmpty ? 30 : assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        return grid_widgets.buildGalleryGridTile(
          asset: asset,
          image: AssetEntityImage(
            asset,
            isOriginal: false,
            thumbnailSize: const ThumbnailSize.square(180),
            fit: BoxFit.cover,
          ),
          onTap: () => _onAssetTap(asset),
          onDoubleTap: () {},
          isFavorite: false, // Can be refined later
          isAnimating: false,
        );
      },
    );
  }
}
