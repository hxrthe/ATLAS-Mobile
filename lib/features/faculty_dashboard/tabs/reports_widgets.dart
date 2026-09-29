import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

const bloomLevels = [
  'Remember',
  'Understand',
  'Apply',
  'Analyze',
  'Evaluate',
  'Create',
];
const bloomShort = {
  'Remember': 'Rem',
  'Understand': 'Und',
  'Apply': 'App',
  'Analyze': 'Ana',
  'Evaluate': 'Eva',
  'Create': 'Cre',
};

const masteredColor = Color(0xFF2E9E5B);
const nearColor = Color(0xFFF2A93B);
const notMasteredColor = Color(0xFFD9534F);
const noDataColor = Color(0xFFB8C0CC);

Color masteryColor(double? pct, {double mastered = 75, double near = 50}) {
  if (pct == null) return noDataColor;
  if (pct >= mastered) return masteredColor;
  if (pct >= near) return nearColor;
  return notMasteredColor;
}

Color decisionColor(String decision) {
  switch (decision) {
    case 'Retain':
      return masteredColor;
    case 'Discard':
      return notMasteredColor;
    default:
      return nearColor;
  }
}

double? asDouble(dynamic v) => v is num ? v.toDouble() : null;

String fmtNum(num? v, {int decimals = 1}) {
  if (v == null) return '—';
  return v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(decimals);
}

/// White rounded card used by every report section.
class ReportCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const ReportCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: c.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Large ring gauge (e.g. pass rate).
class RingGauge extends StatelessWidget {
  final double? percent;
  final Color color;
  final double size;
  final String caption;

  const RingGauge({
    super.key,
    required this.percent,
    required this.color,
    required this.caption,
    this.size = 108,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: (percent ?? 0) / 100,
          color: color,
          track: c.border,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                percent == null ? '—' : '${percent!.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(caption,
                  style: TextStyle(fontSize: 10.5, color: c.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;

  _RingPainter({required this.fraction, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// Small stat tile.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? color;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.cardMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 11, color: c.textSecondary)),
                ),
                if (onTap != null)
                  Icon(Icons.edit, size: 13, color: c.textSecondary),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color ?? c.textPrimary,
              ),
            ),
            if (hint != null)
              Text(hint!,
                  style: TextStyle(fontSize: 10.5, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal stacked passed/failed bars per group (section, subject or exam).
class PassRateBars extends StatelessWidget {
  final List<Map<String, dynamic>> groups;
  final ValueChanged<Map<String, dynamic>>? onTap;

  const PassRateBars({super.key, required this.groups, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    if (groups.isEmpty) {
      return Text('No scanned papers for this filter.',
          style: TextStyle(color: c.textSecondary, fontSize: 13));
    }
    return Column(
      children: groups.map((g) {
        final count = (g['count'] as num?)?.toInt() ?? 0;
        final passed = (g['passed'] as num?)?.toInt() ?? 0;
        final rate = asDouble(g['pass_rate']) ?? 0;
        final mean = asDouble(g['mean_percent']);
        final sub = [
          if ((g['course_title'] ?? '').toString().isNotEmpty) g['course_title'],
          if ((g['course_code'] ?? '').toString().isNotEmpty) g['course_code'],
          if ((g['grade_level'] ?? '').toString().isNotEmpty &&
              g['grade_level'] != 'Unassigned')
            g['grade_level'],
        ].join(' · ');
        return InkWell(
          onTap: onTap == null ? null : () => onTap!(g),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (g['label'] ?? '').toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: c.textPrimary,
                            ),
                          ),
                          if (sub.isNotEmpty)
                            Text(sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: c.textSecondary)),
                        ],
                      ),
                    ),
                    Text(
                      '${rate.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: rate >= 50 ? masteredColor : notMasteredColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 12,
                    child: Row(
                      children: [
                        if (passed > 0)
                          Expanded(
                            flex: passed,
                            child: Container(color: masteredColor),
                          ),
                        if (count - passed > 0)
                          Expanded(
                            flex: count - passed,
                            child: Container(
                                color: notMasteredColor.withValues(alpha: 0.75)),
                          ),
                        if (count == 0)
                          Expanded(child: Container(color: c.border)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$passed passed · ${count - passed} failed · n=$count'
                  '${mean != null ? ' · mean ${mean.toStringAsFixed(1)}%' : ''}',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Column histogram of score percentages with the passing mark overlaid.
class ScoreHistogram extends StatelessWidget {
  final List<Map<String, dynamic>> buckets;
  final double? passingPercent;

  const ScoreHistogram({super.key, required this.buckets, this.passingPercent});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final maxCount = buckets.fold<int>(
        0, (m, b) => math.max(m, (b['count'] as num?)?.toInt() ?? 0));
    const chartHeight = 130.0;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Column(
        children: [
          SizedBox(
            height: chartHeight + 18,
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: buckets.map((b) {
                    final count = (b['count'] as num?)?.toInt() ?? 0;
                    final from = (b['from'] as num?)?.toDouble() ?? 0;
                    final h = maxCount == 0 ? 0.0 : count / maxCount * chartHeight;
                    final passingBucket =
                        passingPercent != null && from >= passingPercent! - 0.001;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(count == 0 ? '' : '$count',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: c.textPrimary)),
                            const SizedBox(height: 2),
                            Container(
                              height: math.max(h, count > 0 ? 3 : 0),
                              decoration: BoxDecoration(
                                color: passingBucket
                                    ? masteredColor
                                    : c.primary.withValues(alpha: 0.75),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (passingPercent != null)
                  Positioned(
                    left: (width * passingPercent! / 100).clamp(0, width - 2),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: c.textPrimary.withValues(alpha: 0.55)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: buckets
                .map((b) => Expanded(
                      child: Text(
                        fmtNum(b['from'] as num?),
                        textAlign: TextAlign.left,
                        style: TextStyle(fontSize: 9.5, color: c.textSecondary),
                      ),
                    ))
                .toList(),
          ),
          if (passingPercent != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(width: 12, height: 2, color: c.textPrimary.withValues(alpha: 0.55)),
                const SizedBox(width: 6),
                Text('Passing mark ${fmtNum(passingPercent)}%',
                    style: TextStyle(fontSize: 11, color: c.textSecondary)),
                const SizedBox(width: 14),
                Container(width: 10, height: 10, color: masteredColor),
                const SizedBox(width: 6),
                Text('At/above passing',
                    style: TextStyle(fontSize: 11, color: c.textSecondary)),
              ],
            ),
          ],
        ],
      );
    });
  }
}

/// Difficulty (x) vs discrimination (y) map; the green zone is the "retain" region.
class ItemQuadrantChart extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final ValueChanged<int>? onTapItem;

  const ItemQuadrantChart({super.key, required this.items, this.onTapItem});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return AspectRatio(
      aspectRatio: 1.25,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: onTapItem == null
              ? null
              : (d) {
                  final hit = _ItemQuadrantPainter.itemAt(items, size, d.localPosition);
                  if (hit != null) onTapItem!(hit);
                },
          child: CustomPaint(
            size: size,
            painter: _ItemQuadrantPainter(
              items: items,
              axis: c.textSecondary,
              grid: c.border,
              text: c.textPrimary,
            ),
          ),
        );
      }),
    );
  }
}

class _ItemQuadrantPainter extends CustomPainter {
  final List<Map<String, dynamic>> items;
  final Color axis;
  final Color grid;
  final Color text;

  static const _left = 34.0;
  static const _bottom = 30.0;
  static const _top = 8.0;
  static const _right = 8.0;
  static const _dMin = -0.4;
  static const _dMax = 1.0;

  _ItemQuadrantPainter({
    required this.items,
    required this.axis,
    required this.grid,
    required this.text,
  });

  static Offset _pos(Size s, double p, double d) {
    final w = s.width - _left - _right;
    final h = s.height - _top - _bottom;
    final x = _left + p.clamp(0, 1) * w;
    final y = _top + (1 - (d.clamp(_dMin, _dMax) - _dMin) / (_dMax - _dMin)) * h;
    return Offset(x, y);
  }

  static int? itemAt(List<Map<String, dynamic>> items, Size s, Offset at) {
    int? best;
    var bestDist = 18.0;
    for (final it in items) {
      final o = _pos(s, asDouble(it['difficulty']) ?? 0, asDouble(it['discrimination']) ?? 0);
      final dist = (o - at).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = (it['item_number'] as num).toInt();
      }
    }
    return best;
  }

  void _label(Canvas canvas, String s, Offset at, {double size = 9.5, Color? color, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color ?? axis)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final zone = Rect.fromPoints(_pos(size, 0.30, _dMax), _pos(size, 0.70, 0.30));
    canvas.drawRect(zone, Paint()..color = masteredColor.withValues(alpha: 0.12));
    _label(canvas, 'Ideal zone', zone.topLeft + const Offset(4, 3),
        color: masteredColor, size: 9);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final p in [0.0, 0.3, 0.7, 1.0]) {
      canvas.drawLine(_pos(size, p, _dMin), _pos(size, p, _dMax), gridPaint);
      _label(canvas, p.toStringAsFixed(1), _pos(size, p, _dMin) + const Offset(-8, 4));
    }
    for (final d in [-0.4, 0.0, 0.2, 0.3, 0.4, 1.0]) {
      final paint = Paint()
        ..color = d == 0 ? axis : grid
        ..strokeWidth = d == 0 ? 1.2 : 1;
      canvas.drawLine(_pos(size, 0, d), _pos(size, 1, d), paint);
      _label(canvas, d.toStringAsFixed(1), _pos(size, 0, d) + const Offset(-30, -6));
    }
    _label(canvas, 'Difficulty index P  (harder ← → easier)',
        Offset(size.width / 2 + _left / 2, size.height - 7),
        center: true, size: 10, color: text);

    for (final it in items) {
      final o = _pos(size, asDouble(it['difficulty']) ?? 0, asDouble(it['discrimination']) ?? 0);
      final color = decisionColor((it['decision'] ?? '').toString());
      canvas.drawCircle(o, 8, Paint()..color = color.withValues(alpha: 0.85));
      canvas.drawCircle(
          o,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white
            ..strokeWidth = 1.2);
      _label(canvas, '${it['item_number']}', o,
          size: 8, color: Colors.white, center: true);
    }
  }

  @override
  bool shouldRepaint(_ItemQuadrantPainter old) => old.items != items || old.axis != axis;
}

const bloomLevelColors = {
  'Remember': Color(0xFFE05A47),
  'Understand': Color(0xFFF08A24),
  'Apply': Color(0xFFE8B923),
  'Analyze': Color(0xFF3FA66B),
  'Evaluate': Color(0xFF3B7DD8),
  'Create': Color(0xFF8B5CC7),
};

/// One Bloom level's slice of an exam: [share] of all tagged items (0–1) and
/// the % of those answers that were correct.
class BloomSlice {
  final String level;
  final int items;
  final double share;
  final double? mastery;

  const BloomSlice(this.level, this.items, this.share, this.mastery);

  /// Points of the whole exam (out of 100) earned at this level.
  double get earned => share * (mastery ?? 0);
}

/// Builds the exam's slices from `bloom.overall`; levels with no items are dropped.
List<BloomSlice> bloomSlices(
  Map<String, dynamic> overall, {
  Map<String, dynamic>? masteryFrom,
}) {
  final counts = {
    for (final l in bloomLevels)
      l: ((overall[l] as Map?)?['items'] as num?)?.toInt() ?? 0,
  };
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return [];
  final source = masteryFrom ?? overall;
  return [
    for (final l in bloomLevels)
      if (counts[l]! > 0)
        BloomSlice(
          l,
          counts[l]!,
          counts[l]! / total,
          asDouble((source[l] as Map?)?['mastery']),
        ),
  ];
}

/// 100% segmented bar: segment width = share of exam items at that Bloom
/// level, solid fill height = % correct, so solid area sums to the score.
class BloomSegmentedBar extends StatelessWidget {
  final List<BloomSlice> slices;
  final double height;
  final bool showLabels;
  final ValueChanged<String>? onTapLevel;

  const BloomSegmentedBar({
    super.key,
    required this.slices,
    this.height = 64,
    this.showLabels = true,
    this.onTapLevel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < slices.length; i++)
              Expanded(
                flex: slices[i].items,
                child: GestureDetector(
                  onTap: onTapLevel == null
                      ? null
                      : () => onTapLevel!(slices[i].level),
                  child: Container(
                    margin: EdgeInsets.only(
                        right: i == slices.length - 1 ? 0 : 1.5),
                    color: bloomLevelColors[slices[i].level]!
                        .withValues(alpha: 0.18),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            widthFactor: 1,
                            heightFactor:
                                ((slices[i].mastery ?? 0) / 100).clamp(0.0, 1.0),
                            child: Container(
                                color: bloomLevelColors[slices[i].level]),
                          ),
                        ),
                        if (showLabels)
                          Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  '${bloomShort[slices[i].level]}\n'
                                  '${(slices[i].share * 100).toStringAsFixed(0)}%',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.15,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary,
                                    shadows: [
                                      Shadow(
                                          blurRadius: 4,
                                          color: c.card.withValues(alpha: 0.9)),
                                    ],
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
          ],
        ),
      ),
    );
  }
}

class MasteryLegend extends StatelessWidget {
  final double mastered;
  final double near;

  const MasteryLegend({super.key, this.mastered = 75, this.near = 50});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    Widget chip(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        chip(masteredColor, 'Mastered ≥ ${fmtNum(mastered)}%'),
        chip(nearColor, 'Nearly ${fmtNum(near)}–${fmtNum(mastered - 1)}%'),
        chip(notMasteredColor, 'Not mastered < ${fmtNum(near)}%'),
        chip(noDataColor, 'No items'),
      ],
    );
  }
}

/// Compact horizontal index bar (e.g. difficulty or discrimination).
class IndexBar extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color color;
  final String caption;

  const IndexBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.caption,
    this.min = 0,
    this.max = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final frac = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(2)} · $caption',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 7,
            backgroundColor: c.border,
            color: color,
          ),
        ),
      ],
    );
  }
}
