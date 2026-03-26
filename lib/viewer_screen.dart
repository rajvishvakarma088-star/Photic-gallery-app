import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'glass_container.dart';

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
  final ScrollController thumbnailScrollController = ScrollController();
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(0);
  final Map<String, AssetEntityImageProvider> providerCache = {};
  final Map<String, AssetEntityImageProvider> stripProviderCache = {};
  final Set<String> warmedViewerAssetIds = {};
  Timer? thumbnailStripTimer;
  bool isInteractingWithStrip = false;

  double verticalDrag = 0;
  double upwardDrag = 0;
  double detailsDrag = 0;
  bool showDetails = false;
  bool showThumbnailStrip = true;
  int currentIndex = 0;

  final PhotoViewController photoController = PhotoViewController();
  static const double detailsSheetHeight = 316;
  static const double thumbnailBarBottomOffset = 84;
  static const double thumbnailItemWidth = 56;
  static const double thumbnailSpacing = 8;

  double get dismissProgress =>
      (verticalDrag / 220).clamp(0.0, 1.0);

  AssetEntityImageProvider viewerImageProvider(AssetEntity asset) {
    return providerCache.putIfAbsent(asset.id, () {
      return AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize(1800, 1800),
        thumbnailFormat: ThumbnailFormat.jpeg,
      );
    });
  }

  AssetEntityImageProvider stripImageProvider(AssetEntity asset) {
    return stripProviderCache.putIfAbsent(asset.id, () {
      return AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize(240, 240),
        thumbnailFormat: ThumbnailFormat.jpeg,
      );
    });
  }

  void precacheViewerImage(int index) {
    if (index < 0 || index >= widget.images.length) return;
    final asset = widget.images[index];
    if (!warmedViewerAssetIds.add(asset.id)) return;

    precacheImage(
      viewerImageProvider(asset),
      context,
    );
  }

  void warmUpVisibleImages(int centerIndex) {
    for (int offset = -3; offset <= 3; offset++) {
      precacheViewerImage(centerIndex + offset);
    }
  }

  void syncThumbnailStrip([bool animated = true]) {
    if (!thumbnailScrollController.hasClients) return;

    final viewport = thumbnailScrollController.position.viewportDimension;
    final targetOffset =
        ((currentIndex * (thumbnailItemWidth + thumbnailSpacing)) -
                ((viewport - thumbnailItemWidth) / 2))
            .clamp(
      0.0,
      thumbnailScrollController.position.maxScrollExtent,
    ).toDouble();

    if (animated) {
      thumbnailScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      thumbnailScrollController.jumpTo(targetOffset);
    }
  }

  void openDetails() {
    thumbnailStripTimer?.cancel();
    setState(() {
      showDetails = true;
      verticalDrag = 0;
      upwardDrag = 0;
      detailsDrag = 0;
    });
  }

  void closeDetails() {
    setState(() {
      showDetails = false;
      upwardDrag = 0;
      detailsDrag = 0;
    });
    scheduleThumbnailStripHide();
  }

  void toggleThumbnailStrip() {
    setState(() {
      showThumbnailStrip = !showThumbnailStrip;
    });

    if (showThumbnailStrip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        syncThumbnailStrip(false);
      });
      scheduleThumbnailStripHide();
    } else {
      thumbnailStripTimer?.cancel();
    }
  }

  void showThumbnailStripTemporarily() {
    if (!showThumbnailStrip) {
      setState(() {
        showThumbnailStrip = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        syncThumbnailStrip(false);
      });
    } else {
      syncThumbnailStrip(false);
    }
    scheduleThumbnailStripHide();
  }

  void scheduleThumbnailStripHide() {
    thumbnailStripTimer?.cancel();
    if (showDetails || isInteractingWithStrip) return;

    thumbnailStripTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted || showDetails || isInteractingWithStrip) return;
      setState(() {
        showThumbnailStrip = false;
      });
    });
  }

  Future<void> animateToViewerPage(int index) async {
    if (!controller.hasClients || index == currentIndex) return;

    final distance = (index - currentIndex).abs();
    warmUpVisibleImages(index);

    if (distance >= 4) {
      controller.jumpToPage(index);
      return;
    }

    final duration = Duration(
      milliseconds: 160 + (distance * 55),
    );

    await controller.animateToPage(
      index,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  String formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day} ${months[date.month - 1]} ${date.year}  $hour:$minute $period';
  }

  @override
  void initState() {
    super.initState();
    currentIndex = widget.index;
    currentIndexNotifier.value = widget.index;
    controller = PageController(initialPage: widget.index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      warmUpVisibleImages(currentIndex);
      syncThumbnailStrip(false);
      scheduleThumbnailStripHide();
    });
  }

  @override
  void dispose() {
    thumbnailStripTimer?.cancel();
    photoController.dispose();
    thumbnailScrollController.dispose();
    currentIndexNotifier.dispose();
    providerCache.clear();
    stripProviderCache.clear();
    warmedViewerAssetIds.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            opacity: 1 - (dismissProgress * 0.55),
            child: AnimatedContainer(
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
          ),

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (showDetails) {
                closeDetails();
              }
            },
            child: Stack(
              children: [
                // 🖼️ IMAGE VIEW
                GestureDetector(
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      if (details.delta.dy < 0 && !showDetails) {
                        upwardDrag = (upwardDrag + (-details.delta.dy))
                            .clamp(0.0, 160.0);
                        return;
                      }

                      final newDrag = verticalDrag + details.delta.dy;
                      if (newDrag > 0 && !showDetails) {
                        verticalDrag =
                            (verticalDrag + (details.delta.dy * 0.72))
                                .clamp(0.0, 260.0);
                      }
                    });
                  },
                  onVerticalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;

                    if (verticalDrag > 150 || velocity > 700) {
                      Navigator.pop(context);
                    } else if (velocity < -140 || upwardDrag > 60) {
                      openDetails();
                    } else {
                      setState(() {
                        verticalDrag = 0;
                        upwardDrag = 0;
                      });
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      verticalDrag - (upwardDrag * 0.22),
                    ),
                    child: Transform.scale(
                      scale: 1 - (dismissProgress * 0.08),
                      child: Opacity(
                        opacity: 1 - (dismissProgress * 0.28),
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
                            currentIndex = index;
                            currentIndexNotifier.value = index;
                            warmUpVisibleImages(index);
                            showThumbnailStripTemporarily();
                            syncThumbnailStrip();
                          },
                          builder: (context, index) {
                            return PhotoViewGalleryPageOptions(
                              controller: photoController,
                              imageProvider:
                                  viewerImageProvider(widget.images[index]),
                              filterQuality: FilterQuality.medium,
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

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: thumbnailBarBottomOffset +
                      MediaQuery.of(context).padding.bottom,
                  child: IgnorePointer(
                    ignoring: showDetails,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      offset: showDetails
                          ? const Offset(0, 1.2)
                          : showThumbnailStrip
                              ? Offset.zero
                              : const Offset(0, 0.9),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: showDetails || !showThumbnailStrip ? 0 : 1,
                        child: ValueListenableBuilder<int>(
                          valueListenable: currentIndexNotifier,
                          builder: (context, _, __) {
                            return buildThumbnailStrip(isDark);
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  right: 12,
                  bottom: thumbnailBarBottomOffset +
                      MediaQuery.of(context).padding.bottom +
                      11,
                  child: IgnorePointer(
                    ignoring: showDetails,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: showDetails ? 0 : 1,
                      child: buildThumbnailStripToggle(isDark),
                    ),
                  ),
                ),

                // 📊 DETAILS PANEL
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ValueListenableBuilder<int>(
                    valueListenable: currentIndexNotifier,
                    builder: (context, index, _) {
                      return buildDetailsPanel(widget.images[index], isDark);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildThumbnailStrip(bool isDark) {
    final activeBorder = isDark
        ? const Color(0xFFD6CFFF)
        : const Color(0xFF6D5FD3);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 62,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification) {
                thumbnailStripTimer?.cancel();
                isInteractingWithStrip = true;
              } else if (notification is ScrollEndNotification) {
                isInteractingWithStrip = false;
                scheduleThumbnailStripHide();
              }
              return false;
            },
            child: ListView.separated(
              controller: thumbnailScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.images.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: thumbnailSpacing),
              itemBuilder: (context, index) {
                final asset = widget.images[index];
                final isSelected = index == currentIndex;

                return GestureDetector(
                  onTapDown: (_) {
                    thumbnailStripTimer?.cancel();
                    isInteractingWithStrip = true;
                  },
                  onTapCancel: () {
                    isInteractingWithStrip = false;
                    scheduleThumbnailStripHide();
                  },
                  onTap: () {
                    showThumbnailStripTemporarily();
                    animateToViewerPage(index);
                    isInteractingWithStrip = false;
                    scheduleThumbnailStripHide();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: thumbnailItemWidth,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected
                            ? activeBorder
                            : Colors.white.withOpacity(isDark ? 0.16 : 0.38),
                        width: isSelected ? 1.8 : 0.9,
                      ),
                      color: isSelected
                          ? activeBorder.withOpacity(isDark ? 0.12 : 0.08)
                          : Colors.black.withOpacity(isDark ? 0.12 : 0.04),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        scale: isSelected ? 1 : 0.92,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image(
                              image: stripImageProvider(asset),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                            if (isSelected)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.14),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                          ],
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
    );
  }

  Widget buildThumbnailStripToggle(bool isDark) {
    return GestureDetector(
      onTap: toggleThumbnailStrip,
      child: GlassContainer(
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Icon(
            showThumbnailStrip
                ? Icons.keyboard_arrow_right_rounded
                : Icons.keyboard_arrow_left_rounded,
            size: 22,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
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
    final accent = isDark
        ? const Color(0xFFB8AEFF)
        : const Color(0xFF7A6CE0);
    final panelColor = isDark
        ? Colors.white.withOpacity(0.09)
        : Colors.white.withOpacity(0.72);

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      offset: showDetails
          ? const Offset(0, 0)
          : const Offset(0, 1.08),
      child: Transform.translate(
        offset: Offset(0, detailsDrag),
        child: GestureDetector(
          onVerticalDragUpdate: (details) {
            setState(() {
              detailsDrag = (detailsDrag + details.delta.dy).clamp(0.0, 140.0);
            });
          },
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 140 || detailsDrag > 70) {
              closeDetails();
            } else {
              setState(() {
                detailsDrag = 0;
              });
            }
          },
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(34)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                constraints: BoxConstraints(
                  minHeight: 280,
                  maxHeight: detailsSheetHeight + bottomPadding,
                ),
                padding: EdgeInsets.fromLTRB(18, 14, 18, 12 + bottomPadding),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      panelColor,
                      isDark
                          ? const Color(0xFF7C6EE6).withOpacity(0.08)
                          : const Color(0xFFEAE5FF).withOpacity(0.35),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withOpacity(isDark ? 0.14 : 0.75),
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 52,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white38
                                : Colors.black26,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(isDark ? 0.16 : 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Photo Details',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Captured information and image metadata',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            onPressed: closeDetails,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      infoTile(
                        icon: Icons.image_outlined,
                        label: 'Name',
                        value: asset.title ?? 'Unknown',
                        isDark: isDark,
                        accent: accent,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: infoTile(
                              icon: Icons.aspect_ratio_rounded,
                              label: 'Resolution',
                              value: '${asset.width} x ${asset.height}',
                              isDark: isDark,
                              accent: accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: infoTile(
                              icon: Icons.photo_library_outlined,
                              label: 'Position',
                              value: '${currentIndex + 1}/${widget.images.length}',
                              isDark: isDark,
                              accent: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      infoTile(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: formatDate(asset.createDateTime),
                        isDark: isDark,
                        accent: accent,
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          'Swipe down to close',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget infoTile({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(isDark ? 0.1 : 0.68),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black45,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
