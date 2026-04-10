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
    this.blurSigma = 7,
    this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(30);
    final accentColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    final gradientColors = isDark
        ? [
            const Color(0xFF1A1A1A).withValues(alpha: 0.82),
            const Color(0xFF121212).withValues(alpha: 0.72),
            const Color(0xFF0A0A0A).withValues(alpha: 0.88),
        ]
        : [
            const Color(0xFFFFFFFF).withValues(alpha: 0.92),
            const Color(0xFFFBFBFB).withValues(alpha: 0.82),
            const Color(0xFFFFFFFF).withValues(alpha: 0.88),
        ];

    final finalGradient = backgroundColor != null
        ? LinearGradient(
            colors: [
              Color.lerp(
                backgroundColor!,
                isDark ? Colors.white : Colors.white,
                isDark ? 0.06 : 0.16,
              )!
                  .withValues(alpha: backgroundColor!.a / 255.0),
              backgroundColor!,
              Color.lerp(
                backgroundColor!,
                accentColor,
                isDark ? 0.14 : 0.1,
              )!
                  .withValues(alpha: backgroundColor!.a / 255.0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
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
          color: borderColor ??
              (isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.1)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: isDark ? 0.18 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
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
                    Colors.white.withValues(alpha: isDark ? 0.12 : 0.36),
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
