import 'package:flutter/material.dart';
import '../../grading/grading_repository.dart';
import '../../grading/unified_exam.dart';
import '../../quick_exam/quick_exam_models.dart';
import '../../quick_exam/quick_exam_repository.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/atlas_loading_view.dart';
import '../../../core/widgets/atlas_pull_to_refresh.dart';
import '../../../core/widgets/atlas_filter_chip.dart';
import '../../../core/widgets/atlas_info_button.dart';
import 'reports_widgets.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

/// Pass-rate breakdown follows the filters: all courses → by subject,
/// one course → by exam, one exam → by section.
enum _PassDim { subject, exam, section }

class _ReportsTabState extends State<ReportsTab> {
  final GradingRepository _repo = GradingRepository();
  final QuickExamRepository _majorRepo = QuickExamRepository();

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _requestId = 0;
  bool _savingPassingScore = false;

  String? _courseId;
  String? _assessmentId;
  String? _gradeLevel;
  String? _section;
  /// When a Major Exam (`qx:…`) is selected, hold its records summary.
  Map<String, dynamic>? _majorReport;

  String? _decisionFilter;
  final Set<int> _expandedItems = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      if (_data == null) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
      _majorReport = null;
    });
    try {
      if (isMajorExamFilterId(_assessmentId)) {
        await _loadMajorReport(id);
        return;
      }
      final data = await _repo.fetchReports(
        courseId: _courseId,
        assessmentId: _assessmentId,
        gradeLevel: _gradeLevel,
        section: _section,
      );
      await _mergeMajorExamOptions(data);
      if (!mounted || id != _requestId) return;
      setState(() {
        _data = data;
        _loading = false;
        _refreshing = false;
        _decisionFilter = null;
        _expandedItems.clear();
      });
      _warnIfIncomplete(data['coverage']);
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = friendlyError(e, fallback: 'Could not load reports. Please try again.');
      });
    }
  }

  Future<void> _mergeMajorExamOptions(Map<String, dynamic> data) async {
    try {
      final majors = await _majorRepo.fetchExams();
      final options = Map<String, dynamic>.from(
        (data['options'] as Map?) ?? {},
      );
      final assessments = [
        ...((options['assessments'] as List?) ?? []),
      ];
      final existing = {
        for (final a in assessments)
          if (a is Map) a['assessment_id']?.toString(),
      };
      for (final e in majors) {
        final fid = majorExamFilterId(e.examId);
        if (existing.contains(fid)) continue;
        if (_courseId != null) {
          // Keep majors that match any course in options when a course filter is set.
          final courses = (options['courses'] as List?) ?? const [];
          final course = courses.cast<dynamic>().whereType<Map>().where(
                (c) => c['course_id']?.toString() == _courseId,
              );
          if (course.isNotEmpty) {
            final code = (course.first['course_code'] ?? '').toString();
            final title = (course.first['course_title'] ?? '').toString();
            if (!majorExamMatchesCourse(e,
                courseCode: code, courseTitle: title)) {
              continue;
            }
          }
        }
        assessments.add({
          'assessment_id': fid,
          'title': '${e.name} · Major',
          'course_id': null,
          'source': 'major',
        });
      }
      options['assessments'] = assessments;
      data['options'] = options;
    } catch (e) {
      debugPrint('Merge major exam options failed: $e');
    }
  }

  Future<void> _loadMajorReport(int requestId) async {
    final examId = majorExamIdFromFilter(_assessmentId)!;
    try {
      final exam = await _majorRepo.fetchExam(examId);
      final records = await _majorRepo.fetchExamRecords(examId);
      // Keep course filter options available by loading a light reports shell.
      final shell = await _repo.fetchReports(courseId: _courseId);
      await _mergeMajorExamOptions(shell);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _data = shell;
        _majorReport = {
          'exam': exam,
          'records': records,
        };
        _loading = false;
        _refreshing = false;
        _decisionFilter = null;
        _expandedItems.clear();
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = friendlyError(e, fallback: 'Could not load major exam report.');
      });
    }
  }

  bool _coverageDialogOpen = false;

  /// Warns that the figures are partial when the current filters still have
  /// roster students without a scanned paper.
  Future<void> _warnIfIncomplete(dynamic coverage) async {
    if (coverage is! Map || coverage['complete'] != false || _coverageDialogOpen) {
      return;
    }
    final pending = (coverage['pending'] as List? ?? [])
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    if (pending.isEmpty) return;
    final scanned = coverage['scanned'] ?? 0;
    final expected = coverage['expected'] ?? 0;

    _coverageDialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.atlas;
        return AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          title: Row(
            children: [
              Icon(Icons.pending_actions_rounded, color: c.ambiguous),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Scanning not complete',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$scanned of $expected papers are scanned for this filter. '
                    'These reports may change once the rest are scanned.',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  for (final p in pending) _coverageGroup(ctx, p),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.insights_rounded, size: 18),
                label: const Text('View reports anyway'),
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.onPrimary,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        );
      },
    );
    _coverageDialogOpen = false;
  }

  Widget _coverageGroup(BuildContext ctx, Map<String, dynamic> p) {
    final c = ctx.atlas;
    final missing = (p['missing'] as List? ?? []).map((e) => e.toString()).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
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
                child: Text(
                  '${p['course_code'] ?? ''} · ${p['section'] ?? ''}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary),
                ),
              ),
              Text('${p['scanned']}/${p['total']} scanned',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.ambiguous)),
            ],
          ),
          Text('${p['assessment_title'] ?? ''}',
              style: TextStyle(fontSize: 12, color: c.textSecondary)),
          const SizedBox(height: 8),
          Text('Not yet scanned',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in missing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.ambiguous.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(id,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: c.ambiguous)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Filters ──────────────────────────────────────────────────────────────

  void _setCourse(String? v) {
    _courseId = v;
    _assessmentId = null;
    _gradeLevel = null;
    _section = null;
    _load();
  }

  void _setAssessment(String? v) {
    _assessmentId = v;
    if (v != null) {
      final a = _assessmentById(v);
      if (a != null) _courseId = a['course_id']?.toString();
    }
    _load();
  }

  void _setGrade(String? v) {
    _gradeLevel = v;
    _section = null;
    _load();
  }

  void _setSection(String? v) {
    _section = v;
    _load();
  }

  void _clearFilters() {
    _courseId = null;
    _assessmentId = null;
    _gradeLevel = null;
    _section = null;
    _load();
  }

  Map<String, dynamic> get _options =>
      (_data?['options'] as Map?)?.cast<String, dynamic>() ?? {};

  List<Map<String, dynamic>> _list(dynamic v) => (v as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  List<String> _strings(dynamic v) =>
      (v as List<dynamic>? ?? []).map((e) => e.toString()).toList();

  Map<String, dynamic>? _assessmentById(String id) {
    for (final a in _list(_options['assessments'])) {
      if (a['assessment_id'] == id) return a;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedAssessment =>
      _assessmentId == null ? null : _assessmentById(_assessmentId!);

  String get _scopeLabel {
    final parts = <String>[];
    final course = _list(_options['courses'])
        .where((c) => c['course_id'] == _courseId)
        .map((c) => c['course_code'].toString());
    parts.add(course.isEmpty ? 'All courses' : course.first);
    parts.add(_selectedAssessment?['title']?.toString() ?? 'all exams');
    if (_gradeLevel != null) parts.add(_gradeLevel!);
    parts.add(_section ?? 'all sections');
    return parts.join(' · ');
  }

  // ── Detail popup ─────────────────────────────────────────────────────────

  Widget _expandButton(VoidCallback onTap) => AtlasInfoButton(onTap: onTap);

  /// Full-height sheet holding a card's illustration plus its interpretation.
  void _openDetail(
    String title,
    List<Widget> Function(BuildContext ctx, StateSetter refresh) builder, {
    String? subtitle,
    Widget? action,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.atlas.scaffold,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => StatefulBuilder(
          builder: (ctx, refresh) {
            final c = ctx.atlas;
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
                            Text(subtitle ?? _scopeLabel,
                                style: TextStyle(
                                    fontSize: 12, color: c.textSecondary)),
                          ],
                        ),
                      ),
                      ?action,
                      IconButton(
                        icon: Icon(Icons.close, color: c.textSecondary),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                    children: builder(ctx, refresh),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _heading(String title, {String? hint}) {
    final c = context.atlas;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary)),
          if (hint != null)
            Text(hint, style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
        ],
      ),
    );
  }

  /// Bullet list of plain-language findings.
  Widget _interpretation(List<String> lines) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 18, color: c.primary),
              const SizedBox(width: 6),
              Text('Interpretation',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: c.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          color: c.primary, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                    child: Text(l,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4, color: c.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _plainCard(Widget child) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }

  // ── Passing score ────────────────────────────────────────────────────────

  Future<void> _editPassingScore(double initial) async {
    final assessment = _selectedAssessment;
    if (assessment == null) return;
    double current = initial;
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: context.atlas.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final c = ctx.atlas;
        return StatefulBuilder(builder: (ctx, setModal) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Passing Score — ${assessment['title']}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: c.textPrimary)),
                const SizedBox(height: 16),
                Text('${current.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: c.primary)),
                Slider(
                  value: current,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: c.primary,
                  onChanged: (v) => setModal(() => current = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.primary,
                      foregroundColor: c.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, current),
                    child: const Text('Save Passing Score'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
    if (result == null || !mounted) return;
    setState(() => _savingPassingScore = true);
    try {
      await _repo.updateTemplatePassingScore(
        assessment['template_id'].toString(),
        result,
        assessment['course_id'].toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Passing score saved: ${result.toStringAsFixed(0)}%'),
        backgroundColor: context.atlas.correct,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e, fallback: 'Could not save the passing score. Please try again.')),
        backgroundColor: context.atlas.primary,
      ));
    } finally {
      if (mounted) setState(() => _savingPassingScore = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    if (_loading) {
      return const SafeArea(
        bottom: false,
        child: AtlasLoadingView(layout: AtlasLoadingLayout.reports),
      );
    }
    if (_data == null) {
      return SafeArea(
        bottom: false,
        child: AtlasPullToRefresh(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 180),
              Center(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(_error ?? 'No data',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.primary)),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final summary = (_data!['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final count = (summary['count'] as num?)?.toInt() ?? 0;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildStickyHeader(),
          Expanded(
            child: AtlasPullToRefresh(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 56),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_error!, style: TextStyle(color: c.primary)),
                    ),
                  if (_majorReport != null)
                    _buildMajorExamReport(c)
                  else ...[
                    _buildOverview(summary),
                    if (count > 0) ...[
                      _buildPassRates(),
                      _buildDistribution(),
                    ],
                    _buildItemAnalysis(),
                    if (count > 0) _buildBloom(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int get _activeFilterCount => [_courseId, _assessmentId, _gradeLevel, _section]
      .where((v) => v != null)
      .length;

  /// Applied filters as removable chips; removing one clears its dependents.
  List<({String label, VoidCallback onRemove})> get _appliedChips {
    final chips = <({String label, VoidCallback onRemove})>[];
    if (_courseId != null) {
      final course = _list(_options['courses'])
          .where((c) => c['course_id'] == _courseId)
          .map((c) => c['course_code'].toString());
      chips.add((
        label: course.isEmpty ? 'Course' : course.first,
        onRemove: () => _setCourse(null),
      ));
    }
    if (_assessmentId != null) {
      chips.add((
        label: _selectedAssessment?['title']?.toString() ?? 'Exam',
        onRemove: () => _setAssessment(null),
      ));
    }
    if (_gradeLevel != null) {
      chips.add((label: _gradeLevel!, onRemove: () => _setGrade(null)));
    }
    if (_section != null) {
      chips.add((label: _section!, onRemove: () => _setSection(null)));
    }
    return chips;
  }

  Widget _buildStickyHeader() {
    final c = context.atlas;
    final chips = _appliedChips;
    final active = _activeFilterCount;
    return Material(
      color: c.scaffold,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 0),
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
                        'Descriptive Assessment Analytics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        AtlasAppliedChipsRow(
                          chips: chips,
                          onClearAll: _clearFilters,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AtlasFilterButton(
                  activeCount: active,
                  onPressed: _openFilterSheet,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 2,
              child: _refreshing
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_ReportFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.atlas.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ReportFilterSheet(
        repo: _repo,
        majorRepo: _majorRepo,
        initial: _ReportFilters(
          courseId: _courseId,
          assessmentId: _assessmentId,
          gradeLevel: _gradeLevel,
          section: _section,
        ),
        initialData: _data!,
      ),
    );
    if (result == null || !mounted) return;
    _courseId = result.courseId;
    _assessmentId = result.assessmentId;
    _gradeLevel = result.gradeLevel;
    _section = result.section;
    _load();
  }

  // ── Class performance ────────────────────────────────────────────────────

  Widget _performanceIllustration(Map<String, dynamic> s) {
    final c = context.atlas;
    final passRate = asDouble(s['pass_rate']);
    final passing = asDouble(_data!['passing_percent']);
    return Row(
      children: [
        RingGauge(
          percent: passRate,
          caption: 'pass rate',
          color: (passRate ?? 0) >= 50 ? masteredColor : notMasteredColor,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendLine(masteredColor, '${s['passed']} passed'),
              const SizedBox(height: 6),
              _legendLine(notMasteredColor, '${s['failed']} failed'),
              const SizedBox(height: 10),
              Text(
                'Mean ${fmtNum(asDouble(s['mean_score']))} / ${fmtNum(asDouble(s['mean_max_score']))}'
                ' · passing ${passing == null ? 'varies' : '${fmtNum(passing)}%'}',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMajorExamReport(AtlasColors c) {
    final exam = _majorReport!['exam'] as QuickExam;
    final records = _majorReport!['records'] as QuickExamRecords;
    final avg = records.averagePercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportCard(
          title: exam.name,
          subtitle: '${exam.subjectName} · Major exam',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${records.scanCount} sheet(s) · '
                '${records.passedCount} passed · '
                '${records.flaggedCount} flagged',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              if (avg != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Mean ${avg.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.primary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Full item analysis and Bloom live under Course Management '
                'for course exams. Use Major Exams for keys, sheets and records.',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
            ],
          ),
        ),
        if (records.items.isNotEmpty) ...[
          const SizedBox(height: 12),
          ReportCard(
            title: 'Item check',
            subtitle: 'Share correct among answered sheets',
            child: Column(
              children: [
                for (final it in records.items.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            '#${it.item}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (it.percentCorrect ?? 0) / 100,
                              minHeight: 8,
                              backgroundColor: c.border,
                              color: c.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          it.percentCorrect == null
                              ? '—'
                              : '${it.percentCorrect!.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOverview(Map<String, dynamic> s) {
    final c = context.atlas;
    final count = (s['count'] as num?)?.toInt() ?? 0;
    if (count == 0) {
      return ReportCard(
        title: 'Class Performance',
        child: Text(
          'No scanned papers match these filters yet. Only students on a section are counted.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      );
    }
    return ReportCard(
      title: 'Class Performance',
      subtitle: '${s['identified_students']} students · $count papers',
      trailing: _expandButton(() => _openPerformanceDetail(s)),
      child: _performanceIllustration(s),
    );
  }

  void _openPerformanceDetail(Map<String, dynamic> s) {
    final passing = asDouble(_data!['passing_percent']);
    final assessment = _selectedAssessment;
    final meanMax = asDouble(s['mean_max_score']);
    final passRate = asDouble(s['pass_rate']) ?? 0;
    final mean = asDouble(s['mean_percent']) ?? 0;
    final median = asDouble(s['median_percent']) ?? 0;
    final sd = asDouble(s['sd_percent']) ?? 0;

    final lines = <String>[
      '${s['passed']} of ${s['count']} papers passed (${fmtNum(passRate)}%) — '
          '${passRate >= 75 ? 'a high' : passRate >= 50 ? 'a moderate' : 'a low'} passing rate.',
      if (passing != null)
        'The class mean of ${fmtNum(mean)}% is '
            '${mean >= passing ? '${fmtNum(mean - passing)} points above' : '${fmtNum(passing - mean)} points below'}'
            ' the ${fmtNum(passing)}% passing mark.',
      'Half of the class scored ${fmtNum(median)}% or higher (median).',
      'Standard deviation of ${fmtNum(sd)} points means scores are '
          '${sd < 10 ? 'closely grouped (homogeneous class)' : sd <= 20 ? 'moderately spread' : 'widely spread (heterogeneous class)'}.',
      'Scores ranged from ${fmtNum(asDouble(s['min_percent']))}% to ${fmtNum(asDouble(s['max_percent']))}%.',
      if ((s['unidentified_papers'] as num? ?? 0) > 0)
        '${s['unidentified_papers']} papers without a valid SR code are excluded.',
    ];

    _openDetail('Class Performance', (ctx, refresh) => [
          _plainCard(_performanceIllustration(s)),
          _heading('Summary statistics'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
            children: [
              StatTile(
                label: 'Mean',
                value: '${fmtNum(mean)}%',
                hint: meanMax == null
                    ? null
                    : '${fmtNum(asDouble(s['mean_score']))} / ${fmtNum(meanMax)}',
              ),
              StatTile(label: 'Median', value: '${fmtNum(median)}%'),
              StatTile(label: 'Std. dev.', value: fmtNum(sd), hint: 'points'),
              StatTile(
                label: 'Highest',
                value: '${fmtNum(asDouble(s['max_percent']))}%',
                color: masteredColor,
              ),
              StatTile(
                label: 'Lowest',
                value: '${fmtNum(asDouble(s['min_percent']))}%',
                color: notMasteredColor,
              ),
              StatTile(
                label: 'Passing',
                value: passing == null ? '—' : '${fmtNum(passing)}%',
                hint: assessment == null ? 'select an exam' : 'tap to edit',
                onTap: assessment == null || _savingPassingScore
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _editPassingScore(passing ?? 50);
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _interpretation(lines),
        ]);
  }

  Widget _legendLine(Color color, String text) {
    final c = context.atlas;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary)),
      ],
    );
  }

  // ── Passing rate ─────────────────────────────────────────────────────────

  _PassDim get _passDim {
    if (_assessmentId != null) return _PassDim.section;
    if (_courseId != null) return _PassDim.exam;
    return _PassDim.subject;
  }

  String get _passDimLabel => switch (_passDim) {
        _PassDim.subject => 'Subject',
        _PassDim.exam => 'Exam',
        _PassDim.section => 'Section',
      };

  List<Map<String, dynamic>> get _passGroups => _list(_data![switch (_passDim) {
        _PassDim.subject => 'by_course',
        _PassDim.exam => 'by_assessment',
        _PassDim.section => 'by_section',
      }]);

  void _drillInto(Map<String, dynamic> g) {
    final key = g['key']?.toString();
    switch (_passDim) {
      case _PassDim.subject:
        if (key != null && key != _courseId) _setCourse(key);
      case _PassDim.exam:
        if (key != null && key != _assessmentId) _setAssessment(key);
      case _PassDim.section:
        final label = g['label']?.toString();
        if (label != null && label != _section) _setSection(label);
    }
  }

  String get _drillHint => switch (_passDim) {
        _PassDim.subject => 'Tap a subject to filter to it and see its exams.',
        _PassDim.exam => 'Tap an exam to filter to it and see its sections.',
        _PassDim.section => 'Tap a section to filter the report to it.',
      };

  Widget _buildPassRates() {
    final groups = _passGroups;
    return ReportCard(
      title: 'Passing Rate by $_passDimLabel',
      subtitle: 'Follows the filters above',
      trailing: _expandButton(_openPassRateDetail),
      child: PassRateBars(
        groups: groups,
        onTap: groups.length > 1 ? _drillInto : null,
      ),
    );
  }

  void _openPassRateDetail() {
    final groups = _passGroups;
    final passing = asDouble(_data!['passing_percent']);
    final ranked = groups.where((g) => g['pass_rate'] != null).toList()
      ..sort((a, b) =>
          (asDouble(b['pass_rate']) ?? 0).compareTo(asDouble(a['pass_rate']) ?? 0));
    final below = ranked.where((g) => (asDouble(g['pass_rate']) ?? 0) < 50).toList();
    final lines = <String>[
      if (passing != null) 'A paper passes at ${fmtNum(passing)}% or higher.',
      if (ranked.length >= 2) ...[
        'Highest: ${ranked.first['label']} at ${fmtNum(asDouble(ranked.first['pass_rate']))}% '
            '(${ranked.first['passed']} of ${ranked.first['count']}).',
        'Lowest: ${ranked.last['label']} at ${fmtNum(asDouble(ranked.last['pass_rate']))}% '
            '(${ranked.last['passed']} of ${ranked.last['count']}).',
        'Gap between highest and lowest: '
            '${fmtNum((asDouble(ranked.first['pass_rate']) ?? 0) - (asDouble(ranked.last['pass_rate']) ?? 0))} points.',
      ],
      if (ranked.length == 1)
        '${ranked.first['label']}: ${ranked.first['passed']} of ${ranked.first['count']} passed '
            '(${fmtNum(asDouble(ranked.first['pass_rate']))}%).',
      if (below.isNotEmpty)
        '${below.length == 1 ? 'This group is' : 'These groups are'} below a 50% passing rate and may need remediation: '
            '${below.map((g) => g['label']).join(', ')}.'
      else if (ranked.isNotEmpty)
        'Every ${_passDimLabel.toLowerCase()} has at least half of its students passing.',
    ];
    final c = context.atlas;
    TextStyle head() => TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: c.textSecondary);
    TextStyle body({Color? color, bool bold = false}) => TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        color: color ?? c.textPrimary);
    Widget cell(String t, TextStyle st, {TextAlign a = TextAlign.right}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(t, textAlign: a, style: st),
        );

    _openDetail('Passing Rate by $_passDimLabel', (ctx, refresh) => [
          _plainCard(PassRateBars(
            groups: groups,
            onTap: groups.length > 1
                ? (g) {
                    Navigator.pop(ctx);
                    _drillInto(g);
                  }
                : null,
          )),
          if (groups.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_drillHint,
                  style: TextStyle(fontSize: 11, color: c.textSecondary)),
            ),
          _heading('Breakdown'),
          _plainCard(Table(
            columnWidths: const {
              0: FlexColumnWidth(2.4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1.1),
              4: FlexColumnWidth(1.1),
            },
            border: TableBorder(horizontalInside: BorderSide(color: c.divider)),
            children: [
              TableRow(children: [
                cell(_passDimLabel, head(), a: TextAlign.left),
                cell('n', head()),
                cell('Passed', head()),
                cell('Rate', head()),
                cell('Mean', head()),
              ]),
              for (final g in groups)
                TableRow(children: [
                  cell((g['label'] ?? '').toString(), body(bold: true),
                      a: TextAlign.left),
                  cell('${g['count']}', body()),
                  cell('${g['passed']}', body()),
                  cell(
                    '${fmtNum(asDouble(g['pass_rate']))}%',
                    body(
                      bold: true,
                      color: (asDouble(g['pass_rate']) ?? 0) >= 50
                          ? masteredColor
                          : notMasteredColor,
                    ),
                  ),
                  cell('${fmtNum(asDouble(g['mean_percent']))}%', body()),
                ]),
            ],
          )),
          const SizedBox(height: 16),
          _interpretation(lines),
        ]);
  }

  // ── Score distribution ───────────────────────────────────────────────────

  Widget _histogram() => ScoreHistogram(
        buckets: _list(_data!['distribution']),
        passingPercent: asDouble(_data!['passing_percent']),
      );

  Widget _buildDistribution() {
    return ReportCard(
      title: 'Score Distribution',
      subtitle: 'Papers per 10% score band',
      trailing: _expandButton(_openDistributionDetail),
      child: _histogram(),
    );
  }

  void _openDistributionDetail() {
    final s = (_data!['summary'] as Map).cast<String, dynamic>();
    final buckets = _list(_data!['distribution']);
    final passing = asDouble(_data!['passing_percent']);
    final mean = asDouble(s['mean_percent']) ?? 0;
    final median = asDouble(s['median_percent']) ?? 0;
    final total = (s['count'] as num?)?.toInt() ?? 0;

    Map<String, dynamic>? mode;
    for (final b in buckets) {
      if (mode == null || (b['count'] as num) > (mode['count'] as num)) mode = b;
    }
    final skew = mean - median;
    final lines = <String>[
      if (mode != null && (mode['count'] as num) > 0)
        'Most papers (${mode['count']} of $total) fall in the '
            '${fmtNum(mode['from'] as num?)}–${fmtNum(mode['to'] as num?)}% band.',
      if (skew < -2)
        'Mean (${fmtNum(mean)}%) is below the median (${fmtNum(median)}%): the distribution is negatively skewed — most students scored high and a few low scores pull the mean down. The exam may have been easy for this group.'
      else if (skew > 2)
        'Mean (${fmtNum(mean)}%) is above the median (${fmtNum(median)}%): the distribution is positively skewed — most students scored low. The exam may have been difficult, or the topic needs reteaching.'
      else
        'Mean and median are close (${fmtNum(mean)}% vs ${fmtNum(median)}%): scores are roughly symmetric.',
      if (passing != null)
        'Bars at or above the ${fmtNum(passing)}% passing mark are shown in green.',
    ];

    _openDetail('Score Distribution', (ctx, refresh) => [
          _plainCard(_histogram()),
          const SizedBox(height: 16),
          _interpretation(lines),
        ]);
  }

  // ── Item analysis ────────────────────────────────────────────────────────

  Map<String, dynamic>? get _itemAnalysis =>
      (_data!['item_analysis'] as Map?)?.cast<String, dynamic>();

  Widget _decisionCounts(Map<String, dynamic> decisions,
      {StateSetter? refresh}) {
    return Row(
      children: [
        for (final d in ['Retain', 'Revise', 'Discard'])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: refresh == null
                    ? null
                    : () => refresh(() =>
                        _decisionFilter = _decisionFilter == d ? null : d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: decisionColor(d).withValues(
                        alpha: refresh != null && _decisionFilter == d ? 0.25 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: decisionColor(d).withValues(
                          alpha: refresh != null && _decisionFilter == d ? 1 : 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text('${decisions[d] ?? 0}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: decisionColor(d))),
                      Text(d,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: decisionColor(d))),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemAnalysis() {
    final c = context.atlas;
    final ia = _itemAnalysis;
    if (ia == null) {
      return ReportCard(
        title: 'Item Analysis',
        subtitle: 'Upper/lower 27% method',
        child: Text(
          'Choose one exam in the Exam filter to run item analysis.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      );
    }
    if (ia['available'] != true) {
      return ReportCard(
        title: 'Item Analysis',
        subtitle: ia['template_name']?.toString(),
        child: Text(ia['reason']?.toString() ?? 'Not enough data.',
            style: TextStyle(color: c.textSecondary, fontSize: 13)),
      );
    }
    final s = (ia['summary'] as Map).cast<String, dynamic>();
    final items = _list(ia['items']);
    return ReportCard(
      title: 'Item Analysis',
      subtitle: 'Difficulty × discrimination · ${s['items']} items',
      trailing: _expandButton(() => _openItemAnalysisDetail(ia)),
      child: Column(
        children: [
          ItemQuadrantChart(
            items: items,
            onTapItem: (n) => _showItemDetail(
                items.firstWhere((i) => i['item_number'] == n), ia),
          ),
          const SizedBox(height: 10),
          _decisionCounts(
              (s['decisions'] as Map?)?.cast<String, dynamic>() ?? {}),
        ],
      ),
    );
  }

  void _openItemAnalysisDetail(Map<String, dynamic> ia) {
    final c = context.atlas;
    final s = (ia['summary'] as Map).cast<String, dynamic>();
    final items = _list(ia['items']);
    final decisions = (s['decisions'] as Map?)?.cast<String, dynamic>() ?? {};
    final kr20 = asDouble(s['kr20']);
    final meanP = asDouble(s['mean_difficulty']) ?? 0;
    final meanD = asDouble(s['mean_discrimination']) ?? 0;
    final flaggedOptions =
        items.where((i) => _strings(i['distractor_issues']).isNotEmpty).length;

    final lines = <String>[
      if (kr20 != null)
        'Reliability (KR-20) is ${kr20.toStringAsFixed(2)} — ${s['reliability']}. '
            '${kr20 >= 0.7 ? 'Scores are consistent enough for classroom decisions.' : 'Scores are not very consistent; revise weak items before reusing the test.'}',
      'Average difficulty P = ${meanP.toStringAsFixed(2)} (${_difficultyWord(meanP)}); '
          'the ideal range is 0.30–0.70.',
      'Average discrimination D = ${meanD.toStringAsFixed(2)} '
          '(${meanD >= 0.4 ? 'very good' : meanD >= 0.3 ? 'good' : meanD >= 0.2 ? 'marginal' : 'poor'}) '
          '— how well items separate high and low scorers.',
      '${decisions['Retain'] ?? 0} items can be kept as is, ${decisions['Revise'] ?? 0} should be revised, '
          'and ${decisions['Discard'] ?? 0} should be discarded or rewritten.',
      if (flaggedOptions > 0)
        '$flaggedOptions items have weak or misleading distractors — open an item to see which options.',
    ];

    _openDetail(
      'Item Analysis',
      subtitle: '${ia['template_name']} · ${s['examinees']} papers · '
          'upper/lower groups of ${s['group_size']}',
      action: IconButton(
        tooltip: 'How this is computed',
        icon: Icon(Icons.help_outline, color: c.primary),
        onPressed: () => _showMethod(s),
      ),
      (ctx, refresh) {
        final visible = _decisionFilter == null
            ? items
            : items.where((i) => i['decision'] == _decisionFilter).toList();
        return [
          _plainCard(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ItemQuadrantChart(
                items: items,
                onTapItem: (n) => _showItemDetail(
                    items.firstWhere((i) => i['item_number'] == n), ia),
              ),
              const SizedBox(height: 6),
              Text(
                'Each dot is an item. Items in the green zone (P 0.30–0.70, D ≥ 0.30) work well.',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
            ],
          )),
          _heading('Test summary'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
            children: [
              StatTile(
                label: 'Reliability KR-20',
                value: kr20 == null ? '—' : kr20.toStringAsFixed(2),
                hint: s['reliability']?.toString(),
                color: kr20 == null
                    ? null
                    : (kr20 >= 0.7
                        ? masteredColor
                        : (kr20 >= 0.5 ? nearColor : notMasteredColor)),
              ),
              StatTile(
                label: 'Mean difficulty P',
                value: meanP.toStringAsFixed(2),
                hint: _difficultyWord(meanP),
              ),
              StatTile(
                label: 'Mean discrim. D',
                value: meanD.toStringAsFixed(2),
                hint: 'upper vs lower',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _interpretation(lines),
          _heading(
            _decisionFilter == null ? 'All items' : '$_decisionFilter items',
            hint: 'Tap a count to filter · tap an item to expand',
          ),
          _decisionCounts(decisions, refresh: refresh),
          const SizedBox(height: 10),
          for (final item in visible) _itemRow(item, ia, refresh),
        ];
      },
    );
  }

  String _difficultyWord(double p) {
    if (p >= 0.86) return 'very easy';
    if (p >= 0.71) return 'easy';
    if (p >= 0.30) return 'moderate';
    if (p >= 0.15) return 'difficult';
    return 'very difficult';
  }

  Widget _itemRow(
      Map<String, dynamic> item, Map<String, dynamic> ia, StateSetter refresh) {
    final c = context.atlas;
    final n = (item['item_number'] as num).toInt();
    final p = asDouble(item['difficulty']) ?? 0;
    final d = asDouble(item['discrimination']) ?? 0;
    final decision = item['decision'].toString();
    final expanded = _expandedItems.contains(n);
    final bloom = item['bloom_level']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: decisionColor(decision), width: 4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => refresh(() {
          expanded ? _expandedItems.remove(n) : _expandedItems.add(n);
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Item $n',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: c.textPrimary)),
                  const SizedBox(width: 8),
                  Text('Key ${item['correct_answer']}',
                      style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  if (bloom != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(bloom,
                          style: TextStyle(fontSize: 10, color: c.primary)),
                    ),
                  ],
                  const Spacer(),
                  _pill(decision, decisionColor(decision)),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: c.textSecondary),
                ],
              ),
              const SizedBox(height: 8),
              IndexBar(
                label: 'Difficulty P',
                value: p,
                caption: item['difficulty_label'].toString(),
                color: (p >= 0.30 && p <= 0.70) ? masteredColor : nearColor,
              ),
              const SizedBox(height: 6),
              IndexBar(
                label: 'Discrimination D',
                value: d,
                min: -1,
                caption: item['discrimination_label'].toString(),
                color: d >= 0.30
                    ? masteredColor
                    : (d >= 0.20 ? nearColor : notMasteredColor),
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                _itemDetails(item, ia),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemDetails(Map<String, dynamic> item, Map<String, dynamic> ia) {
    final c = context.atlas;
    final s = (ia['summary'] as Map).cast<String, dynamic>();
    final n = s['group_size'];
    final options = _list(item['options']);
    final issues = _strings(item['distractor_issues']);
    final question = (item['question'] ?? '').toString();
    TextStyle cell({bool bold = false, Color? color}) => TextStyle(
        fontSize: 11.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: color ?? c.textPrimary);
    Widget td(String t, TextStyle st) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(t, style: st),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question.isNotEmpty) ...[
          Text(question, style: TextStyle(fontSize: 12, color: c.textPrimary)),
          const SizedBox(height: 8),
        ],
        Text(
          'U = ${item['upper_correct']}/$n correct in upper group · '
          'L = ${item['lower_correct']}/$n in lower group · '
          '${item['total_correct']}/${s['examinees']} overall'
          '${item['point_biserial'] != null ? ' · r_pb = ${item['point_biserial']}' : ''}',
          style: TextStyle(fontSize: 11.5, color: c.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          'P = (${item['upper_correct']} + ${item['lower_correct']}) ÷ (2×$n) = ${fmtNum(asDouble(item['difficulty']), decimals: 2)}   '
          'D = (${item['upper_correct']} − ${item['lower_correct']}) ÷ $n = ${fmtNum(asDouble(item['discrimination']), decimals: 2)}',
          style: TextStyle(fontSize: 11.5, color: c.textSecondary),
        ),
        const SizedBox(height: 8),
        Text('Distractor analysis', style: cell(bold: true)),
        const SizedBox(height: 4),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.6),
          },
          border: TableBorder(horizontalInside: BorderSide(color: c.border)),
          children: [
            TableRow(children: [
              for (final h in ['Option', 'Upper', 'Lower', 'All %', 'Verdict'])
                td(h, cell(bold: true)),
            ]),
            for (final o in options)
              TableRow(children: [
                td('${o['option']}${o['is_key'] == true ? ' ✓' : ''}',
                    cell(
                        bold: o['is_key'] == true,
                        color: o['is_key'] == true ? masteredColor : null)),
                td('${o['upper']}', cell()),
                td('${o['lower']}', cell()),
                td('${fmtNum(asDouble(o['percent']))}%', cell()),
                td(
                  o['is_key'] == true
                      ? 'Key'
                      : (o['functional'] == null
                          ? '—'
                          : (o['functional'] == true ? 'Working' : 'Weak')),
                  cell(
                    color: o['is_key'] == true || o['functional'] == true
                        ? masteredColor
                        : (o['functional'] == false ? nearColor : null),
                  ),
                ),
              ]),
          ],
        ),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final i in issues)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: nearColor),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(i,
                          style: TextStyle(
                              fontSize: 11, color: c.textSecondary))),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  void _showItemDetail(Map<String, dynamic> item, Map<String, dynamic> ia) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.atlas.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final c = ctx.atlas;
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Text('Item ${item['item_number']}',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary)),
                  const SizedBox(width: 10),
                  _pill(item['decision'].toString(),
                      decisionColor(item['decision'].toString())),
                ],
              ),
              const SizedBox(height: 12),
              _itemDetails(item, ia),
            ],
          ),
        );
      },
    );
  }

  void _showMethod(Map<String, dynamic> s) {
    final n = s['examinees'];
    final g = s['group_size'];
    final steps = <(String, String)>[
      (
        '1. Score and rank',
        'All $n papers were scored against the answer key and ranked from highest to lowest total score.'
      ),
      (
        '2. Form upper and lower groups',
        'The top 27% ($g papers) form the Upper group and the bottom 27% ($g papers) form the Lower group. The middle 46% is set aside.'
      ),
      (
        '3. Tally correct answers per item',
        'U = number correct in the Upper group, L = number correct in the Lower group.'
      ),
      (
        '4. Difficulty index',
        'P = (U + L) ÷ 2n.  0.86+ very easy · 0.71–0.85 easy · 0.30–0.70 moderate (ideal) · 0.15–0.29 difficult · below 0.15 very difficult.'
      ),
      (
        '5. Discrimination index',
        'D = (U − L) ÷ n.  0.40+ very good · 0.30–0.39 good · 0.20–0.29 marginal (revise) · below 0.20 poor · negative = more low scorers got it right (discard).'
      ),
      (
        '6. Distractor analysis',
        'Every wrong option should be chosen by at least 5% of students, and by more Lower- than Upper-group students. Options that fail are flagged.'
      ),
      (
        '7. Decision',
        'Retain: moderate difficulty and D ≥ 0.30 (or D ≥ 0.40 when difficulty is 0.15–0.85). Discard: negative D, or very easy/very difficult with D < 0.20. Otherwise Revise.'
      ),
      (
        '8. Test reliability (KR-20)',
        'KR-20 = k/(k−1) × (1 − Σpq ÷ σ²), where k = number of items, p = proportion correct, q = 1 − p, σ² = variance of total scores. 0.70+ is acceptable for classroom tests.'
      ),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.atlas.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final c = ctx.atlas;
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(22),
            children: [
              Text('How item analysis is computed',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'The manual upper–lower 27% procedure, automated from the recorded bubble-sheet answers.',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
              const SizedBox(height: 14),
              for (final (title, body) in steps) ...[
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary)),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.4, color: c.textSecondary)),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Bloom's mastery ──────────────────────────────────────────────────────

  static const _bloomTitle = "Bloom's Taxonomy Mastery";

  Map<String, dynamic> get _bloom =>
      (_data!['bloom'] as Map?)?.cast<String, dynamic>() ?? {};

  Widget _bloomIllustration(List<BloomSlice> slices, double mastered, double near) {
    final c = context.atlas;
    final earned = slices.fold<double>(0, (a, s) => a + s.earned);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${earned.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: masteryColor(earned, mastered: mastered, near: near))),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('of the exam earned, built from each level',
                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        BloomSegmentedBar(
          slices: slices,
          height: 72,
          onTapLevel: (l) => _showBloomStudents(l, _bloom),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('0%', style: TextStyle(fontSize: 10, color: c.textSecondary)),
            const Spacer(),
            Text('100% of exam items',
                style: TextStyle(fontSize: 10, color: c.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _buildBloom() {
    final c = context.atlas;
    if (_assessmentId == null) {
      return ReportCard(
        title: _bloomTitle,
        subtitle: 'How the exam is split across Bloom levels',
        child: Text(
          'Choose one exam in the Exam filter to see its Bloom breakdown.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      );
    }
    final bloom = _bloom;
    final overall = (bloom['overall'] as Map?)?.cast<String, dynamic>() ?? {};
    final mastered = asDouble(bloom['mastery_threshold']) ?? 75;
    final near = asDouble(bloom['near_mastery_threshold']) ?? 50;
    final slices = bloomSlices(overall);
    if (slices.isEmpty) {
      return ReportCard(
        title: _bloomTitle,
        child: Text(
          'None of this exam\'s items have a Bloom level yet.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      );
    }
    return ReportCard(
      title: _bloomTitle,
      subtitle: 'Width = share of items · solid = answered correctly',
      trailing: _expandButton(() => _openBloomDetail(slices, mastered, near)),
      child: _bloomIllustration(slices, mastered, near),
    );
  }

  void _openBloomDetail(List<BloomSlice> slices, double mastered, double near) {
    final c = context.atlas;
    final bloom = _bloom;
    final overall = (bloom['overall'] as Map?)?.cast<String, dynamic>() ?? {};
    final untagged = (bloom['untagged_items'] as num?)?.toInt() ?? 0;
    final tagged = slices.fold<int>(0, (a, s) => a + s.items);
    final earned = slices.fold<double>(0, (a, s) => a + s.earned);
    final sections = _section == null ? _list(bloom['by_section']) : const [];

    ({double share, double earned}) band(List<String> levels) {
      final part = slices.where((s) => levels.contains(s.level));
      return (
        share: part.fold<double>(0, (a, s) => a + s.share) * 100,
        earned: part.fold<double>(0, (a, s) => a + s.earned),
      );
    }

    final lower = band(const ['Remember', 'Understand']);
    final higher = band(const ['Apply', 'Analyze', 'Evaluate', 'Create']);
    final withMastery = slices.where((s) => s.mastery != null).toList()
      ..sort((a, b) => b.mastery!.compareTo(a.mastery!));
    final biggest = [...slices]..sort((a, b) => b.items.compareTo(a.items));

    final lines = <String>[
      'The class earned ${earned.toStringAsFixed(1)}% of the $tagged Bloom-tagged items.',
      'The exam leans most on ${biggest.first.level} '
          '(${biggest.first.items} items, ${(biggest.first.share * 100).toStringAsFixed(0)}% of the test).',
      if (withMastery.length >= 2) ...[
        'Strongest level: ${withMastery.first.level} at ${withMastery.first.mastery!.toStringAsFixed(0)}% correct.',
        'Weakest level: ${withMastery.last.level} at ${withMastery.last.mastery!.toStringAsFixed(0)}% correct'
            '${withMastery.last.mastery! < near ? ' — not yet mastered; consider reteaching.' : '.'}',
      ],
      if (lower.share > 0 && higher.share > 0)
        'Lower-order items: ${(lower.earned / lower.share * 100).toStringAsFixed(0)}% correct; '
            'higher-order items: ${(higher.earned / higher.share * 100).toStringAsFixed(0)}% correct.'
      else if (higher.share == 0)
        'This exam has no higher-order (Apply to Create) items.'
      else
        'This exam has no lower-order (Remember, Understand) items.',
      if (untagged > 0) '$untagged items without a Bloom level are excluded.',
    ];

    TextStyle head() => TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: c.textSecondary);
    TextStyle body({Color? color, bool bold = false}) => TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        color: color ?? c.textPrimary);
    Widget cell(String text, TextStyle style, {TextAlign align = TextAlign.right}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text, textAlign: align, style: style),
        );

    _openDetail(_bloomTitle, (ctx, refresh) => [
          _plainCard(_bloomIllustration(slices, mastered, near)),
          _heading('Breakdown by level',
              hint: 'Earned = Share × Correct · tap a level for per-student results'),
          _plainCard(Table(
            columnWidths: const {
              0: FlexColumnWidth(2.4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1.1),
              3: FlexColumnWidth(1.3),
              4: FlexColumnWidth(1.2),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(horizontalInside: BorderSide(color: c.divider)),
            children: [
              TableRow(children: [
                cell('Level', head(), align: TextAlign.left),
                cell('Items', head()),
                cell('Share', head()),
                cell('Correct', head()),
                cell('Earned', head()),
              ]),
              for (final s in slices)
                TableRow(children: [
                  InkWell(
                    onTap: () => _showBloomStudents(s.level, bloom),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: bloomLevelColors[s.level],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: Text(s.level, style: body(bold: true))),
                        ],
                      ),
                    ),
                  ),
                  cell('${s.items}', body()),
                  cell('${(s.share * 100).toStringAsFixed(0)}%', body()),
                  cell(
                    s.mastery == null ? '—' : '${s.mastery!.toStringAsFixed(0)}%',
                    body(
                      bold: true,
                      color: masteryColor(s.mastery, mastered: mastered, near: near),
                    ),
                  ),
                  cell(s.earned.toStringAsFixed(1), body()),
                ]),
              TableRow(children: [
                cell('Total', body(bold: true), align: TextAlign.left),
                cell('$tagged', body(bold: true)),
                cell('100%', body(bold: true)),
                cell('', body()),
                cell(earned.toStringAsFixed(1), body(bold: true)),
              ]),
            ],
          )),
          const SizedBox(height: 8),
          MasteryLegend(mastered: mastered, near: near),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Lower-order (Rem + Und)',
                  value: lower.share == 0
                      ? '—'
                      : '${lower.earned.toStringAsFixed(1)} / ${lower.share.toStringAsFixed(0)}',
                  hint: lower.share == 0 ? 'not assessed' : 'earned / share of exam',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  label: 'Higher-order (App → Cre)',
                  value: higher.share == 0
                      ? '—'
                      : '${higher.earned.toStringAsFixed(1)} / ${higher.share.toStringAsFixed(0)}',
                  hint: higher.share == 0 ? 'not assessed' : 'earned / share of exam',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _interpretation(lines),
          if (sections.isNotEmpty) ...[
            _heading('By section',
                hint: 'Same item split for every section; compare how much of each segment is solid.'),
            _plainCard(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in sections)
                  Builder(builder: (_) {
                    final rowSlices = bloomSlices(
                      overall,
                      masteryFrom: (row['levels'] as Map?)?.cast<String, dynamic>(),
                    );
                    final rowEarned =
                        rowSlices.fold<double>(0, (a, s) => a + s.earned);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text((row['label'] ?? '').toString(),
                                    style: body(bold: true)),
                              ),
                              Text('${rowEarned.toStringAsFixed(1)}%',
                                  style: body(
                                    bold: true,
                                    color: masteryColor(rowEarned,
                                        mastered: mastered, near: near),
                                  )),
                            ],
                          ),
                          const SizedBox(height: 4),
                          BloomSegmentedBar(
                            slices: rowSlices,
                            height: 28,
                            showLabels: false,
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            )),
          ],
        ]);
  }

  void _showBloomStudents(String level, Map<String, dynamic> bloom) {
    final mastered = asDouble(bloom['mastery_threshold']) ?? 75;
    final near = asDouble(bloom['near_mastery_threshold']) ?? 50;
    final students = _list(bloom['students'])
        .map((s) => (
              id: s['student_id'].toString(),
              v: asDouble((s['levels'] as Map?)?[level]),
            ))
        .where((s) => s.v != null)
        .toList()
      ..sort((a, b) => b.v!.compareTo(a.v!));
    final masteredCount = students.where((s) => s.v! >= mastered).length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.atlas.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final c = ctx.atlas;
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text('$level — per-student mastery',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  students.isEmpty
                      ? 'No students answered items at this level.'
                      : '$masteredCount of ${students.length} students mastered (≥ ${fmtNum(mastered)}%)',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: students.length,
                  separatorBuilder: (_, _) => Divider(color: c.divider, height: 1),
                  itemBuilder: (_, i) {
                    final s = students[i];
                    final color = masteryColor(s.v, mastered: mastered, near: near);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(s.id,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary)),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: s.v! / 100,
                                minHeight: 8,
                                backgroundColor: c.border,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 40,
                            child: Text('${s.v!.toStringAsFixed(0)}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, color: color)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportFilters {
  final String? courseId;
  final String? assessmentId;
  final String? gradeLevel;
  final String? section;

  const _ReportFilters({
    this.courseId,
    this.assessmentId,
    this.gradeLevel,
    this.section,
  });
}

/// Shopping-app style filter sheet: pill options per group, live result
/// count, Reset and "Show results" footer.
class _ReportFilterSheet extends StatefulWidget {
  final GradingRepository repo;
  final QuickExamRepository majorRepo;
  final _ReportFilters initial;
  final Map<String, dynamic> initialData;

  const _ReportFilterSheet({
    required this.repo,
    required this.majorRepo,
    required this.initial,
    required this.initialData,
  });

  @override
  State<_ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends State<_ReportFilterSheet> {
  late String? _course = widget.initial.courseId;
  late String? _exam = widget.initial.assessmentId;
  late String? _grade = widget.initial.gradeLevel;
  late String? _section = widget.initial.section;
  late Map<String, dynamic> _preview = widget.initialData;
  bool _previewing = false;
  int _previewId = 0;

  Map<String, dynamic> get _options =>
      (_preview['options'] as Map?)?.cast<String, dynamic>() ?? {};

  List<Map<String, dynamic>> _list(dynamic v) => (v as List<dynamic>? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  List<String> _strings(dynamic v) =>
      (v as List<dynamic>? ?? []).map((e) => e.toString()).toList();

  int get _resultCount =>
      ((_preview['summary'] as Map?)?['count'] as num?)?.toInt() ?? 0;

  Future<void> _mergeMajors(Map<String, dynamic> data) async {
    try {
      final majors = await widget.majorRepo.fetchExams();
      final options = Map<String, dynamic>.from(
        (data['options'] as Map?) ?? {},
      );
      final assessments = [...((options['assessments'] as List?) ?? [])];
      final existing = {
        for (final a in assessments)
          if (a is Map) a['assessment_id']?.toString(),
      };
      for (final e in majors) {
        final fid = majorExamFilterId(e.examId);
        if (existing.contains(fid)) continue;
        assessments.add({
          'assessment_id': fid,
          'title': '${e.name} · Major',
          'course_id': null,
          'source': 'major',
        });
      }
      options['assessments'] = assessments;
      data['options'] = options;
    } catch (_) {}
  }

  Future<void> _refreshPreview() async {
    final id = ++_previewId;
    setState(() => _previewing = true);
    try {
      final data = await widget.repo.fetchReports(
        courseId: _course,
        // Major exam ids are not course assessments — keep options only.
        assessmentId: isMajorExamFilterId(_exam) ? null : _exam,
        gradeLevel: _grade,
        section: _section,
      );
      await _mergeMajors(data);
      if (!mounted || id != _previewId) return;
      setState(() {
        _preview = data;
        _previewing = false;
      });
    } catch (_) {
      if (mounted && id == _previewId) setState(() => _previewing = false);
    }
  }

  void _pickCourse(String? v) {
    _course = v;
    _exam = null;
    _grade = null;
    _section = null;
    _refreshPreview();
  }

  void _pickExam(String? v) {
    _exam = v;
    if (v != null && !isMajorExamFilterId(v)) {
      final a = _list(_options['assessments'])
          .where((a) => a['assessment_id'] == v);
      if (a.isNotEmpty) {
        final cid = a.first['course_id']?.toString();
        if (cid != null && cid.isNotEmpty) _course = cid;
      }
    }
    _grade = null;
    _section = null;
    _refreshPreview();
  }

  void _pickGrade(String? v) {
    _grade = v;
    _section = null;
    _refreshPreview();
  }

  void _pickSection(String? v) {
    _section = v;
    _refreshPreview();
  }

  void _reset() {
    _course = null;
    _exam = null;
    _grade = null;
    _section = null;
    _refreshPreview();
  }

  Widget _group(String title, List<Widget> pills, {String? hint}) {
    final c = context.atlas;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary)),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint,
                  style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap,
      {String? subtitle}) {
    final c = context.atlas;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? c.primary : c.border, width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded, size: 15, color: c.onPrimary),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? c.onPrimary : c.textPrimary)),
              ],
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: selected
                          ? c.onPrimary.withValues(alpha: 0.85)
                          : c.textSecondary)),
          ],
        ),
      ),
    );
  }

  List<Widget> _pills<T>(
    List<T> items,
    String? selected,
    String allLabel,
    ValueChanged<String?> onPick,
    String Function(T) id,
    String Function(T) label, {
    String? Function(T)? subtitle,
  }) {
    return [
      _pill(allLabel, selected == null, () => setState(() => onPick(null))),
      for (final item in items)
        _pill(
          label(item),
          selected == id(item),
          () => setState(() => onPick(id(item))),
          subtitle: subtitle?.call(item),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final courses = _list(_options['courses']);
    final exams = _list(_options['assessments'])
        .where((a) => _course == null || a['course_id'] == _course)
        .toList();
    final grades = _strings(_options['grade_levels']);
    final sections = _strings(_options['sections']);
    final selectedCount =
        [_course, _exam, _grade, _section].where((v) => v != null).length;

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Text('Filters',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                if (selectedCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$selectedCount',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: c.onPrimary)),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: c.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.divider),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              children: [
                _group(
                  'Course',
                  _pills<Map<String, dynamic>>(
                    courses,
                    _course,
                    'All courses',
                    _pickCourse,
                    (c) => c['course_id'].toString(),
                    (c) => c['course_code'].toString(),
                    subtitle: (c) => c['course_title']?.toString(),
                  ),
                ),
                _group(
                  'Exam',
                  exams.isEmpty
                      ? [
                          Text('No scanned exams yet.',
                              style: TextStyle(
                                  fontSize: 12.5, color: c.textSecondary)),
                        ]
                      : _pills<Map<String, dynamic>>(
                          exams,
                          _exam,
                          'All exams',
                          _pickExam,
                          (a) => a['assessment_id'].toString(),
                          (a) => a['title'].toString(),
                          subtitle: _course == null
                              ? (a) => a['course_code']?.toString()
                              : null,
                        ),
                  hint: 'Pick one exam to unlock item analysis and Bloom mastery.',
                ),
                _group(
                  'Grade level',
                  _pills<String>(
                      grades, _grade, 'All levels', _pickGrade, (g) => g, (g) => g),
                ),
                _group(
                  'Section',
                  _pills<String>(sections, _section, 'All sections',
                      _pickSection, (s) => s, (s) => s),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: c.card,
              border: Border(top: BorderSide(color: c.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: c.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: selectedCount == 0 ? null : () => setState(_reset),
                    child: Text('Reset',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: c.textPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.primary,
                      foregroundColor: c.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _previewing
                        ? null
                        : () => Navigator.pop(
                              context,
                              _ReportFilters(
                                courseId: _course,
                                assessmentId: _exam,
                                gradeLevel: _grade,
                                section: _section,
                              ),
                            ),
                    child: _previewing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.onPrimary),
                          )
                        : Text(
                            'Show $_resultCount paper${_resultCount == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
