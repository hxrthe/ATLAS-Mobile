import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Pure Flutter ATLAS mark animation (no GIF / no white fringe).
///
/// Draws the brand "A", a rising chart arrow, and document pages with a
/// looping draw + pulse — matching the old loading video motion in the logo red.
class AtlasLogoMotion extends StatefulWidget {
  const AtlasLogoMotion({
    super.key,
    this.size = 72,
    this.showShadow = true,
  });

  final double size;
  final bool showShadow;

  @override
  State<AtlasLogoMotion> createState() => _AtlasLogoMotionState();
}

class _AtlasLogoMotionState extends State<AtlasLogoMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final t = _loop.value;
        // Intro scale on first 20% of each loop, then soft breathe.
        final appear = Curves.easeOutBack.transform((t / 0.22).clamp(0.0, 1.0));
        final breathe = 1.0 + 0.03 * math.sin(t * math.pi * 2);
        final scale = (0.88 + 0.12 * appear) * breathe;

        return SizedBox(
          width: size * 1.15,
          height: size * 1.15,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (widget.showShadow)
                Transform.translate(
                  offset: Offset(0, size * 0.32),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 7),
                    child: Container(
                      width: size * 0.66,
                      height: size * 0.16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8E1C1B).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              Transform.scale(
                scale: scale,
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _AtlasMarkPainter(progress: t),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AtlasMarkPainter extends CustomPainter {
  _AtlasMarkPainter({required this.progress});

  final double progress;

  static const _forest = Color(0xFF6E1212);
  static const _primary = Color(0xFF8E1C1B);
  static const _leaf = Color(0xFFAA2423);
  static const _mint = Color(0xFFE24B4A);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2 + s * 0.04;

    // Staggered motion phases (loop 0→1)
    final aOpacity = Curves.easeOut.transform(_phase(0.00, 0.28));
    final pagesT = Curves.easeOutCubic.transform(_phase(0.12, 0.55));
    final chartT = Curves.easeInOutCubic.transform(_phase(0.18, 0.78));
    final glowT = Curves.easeInOut.transform(
      (math.sin((progress * 2 - 0.3).clamp(0.0, 1.0) * math.pi)).clamp(0.0, 1.0),
    );

    // Soft brand glow behind mark
    final glow = Paint()
      ..color = _leaf.withValues(alpha: 0.10 + 0.08 * glowT)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(Offset(cx, cy), s * 0.38, glow);

    _paintLetterA(canvas, cx, cy, s, aOpacity);
    _paintPages(canvas, cx, cy, s, pagesT);
    _paintChart(canvas, cx, cy, s, chartT);
  }

  double _phase(double start, double end) {
    if (progress <= start) return 0;
    if (progress >= end) return 1;
    return (progress - start) / (end - start);
  }

  void _paintLetterA(Canvas canvas, double cx, double cy, double s, double opacity) {
    if (opacity <= 0) return;

    final paint = Paint()
      ..color = _forest.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final top = Offset(cx, cy - s * 0.34);
    final bl = Offset(cx - s * 0.30, cy + s * 0.36);
    final br = Offset(cx + s * 0.30, cy + s * 0.36);

    final a = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(top.dx, top.dy)
      ..lineTo(br.dx, br.dy);
    canvas.drawPath(a, paint);

    // Crossbar
    final barY = cy + s * 0.02;
    final barPaint = Paint()
      ..color = _primary.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - s * 0.14, barY),
      Offset(cx + s * 0.14, barY),
      barPaint,
    );
  }

  void _paintPages(Canvas canvas, double cx, double cy, double s, double t) {
    if (t <= 0) return;

    final origin = Offset(cx - s * 0.28, cy - s * 0.02);
    final pagePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < 3; i++) {
      final local = Curves.easeOut.transform(((t - i * 0.12) / 0.7).clamp(0.0, 1.0));
      if (local <= 0) continue;

      final angle = (-0.55 - i * 0.22) * local; // fan open left-up
      final length = s * (0.22 + i * 0.03) * local;
      final width = s * 0.10;

      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(angle);

      pagePaint.color = Color.lerp(_primary, _mint, i / 2)!.withValues(alpha: 0.55 + 0.35 * local);

      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(-width / 2, -length, width, length),
        Radius.circular(s * 0.02),
      );
      canvas.drawRRect(r, pagePaint);
      final fold = Paint()
        ..color = pagePaint.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(-width * 0.15, -length * 0.75),
        Offset(width * 0.15, -length * 0.75),
        fold,
      );
      canvas.restore();
    }
  }

  void _paintChart(Canvas canvas, double cx, double cy, double s, double t) {
    if (t <= 0) return;

    final points = <Offset>[
      Offset(cx - s * 0.06, cy + s * 0.14),
      Offset(cx + s * 0.02, cy + s * 0.02),
      Offset(cx + s * 0.12, cy - s * 0.10),
      Offset(cx + s * 0.26, cy - s * 0.28),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final drawLen = metric.length * t;
    final drawn = metric.extractPath(0, drawLen);

    final line = Paint()
      ..color = _leaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(drawn, line);

    // Nodes along drawn portion
    final nodePaint = Paint()..color = _mint;
    final nodeStroke = Paint()
      ..color = _primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018;

    for (var i = 0; i < points.length; i++) {
      final along = i / (points.length - 1);
      if (t < along) break;
      final p = points[i];
      final r = s * (i == points.length - 1 ? 0.028 : 0.032);
      canvas.drawCircle(p, r, nodePaint);
      canvas.drawCircle(p, r, nodeStroke);
    }

    // Arrow head at tip once mostly drawn
    if (t > 0.72) {
      final tipT = ((t - 0.72) / 0.28).clamp(0.0, 1.0);
      final tip = points.last;
      final prev = points[points.length - 2];
      final ang = math.atan2(tip.dy - prev.dy, tip.dx - prev.dx);
      final arrowLen = s * 0.11 * tipT;

      final arrow = Path()
        ..moveTo(
          tip.dx - arrowLen * math.cos(ang - 0.55),
          tip.dy - arrowLen * math.sin(ang - 0.55),
        )
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - arrowLen * math.cos(ang + 0.55),
          tip.dy - arrowLen * math.sin(ang + 0.55),
        );

      final arrowPaint = Paint()
        ..color = _leaf.withValues(alpha: tipT)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.055
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(arrow, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AtlasMarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
