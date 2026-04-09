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
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 1.0, end: isSelected ? 0.92 : 1.0),
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Stack(
              fit: StackFit.expand,
              children: [
                imageChild,
                if (isSelected)
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutBack,
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      builder: (context, opacity, child) {
                        final colorScheme = Theme.of(context).colorScheme;
                        final borderColor =
                            colorScheme.primary.withValues(alpha: 0.92);
                        final fillColor =
                            colorScheme.primary.withValues(alpha: 0.18);
                        return Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: fillColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: borderColor,
                                width: 2,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Transform.scale(
                                  scale: opacity,
                                  child: Icon(
                                    Icons.check_circle,
                                    color: borderColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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
                if (asset.type == AssetType.video)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.42),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 0.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
