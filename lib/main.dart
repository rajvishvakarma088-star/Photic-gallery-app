import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:ui';
import 'package:photo_manager/photo_manager.dart';
import 'services/gallery_service.dart';
import 'viewer_screen.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: theme.isDark ? ThemeMode.dark : ThemeMode.light,

      // 🔥 Smooth transition
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android:
                FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),

      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),

      home: const GalleryScreen(),
    );
  }
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final GalleryService service = GalleryService();

  List<AssetEntity> images = [];

  Set<String> favorites = {};
  Set<String> animatingFavorites = {};

  Map<String, Uint8List?> thumbnailCache = {}; // 🔥 CACHE

  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    loadImages();
  }

  void loadImages() async {
    final data = await service.fetchImages(0);
    setState(() {
      images = data;
    });
  }

  // 🔥 IMAGE CACHE BUILDER
  Widget buildImage(AssetEntity asset, bool isDark) {
    if (thumbnailCache.containsKey(asset.id)) {
      return Image.memory(
        thumbnailCache[asset.id]!,
        fit: BoxFit.cover,
      );
    }

    asset
        .thumbnailDataWithSize(const ThumbnailSize(200, 200))
        .then((data) {
      if (mounted) {
        setState(() {
          thumbnailCache[asset.id] = data;
        });
      }
    });

    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[300],
    );
  }

  // 🖼️ GALLERY
  Widget buildGallery() {
    final isDark = context.watch<ThemeProvider>().isDark;

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: images.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
      ),
      itemBuilder: (context, index) {
        final asset = images[index];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ViewerScreen(
                  images: images,
                  index: index,
                ),
              ),
            );
          },

          // ❤️ FAVORITE
          onDoubleTap: () {
            final id = asset.id;

            setState(() {
              if (favorites.contains(id)) {
                favorites.remove(id);
              } else {
                favorites.add(id);
                animatingFavorites.add(id);
              }
            });

            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  animatingFavorites.remove(id);
                });
              }
            });
          },

          child: Stack(
            children: [
              buildImage(asset, isDark),

              if (favorites.contains(asset.id))
                const Positioned(
                  top: 8,
                  right: 8,
                  child:
                      Icon(Icons.favorite, color: Colors.red),
                ),

              if (animatingFavorites.contains(asset.id))
                const Center(
                  child: Icon(
                    Icons.favorite,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ❤️ FAVORITES
  Widget buildFavorites() {
    final isDark = context.watch<ThemeProvider>().isDark;

    final favImages =
        images.where((e) => favorites.contains(e.id)).toList();

    if (favImages.isEmpty) {
      return Center(
        child: Text(
          "No Favorites",
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: favImages.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
      ),
      itemBuilder: (context, index) {
        return buildImage(favImages[index], isDark);
      },
    );
  }

  Widget getScreen() {
    return selectedIndex == 0
        ? buildGallery()
        : buildFavorites();
  }

  // 🧊 NAVBAR
  Widget buildNavbar() {
    final isDark = context.watch<ThemeProvider>().isDark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceAround,
            children: [
              navItem(Icons.photo, 0, isDark),
              navItem(Icons.favorite, 1, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget navItem(IconData icon, int index, bool isDark) {
    final isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedIndex = index;
        });
      },
      child: Icon(
        icon,
        color: isSelected
            ? (isDark ? Colors.white : Colors.black)
            : (isDark ? Colors.white70 : Colors.black54),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Gallery"),
        backgroundColor:
            isDark ? Colors.black : Colors.white,
        foregroundColor:
            isDark ? Colors.white : Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.brightness_6,
                color: isDark ? Colors.white : Colors.black),
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme();
            },
          ),
        ],
      ),

      body: Stack(
        children: [
          // 🔥 DYNAMIC GRADIENT
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        Colors.black,
                        Colors.grey.shade900,
                      ]
                    : [
                        Colors.white,
                        Colors.grey.shade200,
                      ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          getScreen(),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: buildNavbar(),
          ),
        ],
      ),
    );
  }
}