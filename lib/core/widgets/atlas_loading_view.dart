import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

enum AtlasLoadingLayout { home, courses, reports, list }

/// Full-page loader: ATLAS logo animation first, then a shimmer skeleton behind it.
class AtlasLoadingView extends StatefulWidget {
  const AtlasLoadingView({super.key, this.layout = AtlasLoadingLayout.home});

  final AtlasLoadingLayout layout;

  @override
  State<AtlasLoadingView> createState() => _AtlasLoadingViewState();
}

class _AtlasLoadingViewState extends State<AtlasLoadingView>
    with TickerProviderStateMixin {
  static const _background = Color(0xFFF4F6F9);
  static const _bone = Color(0xFFE2E8F0);

  late final AnimationController _intro;
  late final AnimationController _shimmer;
  late final AnimationController _pulse;

  late final Animation<double> _logoAppear;
  late final Animation<double> _skeletonOpacity;
  late final Animation<double> _logoLift;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _logoAppear = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
    );
    _skeletonOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.42, 0.85, curve: Curves.easeOut),
    );
    _logoLift = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    );

    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _shimmer.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: Stack(
        children: [
          FadeTransition(
            opacity: _skeletonOpacity,
            child: _Shimmer(animation: _shimmer, child: _buildSkeleton()),
          ),
          Center(child: _buildLogo()),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _pulse]),
      builder: (context, child) {
        final appear = 0.82 + (_logoAppear.value * 0.18);
        final pulse = 1.0 + (_pulse.value * 0.035);
        final lift = 1.0 - (_logoLift.value * 0.08);
        return Transform.scale(
          scale: appear * pulse * lift,
          child: Opacity(
            opacity: _logoAppear.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: const Offset(0, 22),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 7),
              child: Container(
                width: 48,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFB8C0C8).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Image.asset(
            'assets/images/atlas_loading.webp',
            height: 72,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => Image.asset(
              'assets/images/ATLAS_Mobile_Logo.png',
              height: 72,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      children: switch (widget.layout) {
        AtlasLoadingLayout.home => _homeBones(),
        AtlasLoadingLayout.courses => _coursesBones(),
        AtlasLoadingLayout.reports => _reportsBones(),
        AtlasLoadingLayout.list => _listBones(),
      },
    );
  }

  List<Widget> _homeBones() {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _boneBox(width: 132, height: 10, radius: 4),
              const SizedBox(height: 10),
              _boneBox(width: 176, height: 22, radius: 6),
            ],
          ),
          _boneBox(width: 56, height: 56, radius: 28),
        ],
      ),
      const SizedBox(height: 32),
      _boneBox(height: 214, radius: 24),
      const SizedBox(height: 32),
      Row(
        children: [
          _boneBox(width: 188, height: 11, radius: 4),
          const Spacer(),
          _boneBox(width: 78, height: 20, radius: 12),
        ],
      ),
      const SizedBox(height: 12),
      _boneBox(height: 74, radius: 12),
      const SizedBox(height: 10),
      _boneBox(height: 74, radius: 12),
      const SizedBox(height: 32),
      Row(
        children: [
          _boneBox(width: 8, height: 8, radius: 4),
          const SizedBox(width: 8),
          _boneBox(width: 118, height: 11, radius: 4),
        ],
      ),
      const SizedBox(height: 12),
      _eventBone(),
      const SizedBox(height: 14),
      _eventBone(),
      const SizedBox(height: 14),
      _eventBone(),
    ];
  }

  List<Widget> _coursesBones() {
    return [
      _boneBox(width: 148, height: 11, radius: 4),
      const SizedBox(height: 16),
      for (int i = 0; i < 5; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        _courseCardBone(),
      ],
    ];
  }

  List<Widget> _reportsBones() {
    return [
      _boneBox(width: 220, height: 11, radius: 4),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: _boneBox(height: 40, radius: 10)),
          const SizedBox(width: 8),
          Expanded(child: _boneBox(height: 40, radius: 10)),
          const SizedBox(width: 8),
          Expanded(child: _boneBox(height: 40, radius: 10)),
        ],
      ),
      const SizedBox(height: 20),
      _boneBox(height: 168, radius: 16),
      const SizedBox(height: 24),
      _boneBox(height: 148, radius: 16),
      const SizedBox(height: 24),
      _boneBox(width: 140, height: 11, radius: 4),
      const SizedBox(height: 12),
      _boneBox(height: 64, radius: 12),
      const SizedBox(height: 10),
      _boneBox(height: 64, radius: 12),
      const SizedBox(height: 10),
      _boneBox(height: 64, radius: 12),
    ];
  }

  List<Widget> _listBones() {
    return [
      for (int i = 0; i < 6; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        _boneBox(height: 72, radius: 14),
      ],
    ];
  }

  Widget _courseCardBone() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bone,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _boneBox(width: 40, height: 40, radius: 20, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _boneBox(width: 88, height: 14, radius: 4, color: Colors.white),
                const SizedBox(height: 8),
                _boneBox(
                  width: 160,
                  height: 11,
                  radius: 4,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventBone() {
    return Row(
      children: [
        _boneBox(width: 36, height: 36, radius: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _boneBox(width: double.infinity, height: 12, radius: 4),
              const SizedBox(height: 8),
              _boneBox(width: 140, height: 10, radius: 4),
            ],
          ),
        ),
      ],
    );
  }

  Widget _boneBox({
    double? width,
    required double height,
    double radius = 8,
    Color color = _bone,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.2 + (t * 2.4), -0.3),
              end: Alignment(-0.2 + (t * 2.4), 0.3),
              colors: const [
                Color(0xFFE2E8F0),
                Color(0xFFF8FAFC),
                Color(0xFFE2E8F0),
              ],
              stops: const [0.25, 0.5, 0.75],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: child,
    );
  }
}
