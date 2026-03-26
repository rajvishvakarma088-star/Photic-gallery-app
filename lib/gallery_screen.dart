import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'services/gallery_service.dart';
import 'viewer_screen.dart';
import 'theme_provider.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final GalleryService service = GalleryService();
  final ScrollController scrollController = ScrollController();

  List<AssetEntity> images = [];
  final Set<String> favorites = {};
  final Set<String> animating = {};

  final Map<String, Uint8List?> thumbnailCache = {};
  final Map<String, ValueNotifier<Uint8List?>> thumbnailNotifiers = {};
  final Set<String> loadingThumbs = {};

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  int currentPage = 0;
  int selectedIndex = 0;
  static const int pageSize = 120;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(onScroll);
    loadImages();
  }

  @override
  void dispose() {
    scrollController.dispose();
    for (final notifier in thumbnailNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  Future<void> loadImages({bool loadMore = false}) async {
    if (loadMore) {
      if (isLoadingMore || isLoading || !hasMore || selectedIndex != 0) {
        return;
      }
      setState(() => isLoadingMore = true);
    } else {
      setState(() => isLoading = true);
      currentPage = 0;
      hasMore = true;
    }

    final nextPage = loadMore ? currentPage + 1 : 0;
    final data = await service.fetchImages(
      page: nextPage,
      size: pageSize,
    );

    if (!mounted) return;

    setState(() {
      if (loadMore) {
        images.addAll(data);
        isLoadingMore = false;
        currentPage = nextPage;
        hasMore = data.length == pageSize;
      } else {
        images = data;
        isLoading = false;
        currentPage = data.isEmpty ? 0 : nextPage;
        hasMore = data.length == pageSize;
      }
    });
  }

  void onScroll() {
    if (!scrollController.hasClients || isLoading || isLoadingMore) return;

    final position = scrollController.position;
    if (position.pixels > position.maxScrollExtent - 800) {
      loadImages(loadMore: true);
    }
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
          .thumbnailDataWithSize(
            const ThumbnailSize(320, 320),
          )
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
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.surfaceContainerHighest,
                Theme.of(context).colorScheme.surfaceContainer,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      },
    );
  }

  Widget buildBottomBar(BuildContext context, bool isDark) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      backgroundColor: isDark
          ? const Color(0xFF101916).withOpacity(0.96)
          : const Color(0xFFF5F6F0).withOpacity(0.96),
      onDestinationSelected: (index) {
        if (index == selectedIndex) return;
        setState(() => selectedIndex = index);
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.photo_library_outlined),
          selectedIcon: const Icon(Icons.photo_library),
          label: 'Gallery',
        ),
        NavigationDestination(
          icon: Badge.count(
            count: favorites.length,
            isLabelVisible: favorites.isNotEmpty,
            child: const Icon(Icons.favorite_border),
          ),
          selectedIcon: const Icon(Icons.favorite),
          label: 'Favorites',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark(context);
    final colorScheme = Theme.of(context).colorScheme;
    final topBarColor =
        isDark ? const Color(0xFF07110E) : const Color(0xFFFCFCF7);
    final visibleImages = selectedIndex == 0
        ? images
        : images
            .where((asset) => favorites.contains(asset.id))
            .toList(growable: false);

    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      appBar: AppBar(
        title: const Text("Gallery"),
        backgroundColor: topBarColor,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle.copyWith(
          statusBarColor: topBarColor,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor:
              isDark ? const Color(0xFF101916) : const Color(0xFFF5F6F0),
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Light mode' : 'Dark mode',
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme();
            },
          )
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [
                        Color(0xFF07110E),
                        Color(0xFF11221D),
                        Color(0xFF1B3028),
                      ]
                    : const [
                        Color(0xFFFCFCF7),
                        Color(0xFFEFF2E8),
                        Color(0xFFDDE7DA),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (visibleImages.isEmpty)
            Center(
              child: Text(
                selectedIndex == 0
                    ? 'No images found'
                    : 'No favorite images yet',
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.8),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            GridView.builder(
              controller: scrollController,
              cacheExtent: 1200,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 110),
              itemCount: visibleImages.length + (isLoadingMore ? 3 : 0),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                if (index >= visibleImages.length) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colorScheme.primary,
                      ),
                    ),
                  );
                }

                final asset = visibleImages[index];

                return RepaintBoundary(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ViewerScreen(
                            images: visibleImages,
                            index: index,
                          ),
                        ),
                      );
                    },
                    onDoubleTap: () {
                      final id = asset.id;

                      setState(() {
                        if (favorites.contains(id)) {
                          favorites.remove(id);
                        } else {
                          favorites.add(id);
                          animating.add(id);
                        }
                      });

                      Future.delayed(
                          const Duration(milliseconds: 500), () {
                        if (mounted) {
                          setState(() {
                            animating.remove(id);
                          });
                        }
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Hero(
                            tag: asset.id,
                            child: buildImage(asset),
                          ),
                        ),
                        if (favorites.contains(asset.id))
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(Icons.favorite,
                                color: Colors.red),
                          ),
                        if (animating.contains(asset.id))
                          const Center(
                            child: Icon(Icons.favorite,
                                color: Colors.white, size: 60),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: buildBottomBar(context, isDark),
        ),
      ),
    );
  }
}
