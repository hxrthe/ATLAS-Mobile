import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'atlas_skeleton.dart';

/// Pull-to-refresh: arrow rotates down→up while dragging, flies off on release,
/// then a skeleton strip shows while [onRefresh] runs.
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
    with TickerProviderStateMixin {
  static const _armDrag = 72.0;
  static const _maxDrag = 240.0;
  static const _cueHeight = 56.0;

  late final AnimationController _settle;
  late final AnimationController _leave;
  late final AnimationController _skeletonIn;

  double _dragOffset = 0;
  double _settleFrom = 0;
  bool _refreshing = false;
  bool _armedHaptic = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (!mounted || _leaving || _refreshing) return;
        final t = Curves.easeOutCubic.transform(_settle.value);
        setState(() => _dragOffset = _settleFrom * (1 - t));
      });
    _leave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _skeletonIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _settle.dispose();
    _leave.dispose();
    _skeletonIn.dispose();
    super.dispose();
  }

  double get _visualOffset {
    final d = _dragOffset.clamp(0.0, _maxDrag);
    return (1 - math.exp(-d / 90)) * 88;
  }

  bool get _armed => _dragOffset >= _armDrag;

  /// 0 = pointing down, 1 = pointing up.
  double get _arrowTurn {
    final visual = _visualOffset;
    return ((visual - 18) / 38).clamp(0.0, 1.0);
  }

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
    if (_refreshing || _leaving) return;
    if (_dragOffset >= _armDrag) {
      await _triggerRefresh();
    } else if (_dragOffset > 0) {
      _armedHaptic = false;
      _settleFrom = _dragOffset;
      _settle.forward(from: 0);
    }
  }

  Future<void> _triggerRefresh() async {
    if (_refreshing || _leaving) return;
    if (_settle.isAnimating) _settle.stop();

    setState(() {
      _leaving = true;
      _armedHaptic = false;
    });
    await _leave.forward(from: 0);
    if (!mounted) return;

    setState(() {
      _leaving = false;
      _refreshing = true;
      _dragOffset = 0;
    });
    _leave.reset();
    _skeletonIn.forward(from: 0);

    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        await _skeletonIn.reverse();
        if (mounted) {
          setState(() => _refreshing = false);
          _skeletonIn.reset();
        }
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
    if (!widget.enabled || _refreshing || _leaving) return false;
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
    final colors = context.atlas;
    final dragVisual = (_leaving || _refreshing) ? 0.0 : _visualOffset;
    final progress = (dragVisual / 56).clamp(0.0, 1.0);

    return ColoredBox(
      color: Colors.transparent,
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
              child: AnimatedBuilder(
                animation: Listenable.merge([_leave, _skeletonIn]),
                builder: (context, _) {
                  final leaveT = Curves.easeInCubic.transform(_leave.value);
                  final skeletonT =
                      Curves.easeOut.transform(_skeletonIn.value);
                  final contentShift = _refreshing
                      ? _cueHeight * skeletonT
                      : dragVisual;

                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Transform.translate(
                        offset: Offset(0, contentShift),
                        child: widget.child,
                      ),
                      if (dragVisual > 0 || _leaving)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: math.max(dragVisual, _cueHeight),
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: _leaving
                                  ? (1 - leaveT)
                                  : progress,
                              child: Transform.translate(
                                offset: Offset(
                                  0,
                                  _leaving ? -48 * leaveT : 0,
                                ),
                                child: Transform.scale(
                                  scale: _leaving
                                      ? (1 - 0.35 * leaveT)
                                      : (0.86 + 0.14 * progress),
                                  child: _PullArrowCue(
                                    turn: _arrowTurn,
                                    armed: _armed,
                                    color: _armed
                                        ? colors.primary
                                        : colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_refreshing)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: _cueHeight * skeletonT,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: skeletonT,
                              child: const _PullSkeletonCue(),
                            ),
                          ),
                        ),
                    ],
                  );
                },
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

class _PullArrowCue extends StatelessWidget {
  const _PullArrowCue({
    required this.turn,
    required this.armed,
    required this.color,
  });

  final double turn;
  final bool armed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform.rotate(
          // 0 → down (π), 1 → up (0)
          angle: math.pi * (1 - turn),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 28,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
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
    );
  }
}

class _PullSkeletonCue extends StatelessWidget {
  const _PullSkeletonCue();

  @override
  Widget build(BuildContext context) {
    return AtlasShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SkeletonBox(height: 10, radius: 6),
            SizedBox(height: 8),
            SkeletonBox(width: 160, height: 10, radius: 6),
          ],
        ),
      ),
    );
  }
}
