import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../glass_container.dart';
import '../services/gallery_service.dart';

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

Widget buildFeaturedAlbumCard({
  required AlbumSummary album,
  required ColorScheme colorScheme,
  required bool isDark,
  required Widget Function(AssetEntity asset, {int thumbPx}) buildImage,
  required VoidCallback onTap,
}) {
  return GestureDetector(
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
                    Colors.black.withOpacity(isDark ? 0.44 : 0.4),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Featured',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${album.count} photos',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.86),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
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
  return GestureDetector(
    onTap: onTap,
    child: GlassContainer(
      borderRadius: BorderRadius.circular(26),
      enableBlur: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 74,
                height: 74,
                child: album.coverAsset != null
                    ? buildImage(album.coverAsset!, thumbPx: 96)
                    : Container(color: colorScheme.surfaceContainerHigh),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
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
                    '${album.count} images',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.68),
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
                color: colorScheme.primaryContainer.withOpacity(0.92),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
