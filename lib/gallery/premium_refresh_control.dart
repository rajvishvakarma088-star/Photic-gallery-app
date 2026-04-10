import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PremiumRefreshControl extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const PremiumRefreshControl({
    super.key,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoSliverRefreshControl(
      refreshTriggerPullDistance: 140.0,
      refreshIndicatorExtent: 60.0,
      onRefresh: onRefresh,
      builder: (
        context,
        refreshState,
        pulledExtent,
        refreshTriggerPullDistance,
        refreshIndicatorExtent,
        ) {
        // Add a 30px "Dead Zone" to prevent flickering on accidental slight pulls
        const double deadZone = 30.0;
        final double effectivePulled = math.max(0.0, pulledExtent - deadZone);
        final double effectiveTrigger = refreshTriggerPullDistance - deadZone;
        final double percentage = (effectivePulled / effectiveTrigger).clamp(0.0, 1.0);
        
        return Container(
          height: pulledExtent,
          alignment: Alignment.center,
          child: _PremiumRefreshIndicatorUI(
            refreshState: refreshState,
            pulledExtent: pulledExtent,
            percentage: percentage,
          ),
        );
      },
    );
  }
}

class _PremiumRefreshIndicatorUI extends StatefulWidget {
  final RefreshIndicatorMode refreshState;
  final double pulledExtent;
  final double percentage;

  const _PremiumRefreshIndicatorUI({
    required this.refreshState,
    required this.pulledExtent,
    required this.percentage,
  });

  @override
  State<_PremiumRefreshIndicatorUI> createState() => _PremiumRefreshIndicatorUIState();
}

class _PremiumRefreshIndicatorUIState extends State<_PremiumRefreshIndicatorUI> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _hasFiredHaptic = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didUpdateWidget(_PremiumRefreshIndicatorUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Trigger haptic once when reaching threshold
    if (widget.refreshState == RefreshIndicatorMode.armed && !_hasFiredHaptic) {
      HapticFeedback.heavyImpact();
      _hasFiredHaptic = true;
    } else if (widget.refreshState == RefreshIndicatorMode.inactive) {
      _hasFiredHaptic = false;
    }

    // Start/Stop rotation based on state
    if (widget.refreshState == RefreshIndicatorMode.refresh) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // The "Morphing" logic
    final double scale = widget.refreshState == RefreshIndicatorMode.refresh 
        ? 1.0 
        : (0.4 + (0.6 * widget.percentage)).clamp(0.0, 1.2);
    
    final double opacity = (widget.percentage * 2).clamp(0.0, 1.0);
    final double rotation = widget.refreshState == RefreshIndicatorMode.refresh
        ? 0.0 // Handled by rotation controller
        : widget.percentage * math.pi;

    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: widget.refreshState == RefreshIndicatorMode.refresh
              ? _buildLoadingSpinner(colorScheme, isDark)
              : _buildSnoopIcon(colorScheme, isDark, rotation),
        ),
      ),
    );
  }

  Widget _buildSnoopIcon(ColorScheme colorScheme, bool isDark, double rotation) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Icon(
          Icons.manage_search_rounded,
          color: colorScheme.primary,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildLoadingSpinner(ColorScheme colorScheme, bool isDark) {
    return RotationTransition(
      turns: _rotationController,
      child: CustomPaint(
        size: const Size(44, 44),
        painter: _PremiumSpinPainter(
          color: colorScheme.primary,
          isDark: isDark,
        ),
      ),
    );
  }
}

class _PremiumSpinPainter extends CustomPainter {
  final Color color;
  final bool isDark;

  _PremiumSpinPainter({required this.color, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    // Background track
    paint.color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05);
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint);

    // Active gradient arc
    final gradient = SweepGradient(
      colors: [
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.5),
        color,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    
    paint.shader = gradient.createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 1.5 * math.pi, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
