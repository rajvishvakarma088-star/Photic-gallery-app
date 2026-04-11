import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:photo_manager/photo_manager.dart';

import '../services/gallery_service.dart';
import '../services/music_service.dart';

Widget buildGalleryStatsChip({
  required IconData icon,
  required String label,
  required Color color,
  required Color textColor,
}) {
  return Container(
    key: ValueKey(label),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: textColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Widget buildPremiumListTileShell({
  required Widget child,
  required ColorScheme colorScheme,
  required bool isDark,
  required VoidCallback onTap,
  VoidCallback? onLongPress,
  bool isSelected = false,
  double scale = 1.0,
  EdgeInsetsGeometry padding = const EdgeInsets.all(12),
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(26)),
}) {
  final topColor = isDark
      ? const Color(0xFF1C1C1C)
      : const Color(0xFFFFFFFF);
  final midColor = isDark
      ? const Color(0xFF181818)
      : const Color(0xFFF9F9F9);
  final bottomColor = isDark
      ? const Color(0xFF131313)
      : const Color(0xFFF2F2F2);

  return RepaintBoundary(
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          scale: scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [topColor, midColor, bottomColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary.withValues(
                        alpha: isDark ? 0.34 : 0.22,
                      )
                    : Colors.white.withValues(
                        alpha: isDark ? 0.12 : 0.24,
                      ),
                width: isSelected ? 1.1 : 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
                if (isSelected)
                  BoxShadow(
                    color: colorScheme.primary.withValues(
                      alpha: isDark ? 0.18 : 0.1,
                    ),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: isDark ? 0.1 : 0.32),
                          Colors.white.withValues(alpha: 0),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.center,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: padding,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget buildFeaturedAlbumCard({
  required AlbumSummary album,
  required ColorScheme colorScheme,
  required bool isDark,
  required Widget Function(AssetEntity asset, {int thumbPx}) buildImage,
  required VoidCallback onTap,
}) {
  return RepaintBoundary(
    child: GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 176,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: album.coverAsset != null
                    ? buildImage(album.coverAsset!, thumbPx: 180)
                    : Container(color: colorScheme.surfaceContainerHigh),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: isDark ? 0.44 : 0.4),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${album.count} items',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
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
      ),
    ),
  );
}

Widget buildAlbumListTile({
  required AlbumSummary album,
  required ColorScheme colorScheme,
  required Widget Function(AssetEntity asset, {int thumbPx}) buildImage,
  required VoidCallback onTap,
}) {
  return buildPremiumListTileShell(
    colorScheme: colorScheme,
    isDark: colorScheme.brightness == Brightness.dark,
    onTap: onTap,
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 74,
            height: 74,
            child: album.coverAsset != null
                ? buildImage(album.coverAsset!, thumbPx: 120)
                : Container(color: colorScheme.surfaceContainerHighest),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                album.name,
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
                '${album.count} items',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    ),
  );
}

class MusicListItem extends StatelessWidget {
  final MusicFile music;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;

  const MusicListItem({
    Key? key,
    required this.music,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onPlayPause,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return buildPremiumListTileShell(
      colorScheme: colorScheme,
      isDark: isDark,
      onTap: onTap,
      isSelected: isCurrent,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 74,
              height: 74,
              child: Stack(
                children: [
                   Builder(
                    builder: (context) {
                      return FutureBuilder<Uint8List?>(
                        future: music.getThumbnail(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                            return Image.memory(snapshot.data!, fit: BoxFit.cover, width: 74, height: 74);
                          }
                          if (music.albumArtPath != null) {
                            return Image.file(
                              File(music.albumArtPath!),
                              fit: BoxFit.cover,
                              width: 74,
                              height: 74,
                              errorBuilder: (c, e, s) => _buildPlaceholder(colorScheme),
                            );
                          }
                          return _buildPlaceholder(colorScheme);
                        },
                      );
                    }
                  ),
                  if (isCurrent)
                    Container(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      child: Center(
                        child: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
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
            onTap: onPlayPause,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isCurrent
                    ? music.themeColor.withValues(alpha: 0.94)
                    : colorScheme.primaryContainer.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isCurrent && isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: isCurrent ? Colors.white : colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHigh,
      child: const Center(child: Icon(Icons.music_note_rounded, size: 32)),
    );
  }
}
