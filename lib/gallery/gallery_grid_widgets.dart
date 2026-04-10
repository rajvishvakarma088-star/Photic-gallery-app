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
              color: colorScheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (colorScheme.brightness == Brightness.dark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          child: Text(
            section.title,
            style: TextStyle(
              color: colorScheme.brightness == Brightness.dark 
                  ? colorScheme.onSurface 
                  : const Color(0xFF1A1A1A),
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
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
    child: TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutQuart,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Transform.scale(
              scale: 0.85 + (0.15 * value),
              child: child,
            ),
          ),
        );
      },
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
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.04),
                      width: 1,
                    ),
                  ),
                  child: imageChild,
                ),
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
  ),
);
}
