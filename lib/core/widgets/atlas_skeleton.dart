import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Sweeps a highlight across [child]; pair with [SkeletonBox] placeholders.
class AtlasShimmer extends StatefulWidget {
  const AtlasShimmer({super.key, required this.child});

  final Widget child;

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
    final c = context.atlas;
    final base = SkeletonBox.boneColor(c);
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        final t = _ctrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.2 + t * 2.4, -0.3),
            end: Alignment(-0.2 + t * 2.4, 0.3),
            colors: [base, Color.lerp(base, c.card, 0.7)!, base],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
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
        c.textSecondary.withValues(alpha: 0.14),
        c.card,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: boneColor(context.atlas),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Shimmering list of card placeholders: a leading badge and two text lines.
class AtlasSkeletonList extends StatelessWidget {
  const AtlasSkeletonList({
    super.key,
    this.count = 5,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 32),
    this.lines = 2,
    this.leadingSize = 36,
  });

  final int count;
  final EdgeInsets padding;
  final int lines;
  final double leadingSize;

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return AtlasShimmer(
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: leadingSize, height: leadingSize, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 13, width: i.isEven ? double.infinity : 200, radius: 4),
                    for (var l = 1; l < lines; l++) ...[
                      const SizedBox(height: 8),
                      SkeletonBox(height: 10, width: l.isOdd ? 150 : 110, radius: 4),
                    ],
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
