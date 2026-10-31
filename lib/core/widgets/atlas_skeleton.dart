import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Green-on-transparent ATLAS loading gif, tinted to the brand red.
class AtlasLoadingMark extends StatelessWidget {
  const AtlasLoadingMark({super.key, this.height = 88});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(
        Color(0xFFAA2423),
        BlendMode.srcIn,
      ),
      child: Image.asset(
        'assets/images/atlas_loading.gif',
        height: height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Shares one shimmer clock. Bones ([SkeletonBox]) sweep on their own so
/// card chrome around them keeps the real screen's colors and borders.
class AtlasShimmer extends StatefulWidget {
  const AtlasShimmer({
    super.key,
    required this.child,
    this.showMark = false,
  });

  final Widget child;

  /// Red loading gif centered over this skeleton when it is tall enough.
  final bool showMark;

  @override
  State<AtlasShimmer> createState() => _AtlasShimmerState();
}

class _AtlasShimmerState extends State<AtlasShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoped = _ShimmerScope(animation: _ctrl, child: widget.child);
    if (!widget.showMark) return scoped;
    return Stack(
      children: [
        scoped,
        const Positioned.fill(
          child: IgnorePointer(
            child: _FittedLoadingMark(),
          ),
        ),
      ],
    );
  }
}

/// Hides the gif on a one-line bone; scales it down on a short field.
class _FittedLoadingMark extends StatelessWidget {
  const _FittedLoadingMark();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        if (!h.isFinite || h < 40) return const SizedBox.shrink();
        final size = (h * 0.42).clamp(36.0, 88.0);
        return Center(child: AtlasLoadingMark(height: size));
      },
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;
  }

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) =>
      animation != oldWidget.animation;
}

/// A rounded placeholder block. Use inside an [AtlasShimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  static Color boneColor(AtlasColors c) => Color.alphaBlend(
        c.textSecondary.withValues(alpha: 0.16),
        c.card,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final base = boneColor(c);
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    final animation = _ShimmerScope.maybeOf(context);
    if (animation == null) return box;
    final highlight = Color.lerp(base, c.card, context.isDarkTheme ? 0.55 : 0.72)!;
    return AnimatedBuilder(
      animation: animation,
      child: box,
      builder: (context, child) {
        final t = animation.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.2 + t * 2.4, -0.3),
            end: Alignment(-0.2 + t * 2.4, 0.3),
            colors: [base, highlight, base],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

enum AtlasSkeletonKind { examCards, scanTiles }

/// Shimmering list whose rows match the cards they stand in for.
class AtlasSkeletonList extends StatelessWidget {
  const AtlasSkeletonList({
    super.key,
    this.count = 5,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 32),
    this.kind = AtlasSkeletonKind.scanTiles,
  });

  final int count;
  final EdgeInsets padding;
  final AtlasSkeletonKind kind;

  @override
  Widget build(BuildContext context) {
    return AtlasShimmer(
      showMark: true,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => switch (kind) {
          AtlasSkeletonKind.examCards => const _ExamCardBone(),
          AtlasSkeletonKind.scanTiles => const _ScanTileBone(),
        },
      ),
    );
  }
}

class _ExamCardBone extends StatelessWidget {
  const _ExamCardBone();

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 40, height: 40, radius: 20),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 15, width: double.infinity, radius: 4),
                SizedBox(height: 6),
                SkeletonBox(height: 12, width: 190, radius: 4),
                SizedBox(height: 6),
                SkeletonBox(height: 12, width: 88, radius: 4),
              ],
            ),
          ),
          SizedBox(width: 10),
          SkeletonBox(width: 8, height: 14, radius: 2),
        ],
      ),
    );
  }
}

class _ScanTileBone extends StatelessWidget {
  const _ScanTileBone();

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 36, height: 36, radius: 18),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14, width: double.infinity, radius: 4),
                SizedBox(height: 6),
                SkeletonBox(height: 12, width: 200, radius: 4),
              ],
            ),
          ),
          SizedBox(width: 8),
          SkeletonBox(width: 52, height: 26, radius: 13),
        ],
      ),
    );
  }
}
