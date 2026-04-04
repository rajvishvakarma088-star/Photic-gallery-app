import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool enableBlur;
  final double blurSigma;
  final Color? borderColor;
  final Color? backgroundColor;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.enableBlur = true,
    this.blurSigma = 10,
    this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(30);
    final gradientColors = isDark
        ? [
            Colors.white.withValues(alpha: 0.12),
            const Color(0xFF7E5DFF).withValues(alpha: 0.1),
            const Color(0xFF57B2FF).withValues(alpha: 0.06),
          ]
        : [
            const Color(0xFFF6EEFF).withValues(alpha: 0.9),
            const Color(0xFFE6D9FF).withValues(alpha: 0.76),
            const Color(0xFFD8C2FF).withValues(alpha: 0.66),
          ];

    final finalGradient = backgroundColor != null 
        ? LinearGradient(colors: [backgroundColor!, backgroundColor!])
        : LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    final glassSurface = DecoratedBox(
      decoration: BoxDecoration(
        gradient: finalGradient,
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? (isDark
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.74)),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C6EE6)
                .withValues(alpha: isDark ? 0.1 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.16 : 0.46),
                    Colors.white.withValues(alpha: 0),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.center,
                ),
              ),
            ),
          ),
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: enableBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                ),
                child: glassSurface,
              )
            : glassSurface,
      ),
    );
  }
}
