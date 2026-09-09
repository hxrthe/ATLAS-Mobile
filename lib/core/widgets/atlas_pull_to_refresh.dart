import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pull-to-refresh that displaces the page and shows parallel lines + a down
/// arrow while dragging. No spinner — screens already show [AtlasLoadingView].
class AtlasPullToRefresh extends StatefulWidget {
  const AtlasPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.enabled = true,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final bool enabled;

  @override
  State<AtlasPullToRefresh> createState() => _AtlasPullToRefreshState();
}

class _AtlasPullToRefreshState extends State<AtlasPullToRefresh>
    with SingleTickerProviderStateMixin {
  static const _armDrag = 72.0;
  static const _maxDrag = 240.0;

  late final AnimationController _settle;

  double _dragOffset = 0;
  double _settleFrom = 0;
  bool _refreshing = false;
  bool _armedHaptic = false;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (!mounted) return;
        final t = Curves.easeOutCubic.transform(_settle.value);
        setState(() => _dragOffset = _settleFrom * (1 - t));
      });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  double get _visualOffset {
    final d = _dragOffset.clamp(0.0, _maxDrag);
    return (1 - math.exp(-d / 90)) * 88;
  }

  bool get _armed => _dragOffset >= _armDrag;

  void _setDrag(double next) {
    if (_settle.isAnimating) _settle.stop();
    final clamped = next.clamp(0.0, _maxDrag);
    if ((clamped - _dragOffset).abs() < 0.3) return;
    final nowArmed = clamped >= _armDrag;
    if (nowArmed && !_armedHaptic) {
      HapticFeedback.selectionClick();
      _armedHaptic = true;
    } else if (!nowArmed) {
      _armedHaptic = false;
    }
    setState(() => _dragOffset = clamped);
  }

  Future<void> _onFingerUp() async {
    if (_refreshing) return;
    if (_dragOffset >= _armDrag) {
      await _triggerRefresh();
    } else if (_dragOffset > 0) {
      _armedHaptic = false;
      _settleFrom = _dragOffset;
      _settle.forward(from: 0);
    }
  }

  Future<void> _triggerRefresh() async {
    if (_refreshing) return;
    if (_settle.isAnimating) _settle.stop();
    setState(() {
      _refreshing = true;
      _dragOffset = 0;
      _armedHaptic = false;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  void didUpdateWidget(AtlasPullToRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _dragOffset > 0) {
      _dragOffset = 0;
      _armedHaptic = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (!widget.enabled || _refreshing) return false;
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is OverscrollNotification) {
      if (notification.dragDetails == null) return false;
      _setDrag(_dragOffset - notification.overscroll);
    } else if (notification is ScrollUpdateNotification) {
      if (notification.metrics.extentBefore > 0.5) {
        if (_dragOffset > 0) _setDrag(0);
      } else if (notification.scrollDelta != null &&
          notification.scrollDelta! < 0 &&
          notification.dragDetails != null) {
        _setDrag(_dragOffset - notification.scrollDelta!);
      }
    } else if (notification is ScrollEndNotification) {
      _onFingerUp();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final visual = _refreshing ? 0.0 : _visualOffset;
    final progress = (visual / 56).clamp(0.0, 1.0);

    return ColoredBox(
      color: const Color(0xFFF4F6F9),
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: (notification) {
          notification.disallowIndicator();
          return true;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ScrollConfiguration(
            behavior: const _PullScrollBehavior(),
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Transform.translate(
                    offset: Offset(0, visual),
                    child: widget.child,
                  ),
                  if (visual > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: visual,
                      child: IgnorePointer(
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Opacity(
                              opacity: progress,
                              child: _PullToRefreshCue(
                                progress: progress,
                                armed: _armed,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PullScrollBehavior extends ScrollBehavior {
  const _PullScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const AlwaysScrollableScrollPhysics(
      parent: ClampingScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _PullToRefreshCue extends StatelessWidget {
  const _PullToRefreshCue({
    required this.progress,
    required this.armed,
  });

  final double progress;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final color = armed ? const Color(0xFF8B1515) : const Color(0xFF8391A1);
    return Transform.scale(
      scale: 0.86 + (0.14 * progress),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 88,
            height: 26,
            child: CustomPaint(
              painter: _ParallelLinesArrowPainter(color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            armed ? 'Release to refresh' : 'Pull to refresh',
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: TextStyle(
              fontSize: 11,
              height: 1.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParallelLinesArrowPainter extends CustomPainter {
  const _ParallelLinesArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const inset = 2.0;
    final y1 = size.height * 0.22;
    final y2 = size.height * 0.78;
    canvas.drawLine(Offset(inset, y1), Offset(size.width - inset, y1), paint);
    canvas.drawLine(Offset(inset, y2), Offset(size.width - inset, y2), paint);

    final midX = size.width / 2;
    final arrowTop = y1 + 5;
    final arrowBottom = y2 - 4;
    canvas.drawLine(
      Offset(midX, arrowTop),
      Offset(midX, arrowBottom),
      paint,
    );
    final head = Path()
      ..moveTo(midX - 6, arrowBottom - 7)
      ..lineTo(midX, arrowBottom)
      ..lineTo(midX + 6, arrowBottom - 7);
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(covariant _ParallelLinesArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
