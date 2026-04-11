import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/settings_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'package:photo_manager/photo_manager.dart';
import 'gallery/gallery_album_widgets.dart' as gallery_album_widgets;
import 'glass_container.dart';
import 'services/music_service.dart';
import 'services/audio_player_service.dart';
import 'services/recycle_bin_database.dart';
import 'music_player_screen.dart';

class MusicScreen extends ConsumerStatefulWidget {
  final AudioPlayerService? audioPlayerService;
  final Set<String> selectedIds;
  final Function(AssetEntity) onSelectionToggle;

  const MusicScreen({
    Key? key,
    this.audioPlayerService,
    this.selectedIds = const {},
    required this.onSelectionToggle,
  }) : super(key: key);

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  static const int _artworkCacheEntries = 500;
  final MusicService musicService = MusicService();
  late AudioPlayerService audioPlayerService;
  final Map<String, ImageProvider> _artworkCache = {};
  
  List<MusicFile> allMusics = [];
  List<MusicFile> filteredMusics = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  String searchQuery = '';
  bool _isNavigating = false;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _hideTopChrome = false;
  double _lastScrollOffset = 0;
  final double _scrollThreshold = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    audioPlayerService = widget.audioPlayerService ?? AudioPlayerService();
    _scrollController.addListener(_onScroll);
    loadMusics(initial: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    bool shouldHide;
    if (offset < _scrollThreshold) {
      shouldHide = false;
    } else if (delta > 2) {
      shouldHide = true;
    } else if (delta < -2) {
      shouldHide = false;
    } else {
      shouldHide = _hideTopChrome;
    }

    if (shouldHide != _hideTopChrome) {
      setState(() {
        _hideTopChrome = shouldHide;
      });
    }

    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!isLoadingMore && hasMore && searchQuery.isEmpty) {
        loadMusics();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _artworkCache.clear();
    super.dispose();
  }

  Widget _buildArtwork(MusicFile music, ColorScheme colorScheme) {
    final fallback = _buildPlaceholder(colorScheme);

    return FutureBuilder<Uint8List?>(
      future: music.getThumbnail(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          final key = '${music.id}@memory';
          final provider = _artworkCache.putIfAbsent(
            key,
            () => MemoryImage(snapshot.data!),
          );
          if (_artworkCache.length > _artworkCacheEntries) {
            _artworkCache.remove(_artworkCache.keys.first);
          }
          return Image(
            image: provider,
            fit: BoxFit.cover,
          );
        }

        if (music.albumArtPath != null) {
          final key = '${music.id}@file';
          final provider = _artworkCache.putIfAbsent(
            key,
            () => ResizeImage(
              FileImage(File(music.albumArtPath!)),
              width: 150,
              height: 150,
            ),
          );
          if (_artworkCache.length > _artworkCacheEntries) {
            _artworkCache.remove(_artworkCache.keys.first);
          }
          return Image(
            image: provider,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => fallback,
          );
        }

        return fallback;
      },
    );
  }

  Future<void> loadMusics({bool initial = false, bool refresh = false}) async {
    if (initial || refresh) {
      final permission = await musicService.requestMusicPermission();
      if (!permission.hasAccess) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
        });
        return;
      }
    }
    
    if (initial) {
      final cached = musicService.musicCache;
      if (cached.isNotEmpty && !refresh) {
        setState(() {
          allMusics = List.from(cached);
          filteredMusics = allMusics;
          isLoading = false;
        });
        return;
      }
      setState(() => isLoading = true);
    } else if (!refresh) {
      setState(() => isLoadingMore = true);
    }

    try {
      final binnedIds = await RecycleBinDatabase.instance.loadAssetIds();
      musicService.setBinnedIds(binnedIds);
      
      final musics = await musicService.fetchMusicsPaged(refresh: refresh);
      if (!mounted) return;
      
      setState(() {
        allMusics = List.from(musics);
        if (searchQuery.isEmpty) {
          filteredMusics = allMusics;
        } else {
          _searchMusics(searchQuery);
        }
        isLoading = false;
        isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      print('Error loading musics: $e');
      setState(() {
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  void _searchMusics(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredMusics = allMusics;
      } else {
        filteredMusics = allMusics
            .where((music) =>
                music.displayName.toLowerCase().contains(query.toLowerCase()) ||
                music.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> playMusic(MusicFile music, int index) async {
    if (_isNavigating) return;
    _isNavigating = true;
    
    try {
      HapticFeedback.mediumImpact();
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MusicPlayerScreen(
            music: music,
            audioPlayerService: audioPlayerService,
          ),
        ),
      ).then((_) {
        _isNavigating = false;
      });

      if (audioPlayerService.currentMusic?.id != music.id) {
        audioPlayerService.setPlaylist(filteredMusics, startIndex: index);
      }
    } catch (e) {
      print('Error navigating to player: $e');
      _isNavigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = ref.watch(settingsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = settings.isDark(context);
    final topBarColor = settings.getTopBarColor(isDark).withValues(alpha: 0.85);
    final overlayStyle = (isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: !_hideTopChrome
          ? AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text(
          'Music',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded, size: 24),
            onPressed: () {
              _searchFocusNode.requestFocus();
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: topBarColor.withValues(alpha: isDark ? 0.75 : 0.82),
                border: Border(
                  bottom: BorderSide(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: isDark ? 0.1 : 0.06),
                    width: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
        systemOverlayStyle: overlayStyle,
      ) : const PreferredSize(
          preferredSize: Size.zero,
          child: SizedBox.shrink(),
        ),
      body: Stack(
        children: [
          // 1. Base Gradient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: settings.getBackgroundGradient(isDark),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // 2. Decorative Orbs
          Positioned(
            top: -80,
            right: -40,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8B5CF6)
                      .withValues(alpha: isDark ? 0.05 : 0.08),
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
                  color: const Color(0xFFC4B5FD)
                      .withValues(alpha: isDark ? 0.03 : 0.12),
                ),
              ),
            ),
          ),
          // 3. Content
          if (isLoading)
            Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            )
          else if (allMusics.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.music_note_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No music found',
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try adding songs to Download, Music, or Documents. Then refresh to reload.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => loadMusics(refresh: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
            )
          else
            CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 104)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: RepaintBoundary(
                      child: GlassContainer(
                        borderRadius: BorderRadius.circular(32),
                        enableBlur: false,
                        blurSigma: 0,
                        backgroundColor: isDark
                            ? const Color(0xFF121212).withValues(alpha: 0.92)
                            : const Color(0xFFFFFFFF).withValues(alpha: 0.94),
                        child: TextField(
                          focusNode: _searchFocusNode,
                          onChanged: _searchMusics,
                          decoration: InputDecoration(
                            hintText: 'Search songs...',
                            border: InputBorder.none,
                            prefixIcon: const Icon(Icons.search),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            hintStyle: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (filteredMusics.isEmpty)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No results for "$searchQuery"',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index == filteredMusics.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'End of collection',
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withOpacity(0.6),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          }

                          final music = filteredMusics[index];
                          
                          return ValueListenableBuilder<MusicFile?>(
                            valueListenable: audioPlayerService.currentMusicNotifier,
                            builder: (context, currentMusic, _) {
                              final isCurrentSong = currentMusic?.id == music.id;
                              
                              return StreamBuilder<PlayerState>(
                                stream: audioPlayerService.playerStateStream,
                                builder: (context, playerSnapshot) {
                                  final isPlaying = playerSnapshot.data?.playing ?? false;
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: gallery_album_widgets.MusicListItem(
                                      music: music,
                                      isCurrent: isCurrentSong,
                                      isPlaying: isPlaying,
                                      onTap: () => playMusic(music, index),
                                      onPlayPause: () {
                                        if (isCurrentSong) {
                                          if (isPlaying) {
                                            audioPlayerService.pause();
                                          } else {
                                            audioPlayerService.play();
                                          }
                                        } else {
                                          playMusic(music, index);
                                        }
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                        childCount: filteredMusics.length +
                            (hasMore && searchQuery.isEmpty ? 1 : 0),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatsChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHigh,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}
