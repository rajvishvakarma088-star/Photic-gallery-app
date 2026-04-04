import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'glass_container.dart';
import 'services/music_service.dart';
import 'services/audio_player_service.dart';
import 'music_player_screen.dart';

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
  Widget _buildFallbackIcon() {
    return Center(
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withOpacity(0.9),
        size: 26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioPlayer = widget.audioPlayerService;
    
    return StreamBuilder<PlayerState>(
      stream: audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final currentMusic = audioPlayer.currentMusic;
        
        // Only show mini player if there's music playing
        if (currentMusic == null) {
          return const SizedBox.shrink();
        }

        final isPlaying = snapshot.data?.playing ?? false;
        final colorScheme = Theme.of(context).colorScheme;

        return ValueListenableBuilder<bool>(
          valueListenable: audioPlayer.isMiniPlayerVisible,
          builder: (context, isVisible, _) {
            if (!isVisible) return const SizedBox.shrink();

            return Dismissible(
              key: const ValueKey('mini_player_dismissible'),
              direction: DismissDirection.down,
              onDismissed: (_) {
                audioPlayer.isMiniPlayerVisible.value = false;
                audioPlayer.pause();
              },
              child: GestureDetector(
                onTap: widget.onTap,
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    height: 70,
                    child: Row(
                      children: [
                        // Album art with music color
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              colors: currentMusic.thumbnailGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Hero(
                              tag: 'music_art_${currentMusic.id}',
                              child: FutureBuilder<Uint8List?>(
                                future: currentMusic.getThumbnail(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                                    return Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                    );
                                  }
                                  
                                  if (currentMusic.hasAlbumArt) {
                                    if (currentMusic.albumArtBytes != null) {
                                      return Image.memory(
                                        currentMusic.albumArtBytes!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                                      );
                                    } else if (currentMusic.albumArtPath != null) {
                                      return Image.file(
                                        File(currentMusic.albumArtPath!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                                      );
                                    }
                                  }
                                  
                                  return _buildFallbackIcon();
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Song info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                currentMusic.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Now Playing',
                                style: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Play/Pause button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            if (isPlaying) {
                              audioPlayer.pause();
                            } else {
                              audioPlayer.play();
                            }
                          },
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: currentMusic.themeColor,
                            size: 26,
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
      },
    );
  }
}
