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
  bool isInteractingWithStrip = false;

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

    return Scaffold(
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
                      Navigator.pop(context);
                    } else if (velocity < -140 || upwardDrag > 60) {
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
                                      showThumbnailStripTemporarily();
                                      syncThumbnailStrip();
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
                        onTap: () => Navigator.pop(context),
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
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> hideAsset() async {
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
    final file = await _currentAsset.file;
    final currentName = file == null
        ? 'Unknown file'
        : path.basename(file.path);
    final controller = TextEditingController(text: currentName);

    if (!mounted) return;

    await showDialog<void>(
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
                  const SizedBox(height: 10),
                  Text(
                    'Premium rename UI is ready, but safe gallery-file rename still needs native media-store handling in this app.',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.74),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Current file name',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
                        'Choose where you want to use this image next.',
                        style: TextStyle(color: color.withValues(alpha: 0.68)),
                      ),
                      const SizedBox(height: 14),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.wallpaper_rounded,
                        title: 'Home Screen',
                        subtitle: 'Prepare this photo for wallpaper use',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _showViewerSnackBar(
                            'Set as wallpaper needs native Android integration next',
                          );
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.lock_rounded,
                        title: 'Lock Screen',
                        subtitle: 'Use this image on the lock screen',
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _showViewerSnackBar(
                            'Lock-screen set as needs native Android integration next',
                          );
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.person_rounded,
                        title: 'Profile Photo',
                        subtitle: 'Open this image in another app to continue',
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final textColor = isDark ? Colors.white : const Color(0xFF211A33);
        return _buildAnimatedSheet(
          child: GlassContainer(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            blurSigma: 22,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: textColor.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Text(
                        'Photo Actions',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Quick tools and premium actions for this image.',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.68),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildMenuSectionLabel(
                        title: 'Editing',
                        color: textColor,
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.edit_rounded,
                        title: 'Edit',
                        subtitle: 'Open the built-in editor',
                        onTap: () {
                          Navigator.pop(context);
                          editAsset();
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.drive_file_rename_outline_rounded,
                        title: 'Rename',
                        subtitle: 'Prepare a better file name',
                        onTap: () async {
                          Navigator.pop(context);
                          await _showRenameDialog();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildMenuSectionLabel(
                        title: 'Sharing',
                        color: textColor,
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.open_in_new_rounded,
                        title: 'Open With App',
                        subtitle: 'Send this image into another app',
                        onTap: () async {
                          Navigator.pop(context);
                          await openWithAnotherApp();
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.wallpaper_rounded,
                        title: 'Set As',
                        subtitle: 'Wallpaper, lock screen, or profile photo',
                        onTap: () async {
                          Navigator.pop(context);
                          await _showSetAsSheet(isDark);
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.share_rounded,
                        title: 'Share',
                        subtitle: 'Share this image anywhere',
                        onTap: () {
                          Navigator.pop(context);
                          shareAsset();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildMenuSectionLabel(
                        title: 'Privacy',
                        color: textColor,
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.visibility_off_rounded,
                        title: 'Move to Vault',
                        subtitle: 'Hide this image from the gallery',
                        onTap: () {
                          Navigator.pop(context);
                          hideAsset();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildMenuSectionLabel(title: 'Delete', color: textColor),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.delete_rounded,
                        title: 'Move to Recycle Bin',
                        subtitle: 'Remove it now, restore it later',
                        destructive: true,
                        onTap: () {
                          Navigator.pop(context);
                          deleteAsset();
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

  Widget _buildMenuSectionLabel({required String title, required Color color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: color.withValues(alpha: 0.54),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
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
