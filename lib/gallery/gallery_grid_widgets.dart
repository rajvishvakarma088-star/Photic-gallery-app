import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'gallery_section.dart';

Widget buildGallerySectionHeader(
  GallerySection section,
  ColorScheme colorScheme,
  bool isFirstSection,
) {
  return Padding(
    padding: EdgeInsets.fromLTRB(4, isFirstSection ? 0 : 14, 4, 4),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.22),
            ),
          ),
          child: Text(
            section.title,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withOpacity(0.56),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${section.items.length}',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withOpacity(0.16),
                  colorScheme.primary.withOpacity(0.02),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget buildGalleryGridTile({
  required AssetEntity asset,
  required Widget image,
  required VoidCallback onTap,
  required VoidCallback onDoubleTap,
  VoidCallback? onLongPress,
  GestureLongPressStartCallback? onLongPressStart,
  GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate,
  GestureLongPressEndCallback? onLongPressEnd,
  required bool isFavorite,
  required bool isAnimating,
  bool isSelected = false,
  Object? heroTag,
  Key? tileKey,
}) {
  final imageChild = ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: heroTag == null
        ? image
        : Hero(
            tag: heroTag,
            child: image,
          ),
  );

  return RepaintBoundary(
    child: GestureDetector(
      key: tileKey,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressEnd: onLongPressEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageChild,
          if (isSelected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                ),
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (isFavorite)
            const Positioned(
              top: 8,
              right: 8,
              child: Icon(
                Icons.favorite,
                color: Colors.red,
              ),
            ),
          if (isAnimating)
            const Center(
              child: Icon(
                Icons.favorite,
                color: Colors.white,
                size: 60,
              ),
            ),
        ],
      ),
    ),
  );
}
