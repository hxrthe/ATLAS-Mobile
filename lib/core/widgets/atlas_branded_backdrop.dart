import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Login-style red grid + radial wash that softens toward the bottom.
///
/// Strong at the top (same language as the splash), fades through the middle,
/// and leaves only a light hint near the bottom.
class AtlasBrandedBackdrop extends StatelessWidget {
  const AtlasBrandedBackdrop({
    super.key,
    required this.child,
    this.fadeStart = 0.28,
    this.fadeMid = 0.55,
  });

  final Widget child;

  /// Where the fade toward the scaffold color begins (0–1).
  final double fadeStart;

  /// Where the fade is mostly complete (0–1); bottom keeps a slight hint.
  final double fadeMid;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    // True near-black in dark mode; soft off-white in light (login scaffold).
    final base = isDark ? const Color(0xFF0A0A0B) : const Color(0xFFFBF7F7);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Solid base — must read as black in dark mode.
        Positioned.fill(child: ColoredBox(color: base)),

        // Splash / login radial wash + grid (fades itself toward bottom).
        Positioned.fill(
          child: CustomPaint(
            painter: AtlasBrandedGridPainter(isDark: isDark),
          ),
        ),

        // Extra vertical veil so the pattern dissolves mid-screen → hint only.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    base.withValues(alpha: 0.0),
                    base.withValues(alpha: 0.0),
                    base.withValues(alpha: 0.45),
                    base.withValues(alpha: 0.82),
                    base.withValues(alpha: 0.92),
                  ],
                  stops: [
                    0.0,
                    fadeStart,
                    fadeMid,
                    0.78,
                    1.0,
                  ],
                ),
              ),
            ),
          ),
        ),

        child,
      ],
    );
  }
}

/// Soft grid + radial red glow matching the login auth shell.
class AtlasBrandedGridPainter extends CustomPainter {
  AtlasBrandedGridPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Same radial stops as login splash.
    final wash = Paint()
      ..shader = RadialGradient(
        center: isDark
            ? const Alignment(-0.2, -0.35)
            : const Alignment(-0.15, -0.4),
        radius: isDark ? 1.15 : 1.2,
        colors: isDark
            ? const [
                Color(0xFF6E1212),
                Color(0xFF0A0A0B),
                Color(0xFF050506),
              ]
            : const [
                Color(0xFFF8D4D3),
                Color(0xFFFFF5F5),
                Color(0xFFFBF7F7),
              ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, wash);

    // Grid: stronger at top, nearly gone at bottom (hint remains).
    final lineColor =
        isDark ? Colors.white : const Color(0xFF8E1C1B);
    final topAlpha = isDark ? 0.07 : 0.08;
    const step = 36.0;

    for (double x = 0; x < size.width; x += step) {
      final paint = Paint()
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: topAlpha),
            lineColor.withValues(alpha: topAlpha * 0.45),
            lineColor.withValues(alpha: topAlpha * 0.08),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Offset.zero & size);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += step) {
      final t = (y / size.height).clamp(0.0, 1.0);
      // Keep a small residual alpha at the bottom so the grid doesn't vanish.
      final alpha = topAlpha * (1.0 - t * 0.9).clamp(0.08, 1.0);
      final paint = Paint()
        ..color = lineColor.withValues(alpha: alpha)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Soft red vignette (login shell).
    final glow = Paint()
      ..shader = RadialGradient(
        center: Alignment(0.7, isDark ? -0.6 : -0.55),
        radius: 1.05,
        colors: [
          const Color(0xFFAA2423).withValues(alpha: isDark ? 0.16 : 0.12),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant AtlasBrandedGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
