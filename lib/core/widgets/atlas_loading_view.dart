import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
            errorBuilder: (_, _, _) => SvgPicture.asset(
              'assets/images/atlas_logo_mark.svg',
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
      _sessionCardBone(),
      const SizedBox(height: 16),
      _quickExamCardBone(),
      const SizedBox(height: 32),
      _headerBone(titleWidth: 188, badgeWidth: 72),
      const SizedBox(height: 12),
      _pendingCardBone(),
      const SizedBox(height: 26),
      _boneBox(width: 110, height: 11, radius: 4),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _courseTileBone()),
          const SizedBox(width: 10),
          Expanded(child: _courseTileBone()),
        ],
      ),
      const SizedBox(height: 32),
      _eventsCardBone(),
    ];
  }

  Widget _headerBone({required double titleWidth, double badgeWidth = 0}) {
    return Row(
      children: [
        _boneBox(width: titleWidth, height: 11, radius: 4),
        const Spacer(),
        if (badgeWidth > 0) _boneBox(width: badgeWidth, height: 20, radius: 12),
      ],
    );
  }

  /// Course code + status pill, title + assessment-type tag, then the scan button.
  Widget _sessionCardBone() {
    return _cardBone(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      children: [
        Row(
          children: [
            _whiteBone(width: 120, height: 28, radius: 6),
            const Spacer(),
            _whiteBone(width: 116, height: 22, radius: 11),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _whiteBone(width: 170, height: 12, radius: 4),
            const SizedBox(width: 8),
            _whiteBone(width: 52, height: 16, radius: 6),
          ],
        ),
        const SizedBox(height: 14),
        _whiteBone(width: double.infinity, height: 44, radius: 12),
      ],
    );
  }

  /// Quick exams entry: icon, title + counts, then New / Open buttons.
  Widget _quickExamCardBone() {
    return _cardBone(
      children: [
        Row(
          children: [
            _whiteBone(width: 40, height: 40, radius: 20),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _whiteBone(width: 96, height: 15, radius: 4),
                const SizedBox(height: 6),
                _whiteBone(width: 170, height: 11, radius: 4),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _whiteBone(height: 40, radius: 20)),
            const SizedBox(width: 10),
            Expanded(child: _whiteBone(height: 40, radius: 20)),
          ],
        ),
      ],
    );
  }

  /// Exam icon, name, READY tag + info button, then one scanned/total bar per section.
  Widget _pendingCardBone() {
    return _cardBone(
      children: [
        Row(
          children: [
            _whiteBone(width: 48, height: 48, radius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _whiteBone(width: 140, height: 13, radius: 4),
              ),
            ),
            const SizedBox(width: 6),
            _whiteBone(width: 46, height: 20, radius: 6),
            const SizedBox(width: 8),
            _whiteBone(width: 34, height: 34, radius: 17),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              _whiteBone(width: 70, height: 12, radius: 4),
              const Spacer(),
              _whiteBone(width: 76, height: 11, radius: 4),
            ],
          ),
          const SizedBox(height: 6),
          _whiteBone(width: double.infinity, height: 6, radius: 3),
        ],
      ],
    );
  }

  /// "Other courses" tile: code + swap icon, title lines, then "Switch".
  Widget _courseTileBone() {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bone,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _whiteBone(width: 72, height: 16, radius: 4),
              const Spacer(),
              _whiteBone(width: 28, height: 28, radius: 14),
            ],
          ),
          const SizedBox(height: 8),
          _whiteBone(width: double.infinity, height: 10, radius: 4),
          const SizedBox(height: 6),
          _whiteBone(width: 90, height: 10, radius: 4),
          const Spacer(),
          _whiteBone(width: 44, height: 11, radius: 4),
        ],
      ),
    );
  }

  /// "System events" header with info button, then recent scan rows.
  Widget _eventsCardBone() {
    return _cardBone(
      children: [
        Row(
          children: [
            _whiteBone(width: 10, height: 10, radius: 5),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _whiteBone(width: 110, height: 11, radius: 4),
                const SizedBox(height: 6),
                _whiteBone(width: 170, height: 10, radius: 4),
              ],
            ),
            const Spacer(),
            _whiteBone(width: 34, height: 34, radius: 17),
          ],
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < 3; i++) _scanEventBone(),
      ],
    );
  }

  /// Status icon; student + score + pass pill; exam — course; time ago.
  Widget _scanEventBone() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _whiteBone(width: 18, height: 18, radius: 9),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _whiteBone(width: 120, height: 12, radius: 4),
                    const Spacer(),
                    _whiteBone(width: 36, height: 12, radius: 4),
                    const SizedBox(width: 6),
                    _whiteBone(width: 46, height: 18, radius: 10),
                  ],
                ),
                const SizedBox(height: 6),
                _whiteBone(width: 180, height: 10, radius: 4),
                const SizedBox(height: 5),
                _whiteBone(width: 64, height: 9, radius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardBone({
    required List<Widget> children,
    double radius = 16,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _bone,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _whiteBone({
    double? width,
    required double height,
    double radius = 8,
  }) => _boneBox(
    width: width,
    height: height,
    radius: radius,
    color: Colors.white,
  );

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
      Row(
        children: [
          _boneBox(width: 230, height: 20, radius: 6),
          const Spacer(),
          _boneBox(width: 40, height: 40, radius: 12),
        ],
      ),
      const SizedBox(height: 20),
      _reportCardBone(bodyHeight: 120),
      const SizedBox(height: 16),
      _reportCardBone(bodyHeight: 110),
      const SizedBox(height: 16),
      _reportCardBone(bodyHeight: 130),
      const SizedBox(height: 16),
      _reportCardBone(bodyHeight: 150),
      const SizedBox(height: 16),
      _reportCardBone(bodyHeight: 70),
    ];
  }

  /// Compact report card: title + info button, then its illustration.
  Widget _reportCardBone({required double bodyHeight}) {
    return _cardBone(
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _whiteBone(width: 140, height: 13, radius: 4),
                const SizedBox(height: 6),
                _whiteBone(width: 100, height: 9, radius: 4),
              ],
            ),
            const Spacer(),
            _whiteBone(width: 30, height: 30, radius: 15),
          ],
        ),
        const SizedBox(height: 16),
        _whiteBone(width: double.infinity, height: bodyHeight, radius: 12),
      ],
    );
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
