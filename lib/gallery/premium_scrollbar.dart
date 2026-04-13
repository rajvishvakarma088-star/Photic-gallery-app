import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

class PremiumScrollbar extends ConsumerStatefulWidget {
  final Widget child;
  final ScrollController controller;
  final double topPadding;
  final double bottomPadding;

  const PremiumScrollbar({
    super.key,
    required this.child,
    required this.controller,
    this.topPadding = 0.0,
    this.bottomPadding = 0.0,
  });

  @override
  ConsumerState<PremiumScrollbar> createState() => _PremiumScrollbarState();
}

class _PremiumScrollbarState extends ConsumerState<PremiumScrollbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  Timer? _hideTimer;
  bool _isDragging = false;
  double _dragStartOffsetY = 0.0;
  double _dragStartScrollOffset = 0.0;
  double _currentViewportHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _fadeController.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_isDragging) return;
    _showScrollbar();
  }

  void _showScrollbar() {
    if (!mounted) return;
    _fadeController.forward();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!_isDragging && mounted) {
        _fadeController.reverse();
      }
    });
    setState(() {}); // Repaint based on controller offset
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    if (!settings.slidingBarEnabled) {
      return widget.child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _currentViewportHeight = constraints.maxHeight;

        return Stack(
          children: [
            widget.child,
            AnimatedBuilder(
              animation: _fadeController,
              builder: (context, child) {
                if (_fadeController.value == 0.0) return const SizedBox.shrink();

                if (!widget.controller.hasClients) {
                  return const SizedBox.shrink();
                }

                final position = widget.controller.position;
                if (position.maxScrollExtent <= 0) {
                  return const SizedBox.shrink();
                }

                final maxOffset = position.maxScrollExtent;
                final currentOffset = position.pixels;
                final fraction = (currentOffset / maxOffset).clamp(0.0, 1.0);

                final viewportHeight = constraints.maxHeight;
                final trackTop = widget.topPadding + 16.0;
                final trackBottom = viewportHeight - widget.bottomPadding - 16.0;
                
                const double logicalThumbBoxHeight = 60.0;
                const double logicalThumbBoxWidth = 34.0;
                final usableHeight = trackBottom - trackTop - logicalThumbBoxHeight;

                if (usableHeight <= 0) return const SizedBox.shrink();

                final topOffset = trackTop + fraction * usableHeight;

                final colorScheme = Theme.of(context).colorScheme;
                final isDark = Theme.of(context).brightness == Brightness.dark;

                final targetThumbWidth = _isDragging ? 32.0 : 26.0;
                final targetThumbHeight = _isDragging ? 58.0 : 48.0;

                return Positioned(
                  top: topOffset,
                  right: 4,
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (details) {
                        _isDragging = true;
                        if (widget.controller.hasClients) {
                          _dragStartScrollOffset = widget.controller.offset;
                          _dragStartOffsetY = details.globalPosition.dy;
                        }
                        _showScrollbar();
                      },
                      onVerticalDragUpdate: (details) {
                        if (!widget.controller.hasClients) return;
                        
                        final deltaY = details.globalPosition.dy - _dragStartOffsetY;
                        final scrollDelta = deltaY * (maxOffset / usableHeight);
                        final targetOffset = (_dragStartScrollOffset + scrollDelta).clamp(0.0, maxOffset);
                        
                        widget.controller.jumpTo(targetOffset);
                        // JumpTo updates scroll which triggers _onScroll but we return early
                        // We must setState here so Slider repaints
                        setState(() {});
                      },
                      onVerticalDragEnd: (details) {
                        _isDragging = false;
                        _showScrollbar();
                      },
                      onVerticalDragCancel: () {
                        _isDragging = false;
                        _showScrollbar();
                      },
                      child: SizedBox(
                        width: logicalThumbBoxWidth,
                        height: logicalThumbBoxHeight,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            width: targetThumbWidth,
                            height: targetThumbHeight,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.95)
                                  : colorScheme.surface.withValues(alpha: 0.98),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
                                  blurRadius: _isDragging ? 14 : 10,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: colorScheme.shadow.withValues(alpha: 0.05),
                                  spreadRadius: _isDragging ? 2 : 1,
                                  blurRadius: 15,
                                ),
                              ],
                              border: Border.all(
                                color: colorScheme.onSurface.withValues(alpha: isDark ? 0.1 : 0.05),
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  size: _isDragging ? 18 : 14,
                                  color: isDark
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurfaceVariant,
                                ),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: _isDragging ? 18 : 14,
                                  color: isDark
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
