import 'package:flutter/material.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_filter_chip.dart';
import '../grading/grading_repository.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDay(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String formatDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, ${d.year} · $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

String _fmtNum(num? v) {
  if (v == null) return '—';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// Scanned / total students per section for one exam, from student-scores rows.
class SectionProgress {
  final String section;
  final int scanned;
  final int total;

  const SectionProgress(this.section, this.scanned, this.total);
}

List<SectionProgress> sectionProgress(List<Map<String, dynamic>> rows) {
  final totals = <String, int>{};
  final scanned = <String, int>{};
  for (final r in rows) {
    final s = (r['section'] ?? '').toString().trim();
    final key = s.isEmpty ? 'Unassigned' : s;
    totals[key] = (totals[key] ?? 0) + 1;
    if (r['score'] != null) scanned[key] = (scanned[key] ?? 0) + 1;
  }
  final keys = totals.keys.toList()
    ..sort((a, b) {
      if (a == 'Unassigned') return 1;
      if (b == 'Unassigned') return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return [for (final k in keys) SectionProgress(k, scanned[k] ?? 0, totals[k]!)];
}

Widget _sheetFrame(
  BuildContext context, {
  required String title,
  String? subtitle,
  required ScrollController scroll,
  required List<Widget> children,
}) {
  final c = context.atlas;
  return Column(
    children: [
      const SizedBox(height: 8),
      Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: c.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: c.textSecondary),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: children,
        ),
      ),
    ],
  );
}

Future<void> _showTallSheet(
  BuildContext context,
  Widget Function(BuildContext, ScrollController) builder,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.atlas.scaffold,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: builder,
    ),
  );
}

Widget _passPill(BuildContext context, bool? passed) {
  final c = context.atlas;
  final color = passed == null
      ? c.textSecondary
      : (passed ? c.correct : c.incorrect);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      passed == null ? '—' : (passed ? 'Passed' : 'Failed'),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

// ── Pending assessment: scanned students per section ───────────────────────

void showAssessmentScansSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<Map<String, dynamic>> rows,
  required int totalItems,
}) {
  _showTallSheet(
    context,
    (ctx, scroll) => _AssessmentScansSheet(
      title: title,
      subtitle: subtitle,
      rows: rows,
      totalItems: totalItems,
      scroll: scroll,
    ),
  );
}

class _AssessmentScansSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> rows;
  final int totalItems;
  final ScrollController scroll;

  const _AssessmentScansSheet({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.totalItems,
    required this.scroll,
  });

  @override
  State<_AssessmentScansSheet> createState() => _AssessmentScansSheetState();
}

class _AssessmentScansSheetState extends State<_AssessmentScansSheet> {
  String? _section;

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final progress = sectionProgress(widget.rows);
    final inSection = widget.rows.where((r) {
      final s = (r['section'] ?? '').toString().trim();
      return _section == null || (s.isEmpty ? 'Unassigned' : s) == _section;
    }).toList();
    final scanned = inSection.where((r) => r['score'] != null).toList()
      ..sort((a, b) =>
          (a['student_id'] ?? '').toString().compareTo((b['student_id'] ?? '').toString()));
    final passed = scanned.where((r) => r['passed'] == true).length;
    final notScanned = inSection.where((r) => r['score'] == null).toList()
      ..sort((a, b) {
        final bySection = _sectionOf(a).compareTo(_sectionOf(b));
        return bySection != 0
            ? bySection
            : (a['student_id'] ?? '').toString().compareTo((b['student_id'] ?? '').toString());
      });

    TextStyle head() => TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: c.textSecondary);

    return _sheetFrame(
      context,
      title: widget.title,
      subtitle: widget.subtitle,
      scroll: widget.scroll,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AtlasFilterPill(
                  label: 'All sections',
                  selected: _section == null,
                  onTap: () => setState(() => _section = null),
                ),
              ),
              for (final p in progress)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AtlasFilterPill(
                    label: p.section,
                    subtitle: '${p.scanned}/${p.total} scanned',
                    selected: _section == p.section,
                    onTap: () => setState(() => _section = p.section),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _stat(context, 'Scanned', '${scanned.length}/${inSection.length}'),
            const SizedBox(width: 8),
            _stat(context, 'Passed', '$passed', color: c.correct),
            const SizedBox(width: 8),
            _stat(context, 'Failed', '${scanned.length - passed}', color: c.incorrect),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: scanned.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text('No answer sheets scanned yet for this section.',
                      style: TextStyle(color: c.textSecondary, fontSize: 13)),
                )
              : Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.6),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder(
                      horizontalInside: BorderSide(color: c.divider)),
                  children: [
                    TableRow(children: [
                      _cell(Text('Student ID', style: head())),
                      _cell(Text('Score', style: head())),
                      _cell(Text('Status', style: head())),
                    ]),
                    for (final r in scanned)
                      TableRow(children: [
                        _cell(Text((r['student_id'] ?? '').toString(),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: c.textPrimary))),
                        _cell(Text(
                          '${_fmtNum(r['score'] as num?)} / ${_fmtNum((r['max_score'] as num?) ?? widget.totalItems)}',
                          style: TextStyle(fontSize: 13, color: c.textPrimary),
                        )),
                        _cell(Align(
                          alignment: Alignment.centerLeft,
                          child: _passPill(context, r['passed'] as bool?),
                        )),
                      ]),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Icon(Icons.pending_actions_rounded, size: 18, color: c.ambiguous),
            const SizedBox(width: 6),
            Text('Not yet scanned',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.ambiguous.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${notScanned.length}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: c.ambiguous)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: notScanned.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text('Every student here has been scanned.',
                      style: TextStyle(color: c.textSecondary, fontSize: 13)),
                )
              : Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.6),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: TableBorder(
                      horizontalInside: BorderSide(color: c.divider)),
                  children: [
                    TableRow(children: [
                      _cell(Text('Student ID', style: head())),
                      _cell(Text('Section', style: head())),
                      _cell(Text('Status', style: head())),
                    ]),
                    for (final r in notScanned)
                      TableRow(children: [
                        _cell(Text((r['student_id'] ?? '').toString(),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: c.textPrimary))),
                        _cell(Text(_sectionOf(r),
                            style: TextStyle(fontSize: 13, color: c.textPrimary))),
                        _cell(Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.ambiguous.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('Pending',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: c.ambiguous)),
                          ),
                        )),
                      ]),
                  ],
                ),
        ),
      ],
    );
  }

  String _sectionOf(Map<String, dynamic> r) {
    final s = (r['section'] ?? '').toString().trim();
    return s.isEmpty ? 'Unassigned' : s;
  }

  Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: child,
      );
}

Widget _stat(BuildContext context, String label, String value, {Color? color}) {
  final c = context.atlas;
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: color ?? c.textPrimary)),
        ],
      ),
    ),
  );
}

// ── System events: scans within a date range ───────────────────────────────

enum ScanRange { today, week, month, year, custom }

extension ScanRangeLabel on ScanRange {
  String get label => switch (this) {
        ScanRange.today => 'Today',
        ScanRange.week => 'Week',
        ScanRange.month => 'Month',
        ScanRange.year => 'Year',
        ScanRange.custom => 'Custom',
      };
}

/// Inclusive (from, to) days for a preset: today, or the last 7 / 30 / 365 days.
DateTimeRange rangeFor(ScanRange r) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final back = switch (r) {
    ScanRange.today => 0,
    ScanRange.week => 6,
    ScanRange.month => 29,
    ScanRange.year => 364,
    ScanRange.custom => 6,
  };
  return DateTimeRange(start: today.subtract(Duration(days: back)), end: today);
}

/// One scan event line (student, exam, score, pass/fail, time).
class ScanEventTile extends StatelessWidget {
  final Map<String, dynamic> scan;
  final String? timeLabel;

  const ScanEventTile({super.key, required this.scan, this.timeLabel});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final flagged = scan['is_flagged'] == true;
    final score = scan['score'] as num?;
    final max = scan['max_score'] as num?;
    final pct = scan['score_percent'] as num?;
    final scoreText = score != null && max != null
        ? '${_fmtNum(score)}/${_fmtNum(max)}'
        : (pct != null ? '${pct.toStringAsFixed(0)}%' : 'N/A');
    final at = DateTime.tryParse(scan['created_at']?.toString() ?? '')?.toLocal();
    final section = scan['section']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            flagged ? Icons.flag_rounded : Icons.check_circle_rounded,
            color: flagged ? Colors.orange.shade600 : c.correct,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${scan['student_id'] ?? 'Unknown'}'
                        '${section != null && section.isNotEmpty ? ' · $section' : ''}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: c.textPrimary),
                      ),
                    ),
                    Text(scoreText,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: c.textPrimary)),
                    const SizedBox(width: 6),
                    _passPill(context, scan['passed'] as bool?),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${scan['assessment_title'] ?? scan['template_name'] ?? 'Answer sheet'}'
                  ' — ${scan['course_code'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                Text(
                  timeLabel ?? (at == null ? '' : formatDateTime(at)),
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void showScanEventsSheet(BuildContext context, GradingRepository repo) {
  _showTallSheet(
    context,
    (ctx, scroll) => _ScanEventsSheet(repo: repo, scroll: scroll),
  );
}

class _ScanEventsSheet extends StatefulWidget {
  final GradingRepository repo;
  final ScrollController scroll;

  const _ScanEventsSheet({required this.repo, required this.scroll});

  @override
  State<_ScanEventsSheet> createState() => _ScanEventsSheetState();
}

class _ScanEventsSheetState extends State<_ScanEventsSheet> {
  ScanRange _range = ScanRange.week;
  late DateTimeRange _dates = rangeFor(ScanRange.week);
  List<Map<String, dynamic>> _scans = [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scans = await widget.repo.fetchScansInRange(
        from: _dates.start,
        to: _dates.end,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _scans = scans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e, fallback: 'Could not load scans. Please try again.');
      });
    }
  }

  Future<void> _pick(ScanRange r) async {
    if (r == ScanRange.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: _dates,
      );
      if (picked == null) return;
      setState(() {
        _range = r;
        _dates = picked;
      });
    } else {
      setState(() {
        _range = r;
        _dates = rangeFor(r);
      });
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final passed = _scans.where((s) => s['passed'] == true).length;
    final failed = _scans.where((s) => s['passed'] == false).length;
    final flagged = _scans.where((s) => s['is_flagged'] == true).length;
    final sameDay = _dates.start == _dates.end;

    return _sheetFrame(
      context,
      title: 'Scan Events',
      subtitle: sameDay
          ? formatDay(_dates.start)
          : '${formatDay(_dates.start)} – ${formatDay(_dates.end)}',
      scroll: widget.scroll,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in ScanRange.values)
              AtlasFilterPill(
                label: r.label,
                selected: _range == r,
                onTap: () => _pick(r),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _stat(context, 'Scans', '${_scans.length}'),
            const SizedBox(width: 8),
            _stat(context, 'Passed', '$passed', color: c.correct),
            const SizedBox(width: 8),
            _stat(context, 'Failed', '$failed', color: c.incorrect),
          ],
        ),
        if (flagged > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('$flagged scans were flagged for review.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
          ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Text(_error!, style: TextStyle(color: c.primary))
        else if (_scans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No scans in this period.',
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _scans.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: c.divider),
                  ScanEventTile(scan: _scans[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
