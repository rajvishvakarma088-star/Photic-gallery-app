import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
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

  List<AssetEntity> images = [];
  Set<String> favorites = {};
  Set<String> animating = {};

  @override
  void initState() {
    super.initState();
    loadImages();
  }

  void loadImages() async {
    final data = await service.fetchImages(0);
    setState(() => images = data);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,

      appBar: AppBar(
        title: const Text("Gallery"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              context.read<ThemeProvider>().toggleTheme();
            },
          )
        ],
      ),

      body: Stack(
        children: [
          // 🌈 GRADIENT
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [Colors.black, Colors.grey.shade900]
                    : [Colors.white, Colors.grey.shade200],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // 🖼️ GRID
          GridView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: images.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
            ),
            itemBuilder: (context, index) {
              return FutureBuilder<Uint8List?>(
                future: images[index].thumbnailDataWithSize(
                    const ThumbnailSize(200, 200)),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Container(color: Colors.grey[900]);
                  }

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

                    onDoubleTap: () {
                      final id = images[index].id;

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
                      children: [
                        Hero(
                          tag: images[index].id,
                          child: Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          ),
                        ),

                        if (favorites.contains(images[index].id))
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(Icons.favorite,
                                color: Colors.red),
                          ),

                        if (animating.contains(images[index].id))
                          const Center(
                            child: Icon(Icons.favorite,
                                color: Colors.white, size: 60),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}