import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'package:photo_manager/photo_manager.dart';
import 'gallery/gallery_album_widgets.dart' as gallery_album_widgets;
import 'glass_container.dart';
import 'services/music_service.dart';
import 'services/audio_player_service.dart';
import 'services/recycle_bin_database.dart';
import 'music_player_screen.dart';

class MusicScreen extends StatefulWidget {
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
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
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
      // Load binned IDs to filter
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
      
      // Navigate immediately for better perceived performance
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

      // Start playback in background if not already playing this song
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [
                          Color(0xFF050505),
                          Color(0xFF080808),
                          Color(0xFF0C0C0C),
                        ]
                      : const [
                          Color(0xFFFFFFFF),
                          Color(0xFFF9F9F9),
                          Color(0xFFF0F0F0),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
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
                SliverAppBar(
                  pinned: false,
                  floating: true,
                  snap: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  toolbarHeight: 68,
                  titleSpacing: 16,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Music',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${allMusics.length} tracks',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.62),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: RepaintBoundary(
                      child: GlassContainer(
                        borderRadius: BorderRadius.circular(32),
                        enableBlur: false,
                        blurSigma: 0,
                        backgroundColor: isDark
                            ? const Color(0xFF121212).withValues(alpha: 0.94)
                            : const Color(0xFFFFFFFF).withValues(alpha: 0.96),
                        borderColor: Colors.white
                            .withValues(alpha: isDark ? 0.14 : 0.18),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Library',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Enjoy your collection of songs',
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
                                  _buildStatsChip(
                                    icon: Icons.music_note_rounded,
                                    label: '${allMusics.length} songs',
                                    color: colorScheme.primaryContainer
                                        .withOpacity(0.88),
                                    textColor: colorScheme.onPrimaryContainer,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: GlassContainer(
                      borderRadius: BorderRadius.circular(28),
                      enableBlur: false,
                      blurSigma: 0,
                      backgroundColor: isDark
                          ? const Color(0xFF121212).withValues(alpha: 0.92)
                          : const Color(0xFFFFFFFF).withValues(alpha: 0.94),
                      child: TextField(
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 32),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary.withOpacity(0.5),
                                ),
                              ),
                            );
                          }
                          final music = filteredMusics[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == filteredMusics.length - 1 &&
                                      !isLoadingMore
                                  ? 0
                                  : 8,
                            ),
                            child: _buildMusicTile(
                              music,
                              index,
                              colorScheme,
                              isDark,
                            ),
                          );
                        },
                        childCount:
                            filteredMusics.length + (isLoadingMore ? 1 : 0),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMusicTile(
    MusicFile music,
    int index,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return ValueListenableBuilder<MusicFile?>(
      valueListenable: audioPlayerService.currentMusicNotifier,
      builder: (context, currentMusic, _) {
        final isCurrentSong = currentMusic?.id == music.id;
        final isSelected = widget.selectedIds.contains(music.id);
        final isSelectionMode = widget.selectedIds.isNotEmpty;

        return StreamBuilder<PlayerState>(
          stream: audioPlayerService.playerStateStream,
          builder: (context, playerSnapshot) {
            final isPlaying = playerSnapshot.data?.playing ?? false;
            final shouldHighlight = isCurrentSong && isPlaying;

            return gallery_album_widgets.buildPremiumListTileShell(
              colorScheme: colorScheme,
              isDark: isDark,
              isSelected: isSelected || shouldHighlight,
              onTap: () {
                if (isSelectionMode) {
                  if (music.asset != null) {
                    widget.onSelectionToggle(music.asset!);
                    HapticFeedback.lightImpact();
                  }
                } else {
                  playMusic(music, index);
                }
              },
              onLongPress: () {
                if (!isSelectionMode && music.asset != null) {
                  widget.onSelectionToggle(music.asset!);
                  HapticFeedback.mediumImpact();
                }
              },
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 74,
                      height: 74,
                      child: _buildArtwork(music, colorScheme),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          music.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${music.formattedDuration} • ${music.formattedSize}',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (isCurrentSong) {
                        if (isPlaying) {
                          audioPlayerService.pause();
                        } else {
                          audioPlayerService.play();
                        }
                      } else {
                        audioPlayerService.setPlaylist(
                          filteredMusics,
                          startIndex: index,
                        );
                      }
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: shouldHighlight
                            ? music.themeColor.withValues(alpha: 0.94)
                            : colorScheme.primaryContainer
                                .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isCurrentSong && isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: shouldHighlight
                            ? Colors.white
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
