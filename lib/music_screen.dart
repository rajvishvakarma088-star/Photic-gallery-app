import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:photo_manager/photo_manager.dart';
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
  final MusicService musicService = MusicService();
  late AudioPlayerService audioPlayerService;
  
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
    super.dispose();
  }

  Future<void> loadMusics({bool initial = false, bool refresh = false}) async {
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

    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: colorScheme.primary,
        ),
      );
    }

    if (allMusics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            SizedBox(
              width: 250,
              child: Text(
                'Try adding songs to your Download, Music, or Documents folder. Then tap refresh to reload.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => loadMusics(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: isDark
                    ? Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Music',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
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
                                  color: colorScheme.primaryContainer.withOpacity(0.9),
                                  textColor: colorScheme.onPrimaryContainer,
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Music',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
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
                                    color: colorScheme.primaryContainer.withOpacity(0.9),
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
        ),
        // Search bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: GlassContainer(
              borderRadius: BorderRadius.circular(28),
              child: TextField(
                onChanged: _searchMusics,
                decoration: InputDecoration(
                  hintText: 'Search songs...',
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  hintStyle: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Music list
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
                        padding: const EdgeInsets.symmetric(vertical: 32),
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
                      bottom: index == filteredMusics.length - 1 && !isLoadingMore ? 0 : 8,
                    ),
                    child: _buildMusicTile(music, index, colorScheme, isDark),
                  );
                },
                childCount: filteredMusics.length + (isLoadingMore ? 1 : 0),
              ),
            ),
          ),
      ],
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

            return GestureDetector(
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
              child: GlassContainer(
                borderRadius: BorderRadius.circular(26),
                enableBlur: false,
                borderColor: isSelected ? colorScheme.primary.withOpacity(0.5) : Colors.transparent,
                backgroundColor: isSelected ? colorScheme.primary.withOpacity(0.08) : null,
                child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 74,
                      height: 74,
                      child: FutureBuilder<Uint8List?>(
                        future: music.getThumbnail(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                              cacheHeight: 150,
                              cacheWidth: 150,
                            );
                          }
                          
                          if (music.albumArtPath != null) {
                            return Image.file(
                              File(music.albumArtPath!),
                              fit: BoxFit.cover,
                              cacheHeight: 150,
                              cacheWidth: 150,
                              errorBuilder: (c, e, s) => _buildPlaceholder(colorScheme),
                            );
                          }

                          return _buildPlaceholder(colorScheme);
                        },
                      ),
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
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${music.formattedDuration} • ${music.formattedSize}',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.68),
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
                        audioPlayerService.setPlaylist(filteredMusics, startIndex: index);
                      }
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: shouldHighlight 
                            ? music.themeColor.withOpacity(0.92) 
                            : colorScheme.primaryContainer.withOpacity(0.92),
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
            ),
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
