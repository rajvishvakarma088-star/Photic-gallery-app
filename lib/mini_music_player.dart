import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'services/music_service.dart';
import 'services/audio_player_service.dart';

class MiniMusicPlayer extends StatefulWidget {
  final AudioPlayerService audioPlayerService;
  final VoidCallback onTap;

  const MiniMusicPlayer({
    Key? key,
    required this.audioPlayerService,
    required this.onTap,
  }) : super(key: key);

  @override
  State<MiniMusicPlayer> createState() => _MiniMusicPlayerState();
}

class _MiniMusicPlayerState extends State<MiniMusicPlayer> {
  static const int _artworkCacheEntries = 80;
  final Map<String, ImageProvider> _artworkCache = {};

  @override
  void dispose() {
    _artworkCache.clear();
    super.dispose();
  }

  Widget _buildArtwork(MusicFile music) {
    Widget fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: music.thumbnailGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded,
            color: Colors.white.withOpacity(0.9), size: 24),
      ),
    );

    return FutureBuilder<Uint8List?>(
      future: music.getThumbnail(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          final key = '${music.id}@mini-memory';
          final provider = _artworkCache.putIfAbsent(
            key,
            () => MemoryImage(snapshot.data!),
          );
          if (_artworkCache.length > _artworkCacheEntries) {
            _artworkCache.remove(_artworkCache.keys.first);
          }
          return Image(image: provider, fit: BoxFit.cover);
        }
        if (music.hasAlbumArt) {
          if (music.albumArtBytes != null) {
            final key = '${music.id}@mini-bytes';
            final provider = _artworkCache.putIfAbsent(
              key,
              () => MemoryImage(music.albumArtBytes!),
            );
            if (_artworkCache.length > _artworkCacheEntries) {
              _artworkCache.remove(_artworkCache.keys.first);
            }
            return Image(
              image: provider,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            );
          } else if (music.albumArtPath != null) {
            final key = '${music.id}@mini-file';
            final provider = _artworkCache.putIfAbsent(
              key,
              () => ResizeImage(
                FileImage(File(music.albumArtPath!)),
                width: 180,
                height: 180,
              ),
            );
            if (_artworkCache.length > _artworkCacheEntries) {
              _artworkCache.remove(_artworkCache.keys.first);
            }
            return Image(
              image: provider,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            );
          }
        }
        return fallback;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioPlayer = widget.audioPlayerService;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<PlayerState>(
      stream: audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final music = audioPlayer.currentMusic;
        if (music == null) return const SizedBox.shrink();

        final isPlaying = snapshot.data?.playing ?? false;
        final themeColor = music.themeColor;

        return ValueListenableBuilder<bool>(
          valueListenable: audioPlayer.isMiniPlayerVisible,
          builder: (context, isVisible, _) {
            if (!isVisible) return const SizedBox.shrink();

            // Entry animation using TweenAnimationBuilder – no controller needed
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 18),
                    child: child,
                  ),
                );
              },
              child: Dismissible(
                key: const ValueKey('mini_player_dismissible'),
                direction: DismissDirection.down,
                onDismissed: (_) {
                  audioPlayer.isMiniPlayerVisible.value = false;
                  audioPlayer.pause();
                },
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: SizedBox(
                    height: 76,
                    child: _LiquidGlassCard(
                      music: music,
                      audioPlayer: audioPlayer,
                      isPlaying: isPlaying,
                      themeColor: themeColor,
                      isDark: isDark,
                      artworkBuilder: _buildArtwork,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium liquid-glass card
// ─────────────────────────────────────────────────────────────────────────────

class _LiquidGlassCard extends StatelessWidget {
  final MusicFile music;
  final AudioPlayerService audioPlayer;
  final bool isPlaying;
  final Color themeColor;
  final bool isDark;
  final Widget Function(MusicFile) artworkBuilder;

  const _LiquidGlassCard({
    required this.music,
    required this.audioPlayer,
    required this.isPlaying,
    required this.themeColor,
    required this.isDark,
    required this.artworkBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final accentGlow = themeColor.withOpacity(isDark ? 0.3 : 0.14);
    final borderColor =
        isDark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.72);
    final bgTop = isDark
        ? const Color(0xFF1A1030).withOpacity(0.72)
        : Colors.white.withOpacity(0.64);
    final bgBottom = isDark
        ? themeColor.withOpacity(0.15)
        : themeColor.withOpacity(0.06);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.5, 1.0],
              colors: [bgTop, isDark ? Colors.white.withOpacity(0.07) : Colors.white.withOpacity(0.48), bgBottom],
            ),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(color: accentGlow, blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 5)),
              BoxShadow(color: Colors.black.withOpacity(isDark ? 0.44 : 0.12), blurRadius: 18, offset: const Offset(0, 4)),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Specular highlight at top
              Positioned(
                top: 0, left: 0, right: 0, height: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(isDark ? 0.14 : 0.32),
                        Colors.white.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
              // Accent colour wash right side
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 110,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            themeColor.withOpacity(isDark ? 0.18 : 0.07),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Content row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    // Album art
                    _ArtTile(music: music, themeColor: themeColor, isDark: isDark, artworkBuilder: artworkBuilder),
                    const SizedBox(width: 12),
                    // Info + progress
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            music.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF1A0A2E),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPlaying) ...[
                                _EqBars(color: themeColor),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                isPlaying ? 'Now Playing' : 'Paused',
                                style: TextStyle(
                                  color: isDark
                                      ? themeColor.withOpacity(0.85)
                                      : themeColor.withOpacity(0.72),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          _MiniProgressBar(
                              audioPlayer: audioPlayer,
                              themeColor: themeColor,
                              isDark: isDark),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Skip prev
                    _IconBtn(
                      icon: Icons.skip_previous_rounded,
                      color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.5),
                      size: 22,
                      onTap: () { HapticFeedback.lightImpact(); audioPlayer.previous(); },
                    ),
                    const SizedBox(width: 4),
                    // Play / Pause
                    _PlayBtn(
                      isPlaying: isPlaying,
                      themeColor: themeColor,
                      isDark: isDark,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        isPlaying ? audioPlayer.pause() : audioPlayer.play();
                      },
                    ),
                    const SizedBox(width: 4),
                    // Skip next
                    _IconBtn(
                      icon: Icons.skip_next_rounded,
                      color: isDark ? Colors.white.withOpacity(0.6) : Colors.black.withOpacity(0.5),
                      size: 22,
                      onTap: () { HapticFeedback.lightImpact(); audioPlayer.next(); },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Album art tile
// ─────────────────────────────────────────────────────────────────────────────

class _ArtTile extends StatelessWidget {
  final MusicFile music;
  final Color themeColor;
  final bool isDark;
  final Widget Function(MusicFile) artworkBuilder;

  const _ArtTile({
    required this.music,
    required this.themeColor,
    required this.isDark,
    required this.artworkBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: themeColor.withOpacity(isDark ? 0.5 : 0.28),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(isDark ? 0.22 : 0.5),
          width: 1.4,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.6),
        child: Hero(
          tag: 'music_art_${music.id}',
          child: artworkBuilder(music),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Play / Pause button
// ─────────────────────────────────────────────────────────────────────────────

class _PlayBtn extends StatelessWidget {
  final bool isPlaying;
  final Color themeColor;
  final bool isDark;
  final VoidCallback onTap;

  const _PlayBtn({
    required this.isPlaying,
    required this.themeColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [themeColor.withOpacity(0.92), themeColor.withOpacity(0.60)],
          ),
          boxShadow: [
            BoxShadow(
              color: themeColor.withOpacity(isDark ? 0.55 : 0.32),
              blurRadius: 14,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(isPlaying),
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skip icon button
// ─────────────────────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onTap, child: Icon(icon, color: color, size: size));
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress bar
// ─────────────────────────────────────────────────────────────────────────────

class _MiniProgressBar extends StatelessWidget {
  final AudioPlayerService audioPlayer;
  final Color themeColor;
  final bool isDark;

  const _MiniProgressBar({
    required this.audioPlayer,
    required this.themeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audioPlayer.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: audioPlayer.durationStream,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final ratio = dur.inMilliseconds > 0
                ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            return SizedBox(
              height: 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Track
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.12)
                                : Colors.black.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      // Fill
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: constraints.maxWidth * ratio,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(colors: [
                              themeColor.withOpacity(0.95),
                              themeColor.withOpacity(0.55),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated equalizer bars ("Now Playing" indicator)
// ─────────────────────────────────────────────────────────────────────────────

class _EqBars extends StatefulWidget {
  final Color color;
  const _EqBars({required this.color});

  @override
  State<_EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<_EqBars> with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = [];
  final List<Animation<double>> _anims = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 480 + i * 80),
      );
      final anim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
      );
      _ctrls.add(ctrl);
      _anims.add(anim);
      Future.delayed(Duration(milliseconds: i * 130), () {
        if (mounted) ctrl.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _anims[i],
            builder: (_, __) => Container(
              width: 3,
              height: 4 + (_anims[i].value * 7),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.85),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          );
        }),
      ),
    );
  }
}
