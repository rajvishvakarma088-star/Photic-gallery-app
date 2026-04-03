import 'dart:async';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'glass_container.dart';
import 'services/recycle_bin_database.dart';
import 'services/vault_service.dart';

class VideoViewerScreen extends StatefulWidget {
  final List<AssetEntity> videos;
  final int initialIndex;

  const VideoViewerScreen({
    super.key,
    required this.videos,
    required this.initialIndex,
  });

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  final RecycleBinDatabase recycleBinDatabase = RecycleBinDatabase.instance;
  final VaultService vaultService = VaultService.instance;
  final ValueNotifier<double> verticalDragNotifier = ValueNotifier<double>(0);
  final Map<int, VideoPlayerController> _videoControllers = {};
  late PageController pageController;
  late int currentIndex;
  bool isDeletingToRecycleBin = false;
  bool hideViewerChrome = false;
  bool showViewerChrome = true;
  Brightness? _lastAppliedBrightness;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    verticalDragNotifier.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _applySystemUiStyle(Brightness brightness) {
    if (_lastAppliedBrightness == brightness && !hideViewerChrome) return;
    _lastAppliedBrightness = brightness;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  VideoPlayerController? get _currentVideoController =>
      _videoControllers[currentIndex];

  void _showViewerSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _shareCurrentVideo({String? text, String? subject}) async {
    final file = await widget.videos[currentIndex].file;
    if (file == null) {
      _showViewerSnackBar('Video file not available');
      return;
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text, subject: subject),
    );
  }

  Future<void> openWithAnotherApp() async {
    await _shareCurrentVideo(
      text: 'Opening in another app',
      subject: 'Open with',
    );
  }

  Future<void> _toggleImmersivePlayback() async {
    setState(() {
      hideViewerChrome = !hideViewerChrome;
    });

    if (hideViewerChrome) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _showPlaybackSpeedSheet(bool isDark) async {
    final controller = _currentVideoController;
    if (controller == null || !controller.value.isInitialized) {
      _showViewerSnackBar('Playback controls are not ready yet');
      return;
    }

    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final textColor = isDark ? Colors.white : const Color(0xFF221B34);

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
                            color: textColor.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Playback Speed',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose how fast this video should play.',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: speeds
                            .map((speed) {
                              final isActive =
                                  (controller.value.playbackSpeed - speed)
                                      .abs() <
                                  0.001;
                              return GestureDetector(
                                onTap: () async {
                                  HapticFeedback.selectionClick();
                                  await controller.setPlaybackSpeed(speed);
                                  if (!mounted || !sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                  setState(() {});
                                },
                                child: GlassContainer(
                                  borderRadius: BorderRadius.circular(18),
                                  enableBlur: false,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      '${speed}x',
                                      style: TextStyle(
                                        color: isActive
                                            ? (isDark
                                                  ? const Color(0xFFDCCFFF)
                                                  : const Color(0xFF5D44D6))
                                            : textColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
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

  void showContextMenu(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final textColor = isDark ? Colors.white : const Color(0xFF221B34);
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
                        'Video Actions',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Playback tools and quick actions for this video.',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.68),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildMenuSectionLabel(
                        title: 'Playback',
                        color: textColor,
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: hideViewerChrome
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        title: hideViewerChrome
                            ? 'Exit Full Screen'
                            : 'Full Screen Playback',
                        subtitle: 'Hide or show the viewer chrome',
                        onTap: () async {
                          Navigator.pop(context);
                          await _toggleImmersivePlayback();
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.speed_rounded,
                        title: 'Playback Speed',
                        subtitle: '0.5x to 2.0x speed control',
                        onTap: () async {
                          Navigator.pop(context);
                          await _showPlaybackSpeedSheet(isDark);
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
                        subtitle: 'Send this video into another app',
                        onTap: () async {
                          Navigator.pop(context);
                          await openWithAnotherApp();
                        },
                      ),
                      _buildMenuTile(
                        isDark: isDark,
                        icon: Icons.share_rounded,
                        title: 'Share Video',
                        subtitle: 'Share this clip anywhere',
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
                        subtitle: 'Hide this video from the gallery',
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

  Future<void> shareAsset() async {
    await _shareCurrentVideo(
      text: 'Check out this video!',
      subject: 'Shared from Gallery',
    );
  }

  Future<void> hideAsset() async {
    try {
      await vaultService.moveAssetToVault(widget.videos[currentIndex]);
      if (!mounted) return;
      Navigator.pop(context, 'vault');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Move to Safe Folder failed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
      await recycleBinDatabase.addAsset(widget.videos[currentIndex]);
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

  Widget buildQuickActionBar(bool isDark) {
    final speed = _currentVideoController?.value.playbackSpeed ?? 1.0;
    return GlassContainer(
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildBottomActionItem(
              isDark: isDark,
              icon: hideViewerChrome
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              label: 'Screen',
              onTap: _toggleImmersivePlayback,
            ),
            _buildBottomActionItem(
              isDark: isDark,
              icon: Icons.speed_rounded,
              label:
                  '${speed.toStringAsFixed(speed.truncateToDouble() == speed ? 0 : 2)}x',
              onTap: () => _showPlaybackSpeedSheet(isDark),
            ),
            _buildBottomActionItem(
              isDark: isDark,
              icon: Icons.share_rounded,
              label: 'Share',
              onTap: shareAsset,
            ),
            _buildBottomActionItem(
              isDark: isDark,
              icon: Icons.visibility_off_rounded,
              label: 'Vault',
              onTap: hideAsset,
            ),
            _buildBottomActionItem(
              isDark: isDark,
              icon: Icons.delete_rounded,
              label: 'Delete',
              destructive: true,
              onTap: deleteAsset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionItem({
    required bool isDark,
    required IconData icon,
    required String label,
    required FutureOr<void> Function() onTap,
    bool destructive = false,
  }) {
    final color = destructive
        ? const Color(0xFFE66A74)
        : (isDark ? Colors.white : const Color(0xFF211A33));

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            HapticFeedback.selectionClick();
            await onTap();
            if (mounted) {
              setState(() {});
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: destructive
                        ? const Color(0xFFE66A74).withValues(alpha: 0.14)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.42)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    _applySystemUiStyle(brightness);
    final isDark = brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background fade on drag
          ValueListenableBuilder<double>(
            valueListenable: verticalDragNotifier,
            builder: (context, verticalDrag, _) {
              final dismissProgress = (verticalDrag / 220).clamp(0.0, 1.0);
              return Container(
                color: Colors.black.withOpacity(
                  (1.0 - dismissProgress).clamp(0.0, 1.0),
                ),
              );
            },
          ),

          GestureDetector(
            onTap: () {
              setState(() {
                showViewerChrome = !showViewerChrome;
              });
            },
            onLongPress: () => showContextMenu(isDark),
            onVerticalDragUpdate: (details) {
              final newDrag = verticalDragNotifier.value + details.delta.dy;
              if (newDrag > 0) {
                verticalDragNotifier.value =
                    (verticalDragNotifier.value + (details.delta.dy * 0.72))
                        .clamp(0.0, 260.0);
              }
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              final verticalDrag = verticalDragNotifier.value;

              if (verticalDrag > 150 || velocity > 700) {
                Navigator.pop(context);
              } else {
                verticalDragNotifier.value = 0;
              }
            },
            child: ValueListenableBuilder<double>(
              valueListenable: verticalDragNotifier,
              builder: (context, verticalDrag, _) {
                final scale = (1.0 - (verticalDrag.abs() / 1000)).clamp(
                  0.65,
                  1.0,
                );
                final borderRadius = (1.0 - scale) * 100;

                return Transform.translate(
                  offset: Offset(0, verticalDrag),
                  child: Center(
                    child: Transform.scale(
                      scale: scale,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(borderRadius),
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: widget.videos.length,
                          onPageChanged: (idx) {
                            setState(() {
                              currentIndex = idx;
                            });
                          },
                          itemBuilder: (context, idx) {
                            final asset = widget.videos[idx];
                            return Hero(
                              tag: asset.id,
                              child: _VideoPage(
                                asset: asset,
                                immersiveMode: hideViewerChrome,
                                onSurfaceTap: () {
                                  if (!mounted) return;
                                  setState(() {
                                    showViewerChrome = !showViewerChrome;
                                  });
                                },
                                onControllerReady: (controller) {
                                  _videoControllers[idx] = controller;
                                  if (idx == currentIndex && mounted) {
                                    setState(() {});
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (!hideViewerChrome && showViewerChrome)
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
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(22),
                  blurSigma: 16,
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),

          if (!hideViewerChrome && showViewerChrome)
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
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(22),
                  blurSigma: 16,
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => showContextMenu(isDark),
                    ),
                  ),
                ),
              ),
            ),

          if (!hideViewerChrome && showViewerChrome)
            Positioned(
              left: 16,
              right: 16,
              bottom: 2 + MediaQuery.of(context).padding.bottom,
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

          if (hideViewerChrome && showViewerChrome)
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
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(22),
                  blurSigma: 16,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: IconButton(
                      tooltip: 'Exit full screen',
                      icon: const Icon(
                        Icons.fullscreen_exit_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _toggleImmersivePlayback,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final AssetEntity asset;
  final bool immersiveMode;
  final VoidCallback? onSurfaceTap;
  final ValueChanged<VideoPlayerController> onControllerReady;

  const _VideoPage({
    required this.asset,
    required this.immersiveMode,
    required this.onSurfaceTap,
    required this.onControllerReady,
  });

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    final file = await widget.asset.file;
    if (file == null || !mounted) return;

    _videoPlayerController = VideoPlayerController.file(file);
    await _videoPlayerController!.initialize();
    widget.onControllerReady(_videoPlayerController!);

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: true,
      showControls: true,
      showOptions: false,
      allowFullScreen: false,
      customControls: PremiumVideoControls(
        immersiveMode: widget.immersiveMode,
        onSurfaceTap: widget.onSurfaceTap,
      ),
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return AspectRatio(
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }
}

class PremiumVideoControls extends StatefulWidget {
  final bool immersiveMode;
  final VoidCallback? onSurfaceTap;

  const PremiumVideoControls({
    super.key,
    required this.immersiveMode,
    required this.onSurfaceTap,
  });

  @override
  State<PremiumVideoControls> createState() => _PremiumVideoControlsState();
}

class _PremiumVideoControlsState extends State<PremiumVideoControls> {
  late VideoPlayerController _controller;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ChewieController.of(context).videoPlayerController;
    _controller.addListener(_updateState);
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_updateState);
    super.dispose();
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
    widget.onSurfaceTap?.call();
  }

  void _skip(int seconds) {
    if (!_controller.value.isInitialized) return;
    final newPos = _controller.value.position + Duration(seconds: seconds);
    _controller.seekTo(newPos);
    _startHideTimer();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) return const SizedBox();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _showControls ? 1.0 : 0.0,
        child: Container(
          color: Colors.black26,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 42,
                      icon: const Icon(
                        Icons.replay_10_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => _skip(-10),
                    ),
                    const SizedBox(width: 32),
                    GestureDetector(
                      onTap: () {
                        if (_controller.value.isPlaying) {
                          _controller.pause();
                        } else {
                          _controller.play();
                        }
                        _startHideTimer();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    IconButton(
                      iconSize: 42,
                      icon: const Icon(
                        Icons.forward_10_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => _skip(10),
                    ),
                  ],
                ),
              ),
              // Lifted Progress Bar
              Positioned(
                left: 20,
                right: 20,
                bottom:
                    (widget.immersiveMode ? 36 : 110) +
                    MediaQuery.of(context).padding.bottom,
                child: Row(
                  children: [
                    Text(
                      _formatDuration(_controller.value.position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _formatDuration(_controller.value.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
