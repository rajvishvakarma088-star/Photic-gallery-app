import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'glass_container.dart';
import 'services/music_service.dart';
import 'services/audio_player_service.dart';
import 'utils/lru_cache.dart';

class MusicPlayerScreen extends StatefulWidget {
  final MusicFile music;
  final AudioPlayerService audioPlayerService;

  const MusicPlayerScreen({
    Key? key,
    required this.music,
    required this.audioPlayerService,
  }) : super(key: key);

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin {
  static const int _artworkCacheEntries = 120;
  late AudioPlayerService _audioPlayer;
  late AnimationController _albumArtController;
  late Animation<double> _albumArtScale;
  late Animation<double> _albumArtOpacity;
  final LruMap<String, ImageProvider> _artworkCache =
      LruMap<String, ImageProvider>(_artworkCacheEntries);
  
  MusicFile? _previousMusic;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _audioPlayer = widget.audioPlayerService;
    _previousMusic = widget.music;
    
    _albumArtController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _albumArtScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _albumArtController, curve: Curves.elasticOut),
    );
    
    _albumArtOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _albumArtController, curve: Curves.easeInOut),
    );
    
    _albumArtController.forward();
    _audioPlayer.currentMusicNotifier.addListener(_onMusicChanged);
  }

  void _onMusicChanged() {
    if (mounted && _audioPlayer.currentMusicNotifier.value != null && 
        _previousMusic?.id != _audioPlayer.currentMusicNotifier.value?.id) {
      _previousMusic = _audioPlayer.currentMusicNotifier.value;
      _albumArtController.reset();
      _albumArtController.forward();
    }
  }

  @override
  void didUpdateWidget(MusicPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.music.id != widget.music.id) {
      _previousMusic = oldWidget.music;
      _albumArtController.reset();
      _albumArtController.forward();
    }
  }

  @override
  void dispose() {
    _audioPlayer.currentMusicNotifier.removeListener(_onMusicChanged);
    _albumArtController.dispose();
    _artworkCache.clear();
    super.dispose();
  }

  Widget _buildAlbumArt(MusicFile music) {
    return FutureBuilder<Uint8List?>(
      future: music.fetchAlbumArt(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          final provider = _artworkCache.putIfAbsent(
            '${music.id}@player-memory',
            () => MemoryImage(snapshot.data!),
          );
          return Image(
            image: provider,
            fit: BoxFit.cover,
          );
        }

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: music.thumbnailGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _triggerHaptic(HapticType type) {
    switch (type) {
      case HapticType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticType.heavy:
        HapticFeedback.heavyImpact();
        break;
    }
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset > 100) {
      _triggerHaptic(HapticType.medium);
      Navigator.pop(context);
    } else {
      setState(() {
        _dragOffset = 0;
      });
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (details.primaryVelocity == null) return;
    if (details.primaryVelocity! > 300) {
      // Swiped Right -> Previous
      _triggerHaptic(HapticType.medium);
      _audioPlayer.previous();
    } else if (details.primaryVelocity! < -300) {
      // Swiped Left -> Next
      _triggerHaptic(HapticType.medium);
      _audioPlayer.next();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async {
        _triggerHaptic(HapticType.light);
        return true;
      },
      child: GestureDetector(
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: () {
                _triggerHaptic(HapticType.light);
                Navigator.pop(context);
              },
            ),
          ),
          body: SafeArea(
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ValueListenableBuilder<MusicFile?>(
                  valueListenable: _audioPlayer.currentMusicNotifier,
                  builder: (context, activeMusic, child) {
                    final currentMusic = activeMusic ?? widget.music;
                    return Column(
                      children: [
                        const SizedBox(height: 40),
                        // Animated album art with actual image or theme color
                        ScaleTransition(
                          scale: _albumArtScale,
                          child: FadeTransition(
                            opacity: _albumArtOpacity,
                            child: GlassContainer(
                              borderRadius: BorderRadius.circular(40),
                              child: Container(
                                width: double.infinity,
                                height: 320,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(40),
                                  boxShadow: [
                                    BoxShadow(
                                      color: currentMusic.themeColor.withOpacity(0.5),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(40),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Album art or theme color background
                                      _buildAlbumArt(currentMusic),
                                      // Music note icon overlay (only if no album art found yet)
                                      FutureBuilder<Uint8List?>(
                                        future: currentMusic.fetchAlbumArt(),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.done && snapshot.data == null && !currentMusic.hasAlbumArt) {
                                            return Center(
                                              child: Icon(
                                                Icons.music_note_rounded,
                                                size: 140,
                                                color: Colors.white.withOpacity(0.9),
                                              ),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        // Animated song info
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(opacity: animation, child: child);
                          },
                          child: Column(
                            key: ValueKey(currentMusic.id),
                            children: [
                              Text(
                                currentMusic.displayName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                currentMusic.formattedSize,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                  fontSize: 14,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 48),
                    // Progress bar
                    StreamBuilder<Duration>(
                      stream: _audioPlayer.positionStream,
                      builder: (context, snapshotPosition) {
                        return StreamBuilder<Duration?>(
                          stream: _audioPlayer.durationStream,
                          builder: (context, snapshotDuration) {
                            final position = snapshotPosition.data ?? Duration.zero;
                            final duration = snapshotDuration.data ?? Duration.zero;
                            final sliderValue = duration.inMilliseconds > 0
                                ? position.inMilliseconds / duration.inMilliseconds
                                : 0.0;

                            return Column(
                              children: [
                                GlassContainer(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 6,
                                      thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius: 10,
                                        elevation: 2,
                                      ),
                                      overlayShape: RoundSliderOverlayShape(
                                        overlayRadius: 14,
                                      ),
                                    ),
                                    child: Slider(
                                      value: sliderValue.clamp(0.0, 1.0),
                                      onChanged: (value) {
                                        final position = Duration(
                                          milliseconds: (value *
                                                  duration.inMilliseconds)
                                              .toInt(),
                                        );
                                        _audioPlayer.seek(position);
                                      },
                                      activeColor: (_audioPlayer.currentMusic ?? widget.music).themeColor,
                                      inactiveColor: colorScheme.primary.withOpacity(0.2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: TextStyle(
                                          color: colorScheme.onSurface.withOpacity(0.7),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: TextStyle(
                                          color: colorScheme.onSurface.withOpacity(0.7),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const Spacer(),
                    // Controls
                    StreamBuilder<PlayerState>(
                      stream: _audioPlayer.playerStateStream,
                      builder: (context, snapshot) {
                        final playerState = snapshot.data;
                        final isPlaying = playerState?.playing ?? false;

                        return Column(
                          children: [
                            const SizedBox(height: 24),
                            // Main controls
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Previous button
                                GestureDetector(
                                  onTap: () {
                                    _triggerHaptic(HapticType.medium);
                                    _audioPlayer.previous();
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (_audioPlayer.currentMusic ?? widget.music).themeColor.withOpacity(0.1),
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: Icon(
                                      Icons.skip_previous_rounded,
                                      size: 32,
                                      color: (_audioPlayer.currentMusic ?? widget.music).themeColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 32),
                                // Play/Pause button
                                GestureDetector(
                                  onTap: () {
                                    _triggerHaptic(HapticType.heavy);
                                    if (isPlaying) {
                                      _audioPlayer.pause();
                                    } else {
                                      _audioPlayer.play();
                                    }
                                  },
                                  child: GlassContainer(
                                    borderRadius: BorderRadius.circular(70),
                                    child: Container(
                                      width: 90,
                                      height: 90,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(70),
                                        gradient: LinearGradient(
                                          colors: [
                                            (_audioPlayer.currentMusic ?? widget.music).themeColor.withOpacity(0.9),
                                            (_audioPlayer.currentMusic ?? widget.music).themeColor.withOpacity(0.7),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (_audioPlayer.currentMusic ?? widget.music).themeColor.withOpacity(0.4),
                                            blurRadius: 12,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        transitionBuilder: (child, animation) {
                                          return ScaleTransition(scale: animation, child: child);
                                        },
                                        child: Icon(
                                          isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          key: ValueKey(isPlaying),
                                          size: 48,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 32),
                                // Next button
                                GestureDetector(
                                  onTap: () {
                                    _triggerHaptic(HapticType.medium);
                                    _audioPlayer.next();
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: (_audioPlayer.currentMusic ?? widget.music).themeColor.withOpacity(0.1),
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: Icon(
                                      Icons.skip_next_rounded,
                                      size: 32,
                                      color: (_audioPlayer.currentMusic ?? widget.music).themeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 48),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}

enum HapticType { light, medium, heavy }
