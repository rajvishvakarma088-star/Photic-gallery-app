import 'dart:io';
import 'dart:async';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:ui';
import 'glass_container.dart';

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
  final ValueNotifier<double> verticalDragNotifier = ValueNotifier<double>(0);
  late PageController pageController;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    verticalDragNotifier.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _applySystemUiStyle(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  void showContextMenu(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Container(
                     width: 44, height: 5,
                     margin: const EdgeInsets.only(bottom: 24),
                     decoration: BoxDecoration(color: isDark ? Colors.white38 : Colors.black26, borderRadius: BorderRadius.circular(99)),
                   ),
                   ListTile(
                     leading: Icon(Icons.share_rounded, color: isDark ? Colors.white : Colors.black),
                     title: Text('Share Video', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                     onTap: () { Navigator.pop(context); shareAsset(); },
                   ),
                   ListTile(
                     leading: Icon(Icons.visibility_off_rounded, color: isDark ? Colors.white : Colors.black),
                     title: Text('Move to Vault', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                     onTap: () { Navigator.pop(context); hideAsset(); },
                   ),
                   ListTile(
                     leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                     title: const Text('Delete Video', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                     onTap: () { Navigator.pop(context); deleteAsset(); },
                   ),
                ]
              )
            )
          )
        );
      }
    );
  }

  Future<void> shareAsset() async {
    final file = await widget.videos[currentIndex].file;
    if (file != null) {
      await Share.shareXFiles([XFile(file.path)], text: 'Check out this video!');
    }
  }

  Future<void> hideAsset() async {
     ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('Moved to Private Vault'), behavior: SnackBarBehavior.floating),
     );
  }

  Future<void> deleteAsset() async {
    final result = await PhotoManager.editor.deleteWithIds([widget.videos[currentIndex].id]);
    if (result.isNotEmpty) {
       Navigator.pop(context);
    }
  }

  Widget buildQuickActionBar(bool isDark) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _actionIcon(Icons.share_rounded, isDark, shareAsset),
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
                color: Colors.black.withOpacity((1.0 - dismissProgress).clamp(0.0, 1.0)),
              );
            },
          ),
          
          GestureDetector(
            onLongPress: () => showContextMenu(isDark),
            onVerticalDragUpdate: (details) {
              final newDrag = verticalDragNotifier.value + details.delta.dy;
              if (newDrag > 0) {
                verticalDragNotifier.value =
                    (verticalDragNotifier.value + (details.delta.dy * 0.72)).clamp(0.0, 260.0);
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
                final scale = (1.0 - (verticalDrag.abs() / 1000)).clamp(0.65, 1.0);
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
                              child: _VideoPage(asset: asset),
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),
          ),

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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
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
          ),
          
          Positioned(
            left: 16,
            right: 16,
            bottom: 8 + MediaQuery.of(context).padding.bottom,
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
        ],
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final AssetEntity asset;
  const _VideoPage({required this.asset});

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

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: true,
      looping: true,
      showControls: true,
      showOptions: false,
      allowFullScreen: false,
      customControls: const PremiumVideoControls(),
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
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return AspectRatio(
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      child: Chewie(
        controller: _chewieController!,
      ),
    );
  }
}

class PremiumVideoControls extends StatefulWidget {
  const PremiumVideoControls({super.key});

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
    _controller = ChewieController.of(context)!.videoPlayerController;
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
                      icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
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
                          _controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    IconButton(
                      iconSize: 42,
                      icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                      onPressed: () => _skip(10),
                    ),
                  ],
                ),
              ),
              // Lifted Progress Bar
              Positioned(
                left: 20,
                right: 20,
                bottom: 110 + MediaQuery.of(context).padding.bottom,
                child: Row(
                  children: [
                    Text(_formatDuration(_controller.value.position), 
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
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
                    Text(_formatDuration(_controller.value.duration), 
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
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
