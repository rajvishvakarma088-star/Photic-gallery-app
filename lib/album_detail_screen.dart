import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
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
  final Map<String, Uint8List?> thumbnailCache = {};
  final Map<String, ValueNotifier<Uint8List?>> thumbnailNotifiers = {};
  final Set<String> loadingThumbs = {};

  @override
  void dispose() {
    for (final notifier in thumbnailNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  Route<T> buildCinematicRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.035, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget buildImage(AssetEntity asset) {
    final id = asset.id;
    thumbnailNotifiers.putIfAbsent(id, () => ValueNotifier(null));

    final cached = thumbnailCache[id];
    if (cached != null) {
      return Image.memory(
        cached,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    if (!loadingThumbs.contains(id)) {
      loadingThumbs.add(id);
      asset
          .thumbnailDataWithSize(const ThumbnailSize(320, 320))
          .then((data) {
        if (!mounted) return;
        if (data != null) {
          thumbnailCache[id] = data;
          thumbnailNotifiers[id]!.value = data;
        }
      }).whenComplete(() {
        loadingThumbs.remove(id);
      });
    }

    return ValueListenableBuilder<Uint8List?>(
      valueListenable: thumbnailNotifiers[id]!,
      builder: (context, value, child) {
        if (value != null) {
          return Image.memory(
            value,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }

        final colorScheme = Theme.of(context).colorScheme;
        return DecoratedBox(
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final topBarColor =
        isDark ? const Color(0xFF120C24) : const Color(0xFFF7F4FF);

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
                        Color(0xFFF7F4FF),
                        Color(0xFFEDE5FF),
                        Color(0xFFE3D5FF),
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
                    isDark ? 0.18 : 0.15,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
            child: GlassContainer(
              borderRadius: BorderRadius.circular(30),
              child: GridView.builder(
                padding: const EdgeInsets.all(10),
                cacheExtent: 1200,
                itemCount: widget.images.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final asset = widget.images[index];
                  return _AlbumReveal(
                    order: index,
                    child: RepaintBoundary(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            buildCinematicRoute(
                              ViewerScreen(
                                images: widget.images,
                                index: index,
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Hero(
                            tag: asset.id,
                            child: buildImage(asset),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
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
