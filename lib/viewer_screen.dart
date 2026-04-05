import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import 'package:path_provider/path_provider.dart';
import 'glass_container.dart';
import 'services/recycle_bin_database.dart';
import 'services/vault_service.dart';

class ViewerScreen extends StatefulWidget {
  final List<AssetEntity> images;
  final int index;
  final ImageProvider? initialPreviewProvider;
  final AssetEntityImageProvider? initialViewerProvider;

  const ViewerScreen({
    super.key,
    required this.images,
    required this.index,
    this.initialPreviewProvider,
    this.initialViewerProvider,
  });

  static ThumbnailSize openingThumbnailSize(BuildContext context) {
    return const ThumbnailSize.square(320);
  }

  static AssetEntityImageProvider openingImageProvider(
    BuildContext context,
    AssetEntity asset,
  ) {
    return AssetEntityImageProvider(
      asset,
      isOriginal: false,
      thumbnailSize: const ThumbnailSize.square(800),
      thumbnailFormat: ThumbnailFormat.jpeg,
    );
  }

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final RecycleBinDatabase recycleBinDatabase = RecycleBinDatabase.instance;
  final VaultService vaultService = VaultService.instance;
  late PageController controller;
  final ScrollController thumbnailScrollController = ScrollController();
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> verticalDragNotifier = ValueNotifier<double>(0);
  final ValueNotifier<double> upwardDragNotifier = ValueNotifier<double>(0);
  final Map<String, AssetEntityImageProvider> providerCache = {};
  final Map<String, AssetEntityImageProvider> stripProviderCache = {};
  final Map<String, Future<String>> fileSizeLabelCache = {};
  final Set<String> warmedViewerAssetIds = {};
  final Set<String> highQualityReadyAssetIds = {};
  Timer? thumbnailStripTimer;
  Timer? deferredNeighborWarmupTimer;
  Timer? _swipeDebounceTimer;
  bool isInteractingWithStrip = false;
  bool _editCompleted = false;
  bool _swipeJustHappened = false; // prevents tap-after-swipe chrome flash
  AssetEntity? _newAssetPostEdit;

  double detailsDrag = 0;
  bool showDetails = false;
  bool showThumbnailStrip = true;
  bool isDeletingToRecycleBin = false;
  bool showViewerChrome = true;
  int currentIndex = 0;
  Brightness? _lastAppliedBrightness;

  final PhotoViewController photoController = PhotoViewController();
  static const double detailsSheetHeight = 316;
  static const double thumbnailItemWidth = 52;
  static const double thumbnailSpacing = 8;

  double get dismissProgress =>
      (verticalDragNotifier.value / 220).clamp(0.0, 1.0);

  ImageProvider currentPageImageProvider(AssetEntity asset, int index) {
    final previewProvider = widget.initialPreviewProvider;
    final isInitialPage = index == widget.index;
    final isPreviewStillNeeded =
        isInitialPage &&
        previewProvider != null &&
        !highQualityReadyAssetIds.contains(asset.id);

    if (isPreviewStillNeeded) {
      return previewProvider;
    }

    return viewerImageProvider(asset);
  }

  AssetEntityImageProvider viewerImageProvider(AssetEntity asset) {
    return providerCache.putIfAbsent(asset.id, () {
      return AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize(800, 800),
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

    precacheImage(viewerImageProvider(asset), context).then((_) {
      if (!mounted) return;
      if (highQualityReadyAssetIds.add(asset.id)) {
        setState(() {});
      }
    });
  }

  void warmUpVisibleImages(int centerIndex) {
    for (int offset = -1; offset <= 1; offset++) {
      precacheViewerImage(centerIndex + offset);
    }
  }

  void warmCurrentThenNeighbors(int centerIndex) {
    precacheViewerImage(centerIndex);
    deferredNeighborWarmupTimer?.cancel();
    deferredNeighborWarmupTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      precacheViewerImage(centerIndex - 1);
      precacheViewerImage(centerIndex + 1);
    });
  }

  void syncThumbnailStrip([bool animated = true]) {
    if (!thumbnailScrollController.hasClients) return;

    final viewport = thumbnailScrollController.position.viewportDimension;

    // Calculate max extent manually to avoid ListView layout thrashing on large galleries.
    final itemsCount = widget.images.length;
    final totalWidth =
        (itemsCount * thumbnailItemWidth) +
        ((itemsCount > 0 ? itemsCount - 1 : 0) * thumbnailSpacing) +
        20.0;
    final calculatedMaxExtent = (totalWidth - viewport).clamp(
      0.0,
      double.infinity,
    );

    final targetOffset =
        ((currentIndex * (thumbnailItemWidth + thumbnailSpacing)) -
                ((viewport - thumbnailItemWidth) / 2))
            .clamp(0.0, calculatedMaxExtent)
            .toDouble();

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
    verticalDragNotifier.value = 0;
    upwardDragNotifier.value = 0;
    setState(() {
      showDetails = true;
      showViewerChrome = true;
      detailsDrag = 0;
    });
  }

  void closeDetails() {
    setState(() {
      showDetails = false;
      detailsDrag = 0;
    });
    upwardDragNotifier.value = 0;
    scheduleThumbnailStripHide();
  }

  void _applySystemUiStyle(Brightness brightness) {
    if (_lastAppliedBrightness == brightness) return;
    _lastAppliedBrightness = brightness;

    final isDark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: isDark
            ? Colors.black
            : const Color(0xFFF0E6FF),
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
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

    warmCurrentThenNeighbors(index);
    controller.jumpToPage(index);
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

  Future<String> fileSizeLabel(AssetEntity asset) {
    return fileSizeLabelCache.putIfAbsent(asset.id, () async {
      final File? file = await asset.file;
      if (file == null) return 'Unavailable';

      final bytes = await file.length();
      final mb = bytes / (1024 * 1024);

      if (mb >= 100) return '${mb.toStringAsFixed(0)} MB';
      if (mb >= 10) return '${mb.toStringAsFixed(1)} MB';
      return '${mb.toStringAsFixed(2)} MB';
    });
  }

  @override
  void initState() {
    super.initState();
    currentIndex = widget.index;
    currentIndexNotifier.value = widget.index;
    controller = PageController(initialPage: widget.index);
    final initialViewerProvider = widget.initialViewerProvider;
    if (initialViewerProvider != null) {
      providerCache[widget.images[widget.index].id] = initialViewerProvider;
    }
    scheduleMicrotask(() {
      if (!mounted) return;
      precacheViewerImage(currentIndex);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      deferredNeighborWarmupTimer?.cancel();
      deferredNeighborWarmupTimer = Timer(const Duration(milliseconds: 90), () {
        if (!mounted) return;
        precacheViewerImage(currentIndex - 1);
        precacheViewerImage(currentIndex + 1);
      });
      syncThumbnailStrip(false);
      scheduleThumbnailStripHide();
    });
  }

  @override
  void dispose() {
    thumbnailStripTimer?.cancel();
    deferredNeighborWarmupTimer?.cancel();
    photoController.dispose();
    thumbnailScrollController.dispose();
    currentIndexNotifier.dispose();
    verticalDragNotifier.dispose();
    _swipeDebounceTimer?.cancel();
    upwardDragNotifier.dispose();
    providerCache.clear();
    stripProviderCache.clear();
    fileSizeLabelCache.clear();
    warmedViewerAssetIds.clear();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _applySystemUiStyle(Theme.of(context).brightness);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final res = _newAssetPostEdit ?? (_editCompleted ? 'edited' : null);
        Navigator.pop(context, res);
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,

      body: Stack(
        children: [
          // 🌈 DYNAMIC BACKGROUND
          ValueListenableBuilder<double>(
            valueListenable: verticalDragNotifier,
            builder: (context, verticalDrag, _) {
              final dismissProgress = (verticalDrag / 220).clamp(0.0, 1.0);
              return Container(
                color: (isDark ? Colors.black : Colors.white).withOpacity(
                  (1.0 - dismissProgress).clamp(0.0, 1.0),
                ),
              );
            },
          ),

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              // Ignore taps that are actually swipe-ends
              if (_swipeJustHappened) return;
              if (showDetails) {
                closeDetails();
              } else {
                setState(() {
                  showViewerChrome = !showViewerChrome;
                });
              }
            },
            child: Stack(
              children: [
                // 🖼️ IMAGE VIEW
                GestureDetector(
                  onLongPress: () => showContextMenu(isDark),
                  onVerticalDragUpdate: (details) {
                    if (details.delta.dy < 0 && !showDetails) {
                      upwardDragNotifier.value =
                          (upwardDragNotifier.value + (-details.delta.dy))
                              .clamp(0.0, 160.0);
                      return;
                    }

                    final newDrag =
                        verticalDragNotifier.value + details.delta.dy;
                    if (newDrag > 0 && !showDetails) {
                      verticalDragNotifier.value =
                          (verticalDragNotifier.value +
                                  (details.delta.dy * 0.72))
                              .clamp(0.0, 260.0);
                    }
                  },
                  onVerticalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    final verticalDrag = verticalDragNotifier.value;
                    final upwardDrag = upwardDragNotifier.value;

                    if (verticalDrag > 150 || velocity > 700) {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context, _newAssetPostEdit ?? (_editCompleted ? 'edited' : null));
                    } else if (velocity < -140 || upwardDrag > 60) {
                      HapticFeedback.mediumImpact();
                      openDetails();
                    } else {
                      verticalDragNotifier.value = 0;
                      upwardDragNotifier.value = 0;
                    }
                  },
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<double>(
                      valueListenable: verticalDragNotifier,
                      builder: (context, verticalDrag, _) {
                        return ValueListenableBuilder<double>(
                          valueListenable: upwardDragNotifier,
                          builder: (context, upwardDrag, __) {
                            final totalDrag = verticalDrag + upwardDrag;
                            final scale = (1.0 - (totalDrag / 1000)).clamp(
                              0.65,
                              1.0,
                            );
                            final borderRadius = (1.0 - scale) * 100;

                            return Transform.translate(
                              offset: Offset(
                                0,
                                verticalDrag - (upwardDrag * 0.22),
                              ),
                              child: Transform.scale(
                                scale: scale,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    borderRadius,
                                  ),
                                  child: PhotoViewGallery.builder(
                                    pageController: controller,
                                    itemCount: widget.images.length,
                                    backgroundDecoration: const BoxDecoration(
                                      color: Colors.transparent,
                                    ),
                                    onPageChanged: (index) {
                                      currentIndex = index;
                                      currentIndexNotifier.value = index;
                                      warmCurrentThenNeighbors(index);
                                      // Swipe → show strip + restore chrome
                                      showThumbnailStripTemporarily();
                                      if (!showViewerChrome) {
                                        setState(() => showViewerChrome = true);
                                      }
                                      syncThumbnailStrip();
                                      // Debounce: ignore the tap that fires
                                      // immediately after a swipe ends
                                      _swipeJustHappened = true;
                                      _swipeDebounceTimer?.cancel();
                                      _swipeDebounceTimer = Timer(
                                        const Duration(milliseconds: 350),
                                        () => _swipeJustHappened = false,
                                      );
                                    },
                                    loadingBuilder: (context, event) =>
                                        const SizedBox(),
                                    builder: (context, index) {
                                      final asset = widget.images[index];
                                      return PhotoViewGalleryPageOptions(
                                        controller: photoController,
                                        imageProvider: currentPageImageProvider(
                                          asset,
                                          index,
                                        ),
                                        heroAttributes: PhotoViewHeroAttributes(
                                          tag: asset.id,
                                        ),
                                        minScale:
                                            PhotoViewComputedScale.contained,
                                        initialScale:
                                            PhotoViewComputedScale.contained,
                                        maxScale:
                                            PhotoViewComputedScale.covered *
                                            2.4,
                                        filterQuality: FilterQuality.low,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),

                // 🔙 MENU BUTTON
                if (showViewerChrome)
                  Positioned(
                    top: 50,
                    right: 20,
                    child: ValueListenableBuilder<double>(
                      valueListenable: verticalDragNotifier,
                      builder: (context, drag, child) {
                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 100),
                          opacity: drag > 20 ? 0 : 1.0,
                          child: child,
                        );
                      },
                      child: glassButton(
                        icon: Icons.more_vert_rounded,
                        isDark: isDark,
                        onTap: () => showContextMenu(isDark),
                      ),
                    ),
                  ),

                // 🔙 BACK BUTTON
                if (showViewerChrome)
                  Positioned(
                    top: 50,
                    left: 20,
                    child: ValueListenableBuilder<double>(
                      valueListenable: verticalDragNotifier,
                      builder: (context, drag, child) {
                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 100),
                          opacity: drag > 20 ? 0 : 1.0,
                          child: child,
                        );
                      },
                      child: glassButton(
                        icon: Icons.arrow_back,
                        isDark: isDark,
                        onTap: () => Navigator.pop(context, _newAssetPostEdit ?? (_editCompleted ? 'edited' : null)),
                      ),
                    ),
                  ),

                if (showViewerChrome)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 106 + MediaQuery.of(context).padding.bottom,
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
                          opacity:
                              showDetails ||
                                  !showThumbnailStrip ||
                                  !showViewerChrome
                              ? 0
                              : 1,
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

                if (showViewerChrome)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 2 + MediaQuery.of(context).padding.bottom,
                    child: IgnorePointer(
                      ignoring: showDetails,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        offset: showDetails ? const Offset(0, 2) : Offset.zero,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: showDetails || !showViewerChrome ? 0 : 1,
                          child: ValueListenableBuilder<double>(
                            valueListenable: verticalDragNotifier,
                            builder: (context, drag, child) {
                              return AnimatedOpacity(
                                duration: const Duration(milliseconds: 100),
                                opacity: drag > 20 ? 0 : 1.0,
                                child: child,
                              );
                            },
                            child: buildQuickActionBar(isDark),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (showViewerChrome)
                  Positioned(
                    right: 12,
                    bottom: 117 + MediaQuery.of(context).padding.bottom,
                    child: IgnorePointer(
                      ignoring: showDetails,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: showDetails || !showViewerChrome ? 0 : 1,
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
    ),);
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
          height: 58,
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
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                    padding: const EdgeInsets.all(2.2),
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

  Widget buildQuickActionBar(bool isDark) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _actionIcon(Icons.share_rounded, isDark, shareAsset),
            _actionIcon(Icons.edit_rounded, isDark, editAsset),
            _actionIcon(Icons.visibility_off_rounded, isDark, hideAsset),
            _actionIcon(Icons.delete_rounded, isDark, deleteAsset),
          ],
        ),
      ),
    );
  }

  Widget _actionIcon(IconData icon, bool isDark, VoidCallback onTap) {
    return IconButton(
      iconSize: 28,
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: isDark ? Colors.white : Colors.black87),
      onPressed: onTap,
    );
  }

  AssetEntity get _currentAsset => widget.images[currentIndexNotifier.value];

  void _showViewerSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _shareCurrentFile({String? text, String? subject}) async {
    final file = await _currentAsset.file;
    if (file == null) {
      _showViewerSnackBar('File not available');
      return;
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text, subject: subject),
    );
  }

  Future<void> shareAsset() async {
    await _shareCurrentFile(
      text: 'Check this out!',
      subject: 'Shared from Gallery',
    );
  }

  Future<void> editAsset() async {
    final asset = widget.images[currentIndexNotifier.value];
    final file = await asset.file;
    if (file == null || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProImageEditor.file(
          file,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List bytes) async {
              try {
                final tempDir = await getTemporaryDirectory();
                final String originalName = asset.title ?? 'image';
                final String extension = path.extension(file.path).isEmpty ? '.jpg' : path.extension(file.path);
                final String baseName = path.basenameWithoutExtension(originalName);
                final String newFileName = '${baseName}_edited_${DateTime.now().millisecondsSinceEpoch}$extension';
                final File tempFile = File('${tempDir.path}/$newFileName');
                
                await tempFile.writeAsBytes(bytes);
                
                final AssetEntity? result = await PhotoManager.editor.saveImageWithPath(
                  tempFile.path,
                  title: newFileName,
                );
                
                if (result != null) {
                  _editCompleted = true;
                  _newAssetPostEdit = result;
                  _showViewerSnackBar('Saved as a new copy');
                }
              } catch (e) {
                print('Error saving image: $e');
                _showViewerSnackBar('Failed to save copy');
              } finally {
                Navigator.pop(context);
              }
            },
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmMoveToVault() async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(34),
            blurSigma: 18,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.12 : 0.32,
                          ),
                        ),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Move To Safe Folder?',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This item will be moved to your safe folder and hidden from your library. You can restore it later.',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.76),
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Move'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  Future<void> hideAsset() async {
    final shouldMove = await _confirmMoveToVault();
    if (!shouldMove || !mounted) return;

    try {
      await vaultService.moveAssetToVault(_currentAsset);
      if (!mounted) return;
      Navigator.pop(context, 'vault');
    } catch (_) {
      _showViewerSnackBar('Move to Safe Folder failed');
    }
  }

  Future<void> openWithAnotherApp() async {
    await _shareCurrentFile(
      text: 'Opening in another app',
      subject: 'Open with',
    );
  }

  Future<void> _showRenameDialog() async {
    final asset = _currentAsset;
    final file = await asset.file;
    if (file == null || !mounted) return;

    final currentName = path.basename(file.path);
    final ext = path.extension(currentName);        // e.g. ".jpg"
    final baseName = path.basenameWithoutExtension(currentName);
    final nameCtrl = TextEditingController(text: baseName);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(32),
            blurSigma: 18,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rename',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A renamed copy will be saved. Extension "$ext" is kept.',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => Navigator.pop(dialogContext, true),
                    decoration: InputDecoration(
                      labelText: 'New name',
                      hintText: baseName,
                      suffixText: ext,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Rename'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final newBase = nameCtrl.text.trim();
    if (newBase.isEmpty || newBase == baseName) return;

    final newTitle = '$newBase$ext';
    // Determine the MediaStore type: 1=image, 2=video, 3=audio
    final assetTypeInt = asset.type == AssetType.video
        ? 2
        : asset.type == AssetType.audio
        ? 3
        : 1;

    try {
      _showViewerSnackBar('Renaming...');
      // Pass asset ID directly — avoids unreliable DATA column query on Android 11+
      await _renameChannel.invokeMethod('renameFile', {
        'assetId': asset.id,        // MediaStore _ID
        'assetType': assetTypeInt,  // 1=image, 2=video, 3=audio
        'newName': newTitle,
      });
      if (!mounted) return;
      _showViewerSnackBar('Renamed to "$newTitle" ✔');
    } on PlatformException catch (e) {
      if (mounted) _showViewerSnackBar('Rename failed: ${e.message}');
    } catch (e) {
      if (mounted) _showViewerSnackBar('Rename failed: $e');
    }

  }

  // ── Rename + Wallpaper channels ──────────────────────────────────
  static const _renameChannel   = MethodChannel('com.rajappppp/rename');
  static const _wallpaperChannel = MethodChannel('com.rajappppp/wallpaper');

  Future<void> _setWallpaper(int which) async {
    final file = await _currentAsset.file;
    if (file == null) {
      _showViewerSnackBar('Image file not available');
      return;
    }
    _showViewerSnackBar('Setting wallpaper...');
    try {
      await _wallpaperChannel.invokeMethod('setWallpaper', {
        'path': file.path,
        'which': which, // 1=home, 2=lock, 3=both
      });
      final label = which == 1
          ? 'Home Screen'
          : which == 2
          ? 'Lock Screen'
          : 'Home & Lock Screen';
      if (mounted) _showViewerSnackBar('Wallpaper set ✔ ($label)');
    } on PlatformException catch (e) {
      if (mounted) _showViewerSnackBar('Failed: ${e.message}');
    } catch (e) {
      if (mounted) _showViewerSnackBar('Wallpaper failed');
    }
  }

  Future<void> _showSetAsSheet(bool isDark) async {
    final color = isDark ? Colors.white : Colors.black87;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _buildAnimatedSheet(
          child: GlassContainer(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            blurSigma: 20,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Set As',
                        style: TextStyle(
                          color: color,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose where to use this image.',
                        style: TextStyle(color: color.withValues(alpha: 0.68)),
                      ),
                      const SizedBox(height: 14),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.wallpaper_rounded,
                        title: 'Home Screen Wallpaper',
                        subtitle: 'Set this photo as your home screen',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _setWallpaper(1);
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.lock_rounded,
                        title: 'Lock Screen Wallpaper',
                        subtitle: 'Set this photo as your lock screen',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _setWallpaper(2);
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.phone_android_rounded,
                        title: 'Home & Lock Screen',
                        subtitle: 'Set as wallpaper everywhere',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _setWallpaper(3);
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.open_in_new_rounded,
                        title: 'Open With Another App',
                        subtitle: 'Use in contacts, social apps, etc.',
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await openWithAnotherApp();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> deleteAsset() async {
    if (isDeletingToRecycleBin) return;
    final shouldMove = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer(
            borderRadius: BorderRadius.circular(34),
            blurSigma: 18,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.12 : 0.32,
                          ),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Move To Recycle Bin?',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This item will be moved to the recycle bin and can be restored later.',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.76),
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Move'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (shouldMove != true || !mounted) return;

    setState(() {
      isDeletingToRecycleBin = true;
    });
    try {
      final asset = widget.images[currentIndexNotifier.value];
      await recycleBinDatabase.addAsset(asset);
      if (!mounted) return;
      Navigator.pop(context, 'recycle');
    } finally {
      if (mounted) {
        setState(() {
          isDeletingToRecycleBin = false;
        });
      }
    }
  }

  void showContextMenu(bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF211A33);
    final colorScheme = Theme.of(context).colorScheme;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ContextMenu',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = Curves.easeOutBack;
        final curvedAnimation = CurvedAnimation(parent: animation, curve: curve);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          alignment: Alignment.topRight,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogContext),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              right: 20,
              child: GlassContainer(
                borderRadius: BorderRadius.circular(26),
                blurSigma: 22,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Material(
                    color: Colors.transparent,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                            child: Text(
                              'Photo Actions',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Divider(
                              color: textColor.withValues(alpha: 0.12),
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildPopupMenuItem(
                            icon: Icons.edit_rounded,
                            title: 'Edit',
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              editAsset();
                            },
                          ),
                          _buildPopupMenuItem(
                            icon: Icons.drive_file_rename_outline_rounded,
                            title: 'Rename',
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _showRenameDialog();
                            },
                          ),
                          _buildPopupMenuItem(
                            icon: Icons.share_rounded,
                            title: 'Share',
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              shareAsset();
                            },
                          ),
                          _buildPopupMenuItem(
                            icon: Icons.wallpaper_rounded,
                            title: 'Set As',
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              _showSetAsSheet(isDark);
                            },
                          ),
                          _buildPopupMenuItem(
                            icon: Icons.open_in_new_rounded,
                            title: 'Open In',
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              openWithAnotherApp();
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Divider(
                              color: textColor.withValues(alpha: 0.12),
                              height: 1,
                            ),
                          ),
                          _buildPopupMenuItem(
                            icon: Icons.visibility_off_rounded,
                            title: 'Move to Vault',
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              hideAsset();
                            },
                          ),
                          _buildPopupMenuItem(
                            icon: Icons.delete_rounded,
                            title: 'Recycle Bin',
                            isDark: isDark,
                            isDestructive: true,
                            onTap: () {
                              Navigator.pop(dialogContext);
                              deleteAsset();
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPopupMenuItem({
    required IconData icon,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final textColor = isDark ? Colors.white : const Color(0xFF211A33);
    final accentColor = isDestructive ? const Color(0xFFE66A74) : textColor;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      splashColor: accentColor.withValues(alpha: 0.1),
      highlightColor: accentColor.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 21,
              color: isDestructive ? accentColor : accentColor.withValues(alpha: 0.78),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final textColor = destructive
        ? const Color(0xFFE65A66)
        : (isDark ? Colors.white : const Color(0xFF211A33));
    final iconBg = destructive
        ? const Color(0xFFE65A66).withValues(alpha: 0.12)
        : (isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.48));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          splashColor: textColor.withValues(alpha: 0.08),
          highlightColor: textColor.withValues(alpha: 0.04),
          overlayColor: WidgetStatePropertyAll(
            textColor.withValues(alpha: 0.06),
          ),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: GlassContainer(
            borderRadius: BorderRadius.circular(24),
            enableBlur: false,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: textColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.7),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: textColor.withValues(alpha: 0.72),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedSheet({required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, sheetChild) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 26),
          child: Opacity(opacity: value, child: sheetChild),
        );
      },
      child: child,
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
    final iconColor = isDark ? Colors.white : const Color(0xFF241C37);
    return GlassContainer(
      borderRadius: BorderRadius.circular(22),
      blurSigma: 16,
      child: SizedBox(
        width: 50,
        height: 50,
        child: IconButton(
          icon: Icon(icon, color: iconColor),
          onPressed: onTap,
        ),
      ),
    );
  }

  // 📊 DETAILS PANEL
  Widget buildDetailsPanel(AssetEntity asset, bool isDark) {
    final accent = isDark ? const Color(0xFFB8AEFF) : const Color(0xFF7A6CE0);
    final panelColor = isDark
        ? Colors.white.withOpacity(0.09)
        : Colors.white.withOpacity(0.72);

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      offset: showDetails ? const Offset(0, 0) : const Offset(0, 1.08),
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
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
                            color: isDark ? Colors.white38 : Colors.black26,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 8,
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
                                  'Captured information and details',
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
                              label: 'Size',
                              valueWidget: FutureBuilder<String>(
                                future: fileSizeLabel(asset),
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? 'Loading...',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                    ),
                                  );
                                },
                              ),
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
    String? value,
    Widget? valueWidget,
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
                if (valueWidget != null)
                  valueWidget
                else
                  Text(
                    value ?? '',
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
