import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

class ViewerScreen extends StatefulWidget {
  final List<AssetEntity> images;
  final int index;

  const ViewerScreen({
    super.key,
    required this.images,
    required this.index,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late PageController controller;

  double verticalDrag = 0;
  bool showDetails = false;
  int currentIndex = 0;

  final PhotoViewController photoController = PhotoViewController();

  @override
  void initState() {
    super.initState();
    currentIndex = widget.index;
    controller = PageController(initialPage: widget.index);
  }

  @override
  void dispose() {
    photoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = widget.images[currentIndex];

    // 🔥 FIX SYSTEM UI (NO BLACK BARS)
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor:
            isDark ? Colors.black : Colors.white,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,

      body: Stack(
        children: [
          // 🌈 BACKGROUND GRADIENT
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        const Color(0xFF0F2027),
                        const Color(0xFF203A43),
                        const Color(0xFF2C5364),
                      ]
                    : [
                        const Color(0xFFfdfbfb),
                        const Color(0xFFebedee),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (showDetails) {
                setState(() => showDetails = false);
              }
            },
            child: Stack(
              children: [
                // 🖼️ IMAGE VIEW
                GestureDetector(
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      final newDrag = verticalDrag + details.delta.dy;
                      if (newDrag > 0) {
                        verticalDrag = newDrag * 0.9;
                      }
                    });
                  },
                  onVerticalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;

                    if (verticalDrag > 120 || velocity > 300) {
                      Navigator.pop(context);
                    } else if (velocity < -300) {
                      setState(() {
                        showDetails = true;
                        verticalDrag = 0;
                      });
                    } else {
                      setState(() {
                        verticalDrag = 0;
                      });
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(0, verticalDrag),
                    child: Transform.scale(
                      scale:
                          (1 - (verticalDrag / 900)).clamp(0.92, 1.0),
                      child: Opacity(
                        opacity:
                            (1 - (verticalDrag / 300)).clamp(0.0, 1.0),
                        child: PhotoViewGallery.builder(
                          pageController: controller,
                          itemCount: widget.images.length,
                          backgroundDecoration: BoxDecoration(
                            gradient: isDark
                                ? const LinearGradient(
                                    colors: [Colors.black, Colors.black],
                                  )
                                : const LinearGradient(
                                    colors: [
                                      Colors.white,
                                      Color(0xFFF2F2F2),
                                    ],
                                  ),
                          ),
                          onPageChanged: (index) {
                            setState(() {
                              currentIndex = index;
                            });
                          },
                          builder: (context, index) {
                            return PhotoViewGalleryPageOptions(
                              controller: photoController,
                              imageProvider: AssetEntityImageProvider(
                                widget.images[index],
                                isOriginal: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // 🔙 BACK BUTTON
                Positioned(
                  top: 50,
                  left: 20,
                  child: glassButton(
                    icon: Icons.arrow_back,
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                ),

                // 📊 DETAILS PANEL
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  bottom: showDetails ? 0 : -300,
                  left: 0,
                  right: 0,
                  child: buildDetailsPanel(asset, isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🧊 GLASS BUTTON
  Widget glassButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: IconButton(
            icon: Icon(
              icon,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: onTap,
          ),
        ),
      ),
    );
  }

  // 📊 DETAILS PANEL
  Widget buildDetailsPanel(AssetEntity asset, bool isDark) {
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(25)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 260,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white54
                        : Colors.black38,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text(
                "Details",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              infoRow("Name", asset.title ?? "Unknown", isDark),
              infoRow(
                  "Resolution",
                  "${asset.width} x ${asset.height}",
                  isDark),
              infoRow(
                  "Date",
                  asset.createDateTime.toString(),
                  isDark),
              const Spacer(),
              Center(
                child: IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color:
                        isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: () {
                    setState(() {
                      showDetails = false;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🧾 INFO ROW
  Widget infoRow(String title, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(
                  color: isDark
                      ? Colors.white70
                      : Colors.black54)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                  color:
                      isDark ? Colors.white : Colors.black),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
