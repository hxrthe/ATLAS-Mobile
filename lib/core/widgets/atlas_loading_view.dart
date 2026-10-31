import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'atlas_skeleton.dart';

enum AtlasLoadingLayout { home, courses, reports, questions, scores, account }

/// Full-page loader: a skeleton in the shape of the screen, with the red
/// ATLAS loading gif centered in front of it.
class AtlasLoadingView extends StatelessWidget {
  const AtlasLoadingView({super.key, this.layout = AtlasLoadingLayout.home});

  final AtlasLoadingLayout layout;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.atlas.scaffold,
      child: Stack(
        children: [
          AtlasShimmer(child: _AtlasSkeleton(layout: layout)),
          const IgnorePointer(
            child: Center(child: AtlasLoadingMark()),
          ),
        ],
      ),
    );
  }
}

class _AtlasSkeleton extends StatelessWidget {
  const _AtlasSkeleton({required this.layout});

  final AtlasLoadingLayout layout;

  static const _washLight = [
    Color(0xFFF3B4B3),
    Color(0xFFF8D4D3),
    Color(0xFFFFF5F5),
  ];
  static const _washDark = [
    Color(0xFF6E1212),
    Color(0xFF0A0A0B),
    Color(0xFF050506),
  ];

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      AtlasLoadingLayout.home => _scroll(
          const EdgeInsets.fromLTRB(24, 24, 24, 56),
          _home(context),
        ),
      AtlasLoadingLayout.courses => _scroll(
          const EdgeInsets.fromLTRB(24, 24, 24, 56),
          _courses(context),
        ),
      AtlasLoadingLayout.reports => _reports(context),
      AtlasLoadingLayout.questions => _questions(context),
      AtlasLoadingLayout.scores => _scroll(
          const EdgeInsets.fromLTRB(16, 12, 16, 24),
          _scores(context),
        ),
      AtlasLoadingLayout.account => _scroll(
          const EdgeInsets.all(24),
          _account(context),
        ),
    };
  }

  Widget _scroll(EdgeInsets padding, List<Widget> children) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: children,
    );
  }

  List<Widget> _home(BuildContext context) {
    return [
      const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 156, height: 12, radius: 4),
              SizedBox(height: 8),
              SkeletonBox(width: 180, height: 26, radius: 6),
            ],
          ),
          SkeletonBox(width: 56, height: 56, radius: 28),
        ],
      ),
      const SizedBox(height: 32),
      _sessionCard(context),
      const SizedBox(height: 16),
      _quickExamCard(context),
      const SizedBox(height: 32),
      _sectionLabel(width: 210, trailingWidth: 78),
      const SizedBox(height: 12),
      _pendingCard(context),
      const SizedBox(height: 26),
      const SkeletonBox(width: 110, height: 11, radius: 4),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _courseTile(context)),
          const SizedBox(width: 10),
          Expanded(child: _courseTile(context)),
        ],
      ),
      const SizedBox(height: 32),
      _eventsCard(context),
    ];
  }

  List<Widget> _courses(BuildContext context) {
    return [
      const SkeletonBox(width: 108, height: 12, radius: 4),
      const SizedBox(height: 12),
      _quickExamCard(context),
      const SizedBox(height: 28),
      const SkeletonBox(width: 168, height: 12, radius: 4),
      const SizedBox(height: 16),
      for (var i = 0; i < 5; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        _courseCard(context),
      ],
    ];
  }

  Widget _reports(BuildContext context) {
    final c = context.atlas;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
          child: const Row(
            children: [
              Expanded(
                child: SkeletonBox(width: 230, height: 18, radius: 4),
              ),
              SizedBox(width: 8),
              SkeletonBox(width: 40, height: 40, radius: 12),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 56),
            children: [
              _reportCard(
                context,
                body: const Row(
                  children: [
                    SkeletonBox(width: 108, height: 108, radius: 54),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendBone(),
                          SizedBox(height: 10),
                          _LegendBone(width: 90),
                          SizedBox(height: 14),
                          SkeletonBox(width: 140, height: 12, radius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _reportCard(
                context,
                body: const Column(
                  children: [
                    _BarBone(),
                    SizedBox(height: 10),
                    _BarBone(labelWidth: 120),
                    SizedBox(height: 10),
                    _BarBone(labelWidth: 80),
                    SizedBox(height: 10),
                    _BarBone(labelWidth: 150),
                  ],
                ),
              ),
              _reportCard(
                context,
                body: const SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _HistBar(height: 36),
                      _HistBar(height: 58),
                      _HistBar(height: 92),
                      _HistBar(height: 110),
                      _HistBar(height: 74),
                      _HistBar(height: 48),
                      _HistBar(height: 28),
                      _HistBar(height: 16),
                    ],
                  ),
                ),
              ),
              _reportCard(
                context,
                body: const Column(
                  children: [
                    SkeletonBox(height: 180, width: double.infinity, radius: 12),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: SkeletonBox(height: 52, radius: 12)),
                        SizedBox(width: 6),
                        Expanded(child: SkeletonBox(height: 52, radius: 12)),
                        SizedBox(width: 6),
                        Expanded(child: SkeletonBox(height: 52, radius: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _questions(BuildContext context) {
    final c = context.atlas;
    return Column(
      children: [
        Container(
          color: c.card,
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: const Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SkeletonBox(width: 112, height: 36, radius: 20),
                        SizedBox(width: 8),
                        SkeletonBox(width: 122, height: 36, radius: 20),
                        SizedBox(width: 8),
                        SkeletonBox(width: 142, height: 36, radius: 20),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              SkeletonBox(width: 24, height: 24, radius: 6),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: 6,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _questionCard(context, withChoices: i.isEven),
          ),
        ),
      ],
    );
  }

  List<Widget> _scores(BuildContext context) {
    final c = context.atlas;
    return [
      const Row(
        children: [
          Expanded(child: SkeletonBox(height: 48, radius: 12)),
          SizedBox(width: 4),
          SkeletonBox(width: 40, height: 40, radius: 12),
        ],
      ),
      const SizedBox(height: 12),
      const Row(
        children: [
          Expanded(child: _StatBone()),
          SizedBox(width: 8),
          Expanded(child: _StatBone()),
          SizedBox(width: 8),
          Expanded(child: _StatBone()),
        ],
      ),
      const SizedBox(height: 8),
      const SkeletonBox(width: 180, height: 11, radius: 4),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              color: c.primary.withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: SkeletonBox(height: 12, radius: 4)),
                  SizedBox(width: 12),
                  Expanded(flex: 2, child: SkeletonBox(height: 12, radius: 4)),
                  SizedBox(width: 12),
                  Expanded(flex: 2, child: SkeletonBox(height: 12, radius: 4)),
                  SizedBox(width: 12),
                  Expanded(flex: 2, child: SkeletonBox(height: 12, radius: 4)),
                  SizedBox(width: 12),
                  Expanded(flex: 2, child: SkeletonBox(height: 12, radius: 4)),
                ],
              ),
            ),
            for (var i = 0; i < 7; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(height: 13, width: double.infinity, radius: 4),
                          SizedBox(height: 4),
                          SkeletonBox(height: 10, width: 72, radius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(flex: 2, child: SkeletonBox(height: 12, radius: 4)),
                    const SizedBox(width: 12),
                    const Expanded(flex: 2, child: SkeletonBox(height: 12, radius: 4)),
                    const SizedBox(width: 12),
                    const Expanded(flex: 2, child: SkeletonBox(height: 12, radius: 4)),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SkeletonBox(
                          height: 22,
                          width: i.isEven ? 52 : 44,
                          radius: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _account(BuildContext context) {
    return [
      const SkeletonBox(width: 108, height: 12, radius: 4),
      const SizedBox(height: 16),
      _surface(
        context,
        radius: 12,
        child: const Row(
          children: [
            SkeletonBox(width: 60, height: 60, radius: 30),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 18, width: 160, radius: 4),
                  SizedBox(height: 8),
                  SkeletonBox(height: 14, width: 200, radius: 4),
                  SizedBox(height: 8),
                  SkeletonBox(height: 10, width: 64, radius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),
      const SkeletonBox(width: 148, height: 12, radius: 4),
      const SizedBox(height: 16),
      _settingTile(context),
      const SizedBox(height: 12),
      _settingTile(context, trailingWidth: 52, trailingRadius: 16),
    ];
  }

  Widget _sectionLabel({required double width, double trailingWidth = 0}) {
    return Row(
      children: [
        SkeletonBox(width: width, height: 11, radius: 4),
        const Spacer(),
        if (trailingWidth > 0)
          SkeletonBox(width: trailingWidth, height: 20, radius: 12),
      ],
    );
  }

  Widget _sessionCard(BuildContext context) {
    final dark = context.isDarkTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark ? _washDark : _washLight,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: dark
            ? null
            : Border.all(color: const Color(0xFFE24B4A).withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: (dark ? const Color(0xFF6E1212) : const Color(0xFFAA2423))
                .withValues(alpha: dark ? 0.45 : 0.22),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 148, height: 28, radius: 6),
              Spacer(),
              SkeletonBox(width: 118, height: 22, radius: 11),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              SkeletonBox(width: 170, height: 14, radius: 4),
              SizedBox(width: 8),
              SkeletonBox(width: 52, height: 16, radius: 6),
            ],
          ),
          SizedBox(height: 14),
          SkeletonBox(width: double.infinity, height: 44, radius: 12),
        ],
      ),
    );
  }

  Widget _quickExamCard(BuildContext context) {
    return _surface(
      context,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 40, height: 40, radius: 20),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 16, width: 120, radius: 4),
                    SizedBox(height: 6),
                    SkeletonBox(height: 12, width: 210, radius: 4),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 40, radius: 12)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 40, radius: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(BuildContext context) {
    final c = context.atlas;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.card,
          border: Border(left: BorderSide(color: c.primary, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 48, height: 48, radius: 12),
                SizedBox(width: 14),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(height: 14, width: 140, radius: 4),
                  ),
                ),
                SizedBox(width: 6),
                SkeletonBox(width: 52, height: 20, radius: 6),
                SizedBox(width: 8),
                SkeletonBox(width: 34, height: 34, radius: 17),
              ],
            ),
            SizedBox(height: 12),
            _SectionProgressBone(),
            SizedBox(height: 8),
            _SectionProgressBone(),
          ],
        ),
      ),
    );
  }

  Widget _courseTile(BuildContext context) {
    final dark = context.isDarkTheme;
    return Container(
      height: 128,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark ? _washDark : _washLight,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: dark
            ? null
            : Border.all(color: const Color(0xFFE24B4A).withValues(alpha: 0.7)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 72, height: 16, radius: 4),
              Spacer(),
              SkeletonBox(width: 28, height: 28, radius: 14),
            ],
          ),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 12, radius: 4),
          SizedBox(height: 6),
          SkeletonBox(width: 90, height: 12, radius: 4),
          Spacer(),
          SkeletonBox(width: 48, height: 12, radius: 4),
        ],
      ),
    );
  }

  Widget _eventsCard(BuildContext context) {
    final c = context.atlas;
    return _surface(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              SkeletonBox(width: 10, height: 10, radius: 5),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 11, radius: 4),
                    SizedBox(height: 6),
                    SkeletonBox(width: 180, height: 12, radius: 4),
                  ],
                ),
              ),
              SkeletonBox(width: 34, height: 34, radius: 17),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) Divider(height: 1, color: c.divider),
            const _ScanEventBone(),
          ],
        ],
      ),
    );
  }

  Widget _courseCard(BuildContext context) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.primary, width: 2),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 40, height: 40, radius: 20),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 88, height: 16, radius: 4),
                SizedBox(height: 6),
                SkeletonBox(width: 170, height: 13, radius: 4),
              ],
            ),
          ),
          SizedBox(width: 8),
          SkeletonBox(width: 8, height: 14, radius: 2),
        ],
      ),
    );
  }

  Widget _reportCard(BuildContext context, {required Widget body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: _surface(
        context,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 160, height: 16, radius: 4),
                      SizedBox(height: 6),
                      SkeletonBox(width: 120, height: 12, radius: 4),
                    ],
                  ),
                ),
                SkeletonBox(width: 34, height: 34, radius: 17),
              ],
            ),
            const SizedBox(height: 14),
            body,
          ],
        ),
      ),
    );
  }

  Widget _questionCard(BuildContext context, {required bool withChoices}) {
    return _surface(
      context,
      radius: 12,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 32, height: 32, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 80, height: 11, radius: 4),
                const SizedBox(height: 6),
                const SkeletonBox(height: 14, width: double.infinity, radius: 4),
                const SizedBox(height: 6),
                const SkeletonBox(height: 14, width: 220, radius: 4),
                if (withChoices) ...[
                  const SizedBox(height: 8),
                  const SkeletonBox(height: 12, width: 160, radius: 4),
                  const SizedBox(height: 4),
                  const SkeletonBox(height: 12, width: 140, radius: 4),
                  const SizedBox(height: 4),
                  const SkeletonBox(height: 12, width: 150, radius: 4),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const SkeletonBox(width: 30, height: 30, radius: 15),
        ],
      ),
    );
  }

  Widget _settingTile(
    BuildContext context, {
    double trailingWidth = 14,
    double trailingRadius = 2,
  }) {
    return _surface(
      context,
      radius: 12,
      child: Row(
        children: [
          const SkeletonBox(width: 24, height: 24, radius: 6),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 14, width: 140, radius: 4),
                SizedBox(height: 6),
                SkeletonBox(height: 12, width: 190, radius: 4),
              ],
            ),
          ),
          SkeletonBox(
            width: trailingWidth,
            height: trailingWidth > 20 ? 28 : 14,
            radius: trailingRadius,
          ),
        ],
      ),
    );
  }

  Widget _surface(
    BuildContext context, {
    required Widget child,
    double radius = 16,
    EdgeInsets padding = const EdgeInsets.all(16),
    Border? border,
  }) {
    final c = context.atlas;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LegendBone extends StatelessWidget {
  const _LegendBone({this.width = 110});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SkeletonBox(width: 10, height: 10, radius: 5),
        const SizedBox(width: 8),
        SkeletonBox(width: width, height: 13, radius: 4),
      ],
    );
  }
}

class _BarBone extends StatelessWidget {
  const _BarBone({this.labelWidth = 100});

  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SkeletonBox(width: labelWidth, height: 12, radius: 4),
        const SizedBox(width: 10),
        const Expanded(child: SkeletonBox(height: 10, radius: 5)),
      ],
    );
  }
}

class _HistBar extends StatelessWidget {
  const _HistBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SkeletonBox(height: height, width: double.infinity, radius: 4),
        ),
      ),
    );
  }
}

class _StatBone extends StatelessWidget {
  const _StatBone();

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: const Column(
        children: [
          SkeletonBox(width: 48, height: 17, radius: 4),
          SizedBox(height: 6),
          SkeletonBox(width: 56, height: 11, radius: 4),
        ],
      ),
    );
  }
}

class _SectionProgressBone extends StatelessWidget {
  const _SectionProgressBone();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            SkeletonBox(width: 70, height: 13, radius: 4),
            Spacer(),
            SkeletonBox(width: 88, height: 12, radius: 4),
          ],
        ),
        SizedBox(height: 6),
        SkeletonBox(width: double.infinity, height: 6, radius: 3),
      ],
    );
  }
}

class _ScanEventBone extends StatelessWidget {
  const _ScanEventBone();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 18, height: 18, radius: 9),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SkeletonBox(height: 13, radius: 4),
                    ),
                    SizedBox(width: 8),
                    SkeletonBox(width: 42, height: 13, radius: 4),
                    SizedBox(width: 6),
                    SkeletonBox(width: 46, height: 18, radius: 10),
                  ],
                ),
                SizedBox(height: 6),
                SkeletonBox(width: 190, height: 12, radius: 4),
                SizedBox(height: 4),
                SkeletonBox(width: 64, height: 11, radius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
