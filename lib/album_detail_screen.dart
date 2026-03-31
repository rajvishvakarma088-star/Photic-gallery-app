import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'glass_container.dart';
import 'theme_provider.dart';
import 'viewer_screen.dart';

class AlbumDetailScreen extends StatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.title,
    required this.images,
  });

  final String title;
  final List<AssetEntity> images;

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  static const double pinchStepOutThreshold = 1.08;
  static const double pinchStepInThreshold = 0.92;
  static const int pinchStepCooldownMs = 55;
  final Map<String, AssetEntityImageProvider> thumbnailProviderCache = {};
  int albumGridCount = 3;
  double _lastPinchScale = 1.0;
  double _pinchAccumulator = 1.0;
  int _activePointers = 0;
  DateTime _lastGridStepAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pinchStepConsumed = false;

  bool get _isPinching => _activePointers >= 2;

  int get albumThumbPx {
    return 180;
  }

  Route<T> buildCinematicRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => page,
    );
  }

  Widget buildImage(AssetEntity asset) {
    return buildImageWithSize(asset, albumThumbPx);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final topBarColor =
        isDark ? const Color(0xFF120C24) : const Color(0xFFF1E8FF);

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            widget.title,
            key: ValueKey(widget.title),
          ),
        ),
        backgroundColor: topBarColor,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle.copyWith(
          statusBarColor: topBarColor,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [
                        Color(0xFF120C24),
                        Color(0xFF1E163A),
                        Color(0xFF2C1F52),
                      ]
                    : const [
                        Color(0xFFF0E5FF),
                        Color(0xFFE4D3FF),
                        Color(0xFFD5BDFF),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -70,
            right: -30,
            child: IgnorePointer(
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFA855F7).withOpacity(
                    isDark ? 0.18 : 0.24,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
            child: GlassContainer(
              borderRadius: BorderRadius.circular(30),
              child: Listener(
                onPointerDown: (_) {
                  final wasPinching = _isPinching;
                  _activePointers++;
                  if (!wasPinching && _isPinching) {
                    setState(() {});
                  }
                },
                onPointerUp: (_) {
                  final wasPinching = _isPinching;
                  _activePointers = (_activePointers - 1).clamp(0, 20);
                  if (wasPinching && !_isPinching) {
                    setState(() {});
                  }
                },
                onPointerCancel: (_) {
                  final wasPinching = _isPinching;
                  _activePointers = (_activePointers - 1).clamp(0, 20);
                  if (wasPinching && !_isPinching) {
                    setState(() {});
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (details) {
                    _lastPinchScale = 1.0;
                    _pinchAccumulator = 1.0;
                    _pinchStepConsumed = false;
                  },
                  onScaleUpdate: (details) {
                    if (_pinchStepConsumed) return;
                    if (!_isPinching) {
                      _lastPinchScale = details.scale;
                      return;
                    }

                    final factor = details.scale / _lastPinchScale;
                    _lastPinchScale = details.scale;
                    if (!factor.isFinite || factor <= 0) return;

                    _pinchAccumulator *= factor;
                    int nextCount = albumGridCount;
                    var updatedAccumulator = _pinchAccumulator;

                    if (updatedAccumulator >= pinchStepOutThreshold &&
                        nextCount > 2) {
                      nextCount--;
                      updatedAccumulator /= pinchStepOutThreshold;
                    } else if (updatedAccumulator <= pinchStepInThreshold &&
                        nextCount < 6) {
                      nextCount++;
                      updatedAccumulator /= pinchStepInThreshold;
                    }

                    _pinchAccumulator =
                        updatedAccumulator.clamp(0.75, 1.25).toDouble();
                    if (nextCount == albumGridCount) return;

                    final now = DateTime.now();
                    if (now.difference(_lastGridStepAt).inMilliseconds <
                        pinchStepCooldownMs) {
                      return;
                    }

                    setState(() {
                      albumGridCount = nextCount;
                      _lastGridStepAt = now;
                    });
                    _pinchStepConsumed = true;
                  },
                  onScaleEnd: (details) {
                    _lastPinchScale = 1.0;
                    _pinchAccumulator = 1.0;
                    _pinchStepConsumed = false;
                  },
                  child: GridView.builder(
                    key: ValueKey('album-grid-$albumGridCount'),
                    padding: const EdgeInsets.all(10),
                    cacheExtent: 800,
                    itemCount: widget.images.length,
                    physics: _isPinching
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: albumGridCount,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final asset = widget.images[index];
                      final ImageProvider<Object> previewProvider =
                          thumbnailProviderCache.putIfAbsent(
                        '${asset.id}@$albumThumbPx',
                        () => AssetEntityImageProvider(
                          asset,
                          isOriginal: false,
                          thumbnailSize: ThumbnailSize.square(albumThumbPx),
                          thumbnailFormat: ThumbnailFormat.jpeg,
                        ),
                      );
                      return _AlbumReveal(
                        order: index,
                        child: RepaintBoundary(
                          child: GestureDetector(
                            onTap: () {
                              final openingProvider =
                                  ViewerScreen.openingImageProvider(
                                    context,
                                    asset,
                                  );
                              unawaited(precacheImage(openingProvider, context));
                              Navigator.push(
                                context,
                                buildCinematicRoute(
                                  ViewerScreen(
                                    images: widget.images,
                                    index: index,
                                    initialPreviewProvider: previewProvider,
                                    initialViewerProvider: openingProvider,
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Hero(
                                tag: asset.id,
                                child: buildImageWithSize(asset, albumThumbPx),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildImageWithSize(AssetEntity asset, int size) {
    final id = '${asset.id}@$size';
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surfaceContainerHighest,
            colorScheme.surfaceContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );

    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      return placeholder;
    }

    final provider = thumbnailProviderCache.putIfAbsent(
      id,
      () => AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: ThumbnailSize.square(size),
        thumbnailFormat: ThumbnailFormat.jpeg,
      ),
    );

    return Image(
      image: provider,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return placeholder;
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}

class _AlbumReveal extends StatelessWidget {
  const _AlbumReveal({
    required this.order,
    required this.child,
  });

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = order.clamp(0, 10).toInt() * 24;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 340 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, builtChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: Transform.scale(
              scale: 0.99 + (value * 0.01),
              child: builtChild,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
