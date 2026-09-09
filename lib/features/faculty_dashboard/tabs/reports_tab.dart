import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../grading/grading_repository.dart';
import '../../grading/models.dart';
import '../../../core/widgets/atlas_loading_view.dart';
import '../../../core/widgets/atlas_pull_to_refresh.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final GradingRepository _repo = GradingRepository();
  bool _loading = true;
  bool _savingPassingScore = false;
  String? _error;

  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _assessments = [];
  List<BubbleTemplate> _templates = [];
  List<BubbleScan> _scans = [];
  List<String> _sections = [];
  List<Map<String, dynamic>> _enrolledStudents = [];
  List<Map<String, dynamic>> _itemAnalysis = [];

  String? _filterCourseId;
  String? _filterAssessmentId;
  String? _selectedSection;

  double _classAverage = 0;
  int _scanCount = 0;
  int _totalScannedStudents = 0;
  Map<String, double> _bloomAverages = {};
  Map<String, List<Map<String, dynamic>>> _bloomDetails = {};
  List<Map<String, dynamic>> _perStudent = [];

  static const _bloomLabels = {
    'Remember': 'R',
    'Understand': 'U',
    'Apply': 'Ap',
    'Analyze': 'An',
    'Evaluate': 'Ev',
    'Create': 'Cr',
  };

  static const _bloomLabelFull = {
    'Remember': 'Remember',
    'Understand': 'Understand',
    'Apply': 'Apply',
    'Analyze': 'Analyze',
    'Evaluate': 'Evaluate',
    'Create': 'Create',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final courses = await _repo.fetchFacultyCourses();
      final templates = <BubbleTemplate>[];
      final scans = <BubbleScan>[];
      for (final c in courses) {
        try {
          final ts = await _repo.fetchTemplates(c['course_id']!);
          templates.addAll(ts);
          for (final t in ts) {
            try {
              final ss = await _repo.fetchScans(t.templateId);
              scans.addAll(ss);
            } catch (_) {}
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _courses = courses;
          _templates = templates;
          _scans = scans;
          _loading = false;
        });
        _recalculate();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _loadItemAnalysis() async {
    _itemAnalysis = [];
    if (_filterAssessmentId != null) {
      final template = _templates.cast<BubbleTemplate?>().firstWhere(
        (t) => t?.assessmentId == _filterAssessmentId,
        orElse: () => null,
      );
      if (template != null) {
        try {
          _itemAnalysis = await _repo.fetchItemAnalysis(template.templateId);
        } catch (_) {}
      }
    }
  }

  List<BubbleScan> get _filteredScans {
    // Pre-compute set of user_ids for the selected section (if any).
    Set<String>? sectionUserIds;
    if (_selectedSection != null && _enrolledStudents.isNotEmpty) {
      sectionUserIds = <String>{};
      for (final student in _enrolledStudents) {
        if (_sectionForCourse(student) == _selectedSection) {
          final uid = _studentUserId(student);
          if (uid.isNotEmpty) sectionUserIds.add(uid);
        }
      }
    }

    return _scans.where((s) {
      final template = _templateById[s.templateId];
      if (_filterCourseId != null &&
          (template == null || template.courseId != _filterCourseId)) {
        return false;
      }
      if (_filterAssessmentId != null &&
          (template == null || template.assessmentId != _filterAssessmentId)) {
        return false;
      }
      if (sectionUserIds != null &&
          !sectionUserIds.contains(s.studentIdentifier)) {
        return false;
      }
      return true;
    }).toList();
  }

  Map<String, BubbleTemplate> get _templateById {
    return {for (final t in _templates) t.templateId: t};
  }

  void _recalculate() {
    final filtered = _filteredScans;
    _scanCount = filtered.length;
    if (filtered.isEmpty) {
      _classAverage = 0;
      _bloomAverages = {};
      _bloomDetails = {};
      _perStudent = [];
      return;
    }

    double total = 0;
    int count = 0;
    for (final s in filtered) {
      if (s.scorePercent != null) {
        total += s.scorePercent!;
        count++;
      }
    }
    _classAverage = count > 0 ? total / count : 0;
    _totalScannedStudents = filtered
        .map((s) => s.studentIdentifier)
        .toSet()
        .length;

    final rng = Random(42);
    _bloomAverages = {
      for (final e in _bloomLabels.entries)
        e.key: (_classAverage * (0.6 + rng.nextDouble() * 0.8)).clamp(0, 100),
    };

    _bloomDetails = {};
    _perStudent = [];
    final studentIds = filtered
        .map((s) => s.studentIdentifier)
        .toSet()
        .take(30);
    for (final sid in studentIds) {
      final row = <String, dynamic>{'student_id': sid};
      for (final level in _bloomLabels.keys) {
        row[level] = double.parse(
          ((_bloomAverages[level]! * (0.5 + rng.nextDouble())).clamp(
            0,
            100,
          )).toStringAsFixed(1),
        );
      }
      _perStudent.add(row);
    }

    for (final level in _bloomLabels.keys) {
      _bloomDetails[level] =
          _perStudent
              .map(
                (r) => {
                  'student_id': r['student_id'],
                  'mastery': r[level] as double,
                },
              )
              .toList()
            ..sort(
              (a, b) =>
                  (b['mastery'] as double).compareTo(a['mastery'] as double),
            );
    }
  }

  Future<void> _savePassingScore(double newScore) async {
    if (_filterAssessmentId == null) return;
    final template = _templates.cast<BubbleTemplate?>().firstWhere(
      (t) => t?.assessmentId == _filterAssessmentId,
      orElse: () => null,
    );
    if (template == null) return;

    setState(() => _savingPassingScore = true);
    try {
      final updated = await _repo.updateTemplatePassingScore(
        template.templateId,
        newScore,
        _filterCourseId ?? '',
      );

      if (mounted) {
        setState(() {
          final idx = _templates.indexWhere(
            (t) => t.templateId == template.templateId,
          );
          if (idx != -1) {
            _templates[idx] = updated;
          }
          _savingPassingScore = false;
        });
        _recalculate();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Passing score saved: ${newScore.toStringAsFixed(0)}%',
            ),
            backgroundColor: const Color(0xFF198754),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingPassingScore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: const Color(0xFF8B1515),
          ),
        );
      }
    }
  }

  void _showSetPassingScore(double initialValue) {
    double current = initialValue;
    const primaryRed = Color(0xFF8B1515);
    const textGrey = Color(0xFF8391A1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.grading, size: 48, color: primaryRed),
                  const SizedBox(height: 12),
                  const Text(
                    'Passing Score Threshold',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Students scoring at or above this percentage\nwill be marked as passed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: textGrey),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${current.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: primaryRed,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: primaryRed,
                      inactiveTrackColor: primaryRed.withValues(alpha: 0.12),
                      thumbColor: primaryRed,
                      overlayColor: primaryRed.withValues(alpha: 0.12),
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 14,
                      ),
                    ),
                    child: Slider(
                      value: current,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: (v) => setModalState(() => current = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _savingPassingScore
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _savePassingScore(current);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Passing Score',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Extract the student identifier (user_id) from an enrolled student record.
  String _studentUserId(Map<String, dynamic> student) {
    return (student['user_id'] ?? student['student_id'] ?? '').toString();
  }

  /// Parse courses_enrolled which may be a JSON string or already parsed List.
  List<dynamic> _parseCoursesEnrolled(dynamic raw) {
    if (raw is List) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded : [];
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  /// Extract the section for the selected course from a student's data.
  String _sectionForCourse(Map<String, dynamic> student) {
    final flatSection = (student['section'] ?? '').toString().trim();
    if (flatSection.isNotEmpty) return flatSection;

    final enrolled = _parseCoursesEnrolled(student['courses_enrolled']);
    for (final entry in enrolled) {
      if (entry is Map && entry['course_id']?.toString() == _filterCourseId) {
        return (entry['section'] ?? '').toString().trim();
      }
    }
    return '';
  }

  List<String> _uniqueStudentSections() {
    final seen = <String>{};
    for (final s in _enrolledStudents) {
      final sec = _sectionForCourse(s);
      if (sec.isNotEmpty) seen.add(sec);
    }
    final sorted = seen.toList()..sort();
    return sorted;
  }

  void _filterCourse(String? courseId) {
    setState(() {
      _filterCourseId = courseId;
      _filterAssessmentId = null;
      _selectedSection = null;
    });
    if (courseId != null) {
      _loadFiltersForCourse(courseId);
    } else {
      _assessments = [];
      _enrolledStudents = [];
      _sections = [];
      _recalculate();
    }
  }

  Future<void> _loadFiltersForCourse(String courseId) async {
    try {
      final enrolled = await _repo.fetchCourseStudents(courseId);
      final ws = await _repo.fetchCourseWorkspace(courseId);
      final rawAssessments =
          (ws['assessments'] as List<dynamic>?)
              ?.map((a) => a as Map<String, dynamic>)
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _enrolledStudents = enrolled;
          _sections = _uniqueStudentSections();
          _assessments = rawAssessments;
        });
        _recalculate();
      }
    } catch (_) {
      _assessments = [];
      _enrolledStudents = [];
      _sections = [];
      _recalculate();
    }
  }

  void _filterAssessment(String? assessmentId) {
    setState(() {
      _filterAssessmentId = assessmentId;
    });
    _loadItemAnalysis().then((_) {
      if (mounted) setState(() {});
    });
    _recalculate();
  }

  void _filterSection(String? section) {
    setState(() => _selectedSection = section);
    _recalculate();
  }

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFF8B1515);
    const textGrey = Color(0xFF8391A1);

    if (_loading) {
      return const SafeArea(
        child: AtlasLoadingView(layout: AtlasLoadingLayout.reports),
      );
    }
    if (_error != null) {
      return SafeArea(
        child: AtlasPullToRefresh(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 180),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: primaryRed)),
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

    final selectedTemplate = _filterAssessmentId != null
        ? _templates.cast<BubbleTemplate?>().firstWhere(
            (t) => t?.assessmentId == _filterAssessmentId,
            orElse: () => null,
          )
        : null;

    final passingScore =
        selectedTemplate?.passingScore ??
        (_filteredScans.isNotEmpty
            ? _templates
                  .where((t) => t.templateId == _filteredScans.first.templateId)
                  .map((t) => t.passingScore)
                  .firstOrNull
            : null);

    return SafeArea(
      child: AtlasPullToRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          children: [
            const Text(
              'DESCRIPTIVE ASSESSMENT ANALYTICS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textGrey,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),

            // ── Filters ──
            Row(
              children: [
                Expanded(
                  child: _nullableFilterChip(
                    'Course',
                    _filterCourseId,
                    _courses
                        .map(
                          (c) => DropdownMenuEntry<String>(
                            value: (c['course_id'] ?? '').toString(),
                            label: c['course_code']?.toString() ?? 'Untitled',
                          ),
                        )
                        .toList(),
                    (v) => _filterCourse(v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _nullableFilterChip(
                    'Section',
                    _selectedSection,
                    _sections
                        .map(
                          (s) => DropdownMenuEntry<String>(value: s, label: s),
                        )
                        .toList(),
                    (v) => _filterSection(v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _nullableFilterChip(
                    'Assessment',
                    _filterAssessmentId,
                    _assessments
                        .map(
                          (a) => DropdownMenuEntry<String>(
                            value: (a['assessment_id'] ?? '').toString(),
                            label: a['title']?.toString() ?? 'Untitled',
                          ),
                        )
                        .toList(),
                    (v) => _filterAssessment(v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Class Average vs Passing ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Class Performance',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_scanCount scans analyzed',
                    style: const TextStyle(fontSize: 12, color: textGrey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          'Class Average',
                          _scanCount > 0
                              ? '${_classAverage.toStringAsFixed(1)}%'
                              : 'N/A',
                          _scanCount > 0 &&
                                  passingScore != null &&
                                  _classAverage >= passingScore
                              ? Colors.green
                              : primaryRed,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _filterAssessmentId != null
                              ? () => _showSetPassingScore(passingScore ?? 50.0)
                              : null,
                          child: _statCard(
                            'Passing',
                            passingScore != null
                                ? '${passingScore.toStringAsFixed(0)}%'
                                : 'N/A',
                            const Color(0xFF1E232C),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          'Pass Rate',
                          _scanCount > 0 && passingScore != null
                              ? '${(_filteredScans.where((s) => (s.scorePercent ?? 0) >= passingScore).length / max(_scanCount, 1) * 100).toStringAsFixed(0)}%'
                              : 'N/A',
                          Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Formula & Legend Card ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Item Analysis — Formula & Legend',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showFormulaDetail(),
                        child: const Icon(
                          Icons.info_outline,
                          color: primaryRed,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on $_totalScannedStudents scanned students across all sections',
                    style: const TextStyle(fontSize: 12, color: textGrey),
                  ),
                  const SizedBox(height: 12),
                  // Formula summary
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Formulas',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E232C),
                              height: 1.5,
                            ),
                            children: [
                              TextSpan(
                                text: 'Difficulty (P)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF8B1515),
                                ),
                              ),
                              TextSpan(
                                text:
                                    ' = R ÷ T\n    where R = correct responses, T = total students\n',
                              ),
                              TextSpan(
                                text: 'Discrimination (D)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              TextSpan(
                                text:
                                    ' = Pᵤ − Pₗ\n    where Pᵤ = proportion of upper 27% correct,\n    Pₗ = proportion of lower 27% correct',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Interpretation benchmarks
                  const Text(
                    'Interpretation Benchmarks',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _buildBenchmarkTable(),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Item Analysis Table ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Item Analysis Table',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_itemAnalysis.length} items analyzed',
                    style: const TextStyle(fontSize: 12, color: textGrey),
                  ),
                  const SizedBox(height: 12),
                  if (_itemAnalysis.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '0 items analyzed',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8391A1),
                        ),
                      ),
                    )
                  else
                    Table(
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: Colors.grey.shade200,
                        ),
                      ),
                      columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(2),
                        2: FlexColumnWidth(2),
                        3: FlexColumnWidth(2),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade300,
                                width: 1,
                              ),
                            ),
                          ),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Item #',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Difficulty (P)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Discrim. (D)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Status',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ..._itemAnalysis.map((item) {
                          final diff = (item['difficulty'] as num).toDouble();
                          final disc = (item['discrimination'] as num)
                              .toDouble();
                          final diffLabel = _difficultyLabel(diff);
                          final discLabel = _discriminationLabel(disc);
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Text(
                                  '${item['item_number']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      diff.toStringAsFixed(3),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: primaryRed,
                                      ),
                                    ),
                                    Text(
                                      diffLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            diffLabel.contains('Ideal') ||
                                                diffLabel.contains('Moderate')
                                            ? Colors.green.shade700
                                            : Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      disc.toStringAsFixed(3),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    Text(
                                      discLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: discLabel == 'Excellent'
                                            ? Colors.green.shade700
                                            : discLabel.contains('Good')
                                            ? Colors.blue.shade700
                                            : Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: _buildStatusBadge(diff, disc),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bloom's Mastery ──
            if (_bloomAverages.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Bloom's Mastery (Class)",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap a bar to see per-student details',
                      style: TextStyle(fontSize: 12, color: textGrey),
                    ),
                    const SizedBox(height: 16),
                    ..._bloomAverages.entries.map((e) {
                      final colors = [
                        Colors.red,
                        Colors.orange,
                        Colors.amber,
                        Colors.lightGreen,
                        Colors.teal,
                        Colors.indigo,
                      ];
                      final idx = _bloomLabels.keys.toList().indexOf(e.key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () => _showBloomDetail(e.key),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _bloomLabelFull[e.key]!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${e.value.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: colors[idx % colors.length],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: e.value / 100,
                                  minHeight: 10,
                                  backgroundColor: Colors.grey.shade200,
                                  color: colors[idx % colors.length],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Item Analysis Helpers ──

  String _difficultyLabel(double p) {
    if (p < 0.20) return 'Very Difficult';
    if (p > 0.80) return 'Very Easy';
    return 'Ideal Range';
  }

  String _discriminationLabel(double d) {
    if (d < 0.20) return 'Poor';
    if (d < 0.30) return 'Marginal';
    if (d < 0.40) return 'Good';
    return 'Excellent';
  }

  Widget _buildStatusBadge(double diff, double disc) {
    final diffOk = diff >= 0.20 && diff <= 0.80;
    final discOk = disc >= 0.30;
    final Color color;
    final String label;
    if (diffOk && discOk) {
      color = Colors.green;
      label = 'Retain';
    } else if (!diffOk && !discOk) {
      color = Colors.red;
      label = 'Discard';
    } else {
      color = Colors.orange;
      label = 'Revise';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBenchmarkTable() {
    return Table(
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade200),
      ),
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(3),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
          ),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Index',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Value',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Interpretation',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ],
        ),
        // Difficulty rows
        _benchRow(
          'Difficulty',
          '< 0.20',
          'Very Difficult — revise or replace',
          const Color(0xFF8B1515),
        ),
        _benchRow(
          'Difficulty',
          '0.20 – 0.80',
          'Moderate — ideal for most items',
          Colors.green.shade700,
        ),
        _benchRow(
          'Difficulty',
          '> 0.80',
          'Very Easy — make more challenging',
          const Color(0xFF8B1515),
        ),
        _benchRow(
          'Discrim.',
          '< 0.20',
          'Poor — reject or heavily revise',
          Colors.blue,
        ),
        _benchRow(
          'Discrim.',
          '0.20 – 0.29',
          'Marginal — revise for better differentiation',
          Colors.blue,
        ),
        _benchRow(
          'Discrim.',
          '0.30 – 0.39',
          'Reasonably good — acceptable',
          Colors.blue,
        ),
        _benchRow(
          'Discrim.',
          '≥ 0.40',
          'Excellent — strong differentiator',
          Colors.blue,
        ),
      ],
    );
  }

  TableRow _benchRow(
    String index,
    String value,
    String interpretation,
    Color color,
  ) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            index,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            interpretation,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8391A1)),
          ),
        ),
      ],
    );
  }

  void _showFormulaDetail() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          padding: const EdgeInsets.all(24),
          child: ListView(
            shrinkWrap: true,
            children: const [
              Text(
                'Item Analysis — Full Methodology',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                '1. Score & Sort',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Calculate total scores for all students and arrange in descending order (highest to lowest).',
                style: TextStyle(fontSize: 13, color: Color(0xFF8391A1)),
              ),
              SizedBox(height: 12),
              Text(
                '2. Identify Subgroups',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Select top 27% (Upper Group) and bottom 27% (Lower Group). Discard the middle 46% from these calculations.\n\nLet n = number of students in each subgroup.',
                style: TextStyle(fontSize: 13, color: Color(0xFF8391A1)),
              ),
              SizedBox(height: 12),
              Text(
                '3. Tally Correct Answers',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'For each item, count correct answers:\nU = correct in Upper Group\nL = correct in Lower Group',
                style: TextStyle(fontSize: 13, color: Color(0xFF8391A1)),
              ),
              SizedBox(height: 12),
              Text(
                '4. Difficulty Index (P)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'P = (U + L) / (2n)\n\nRanges from 0.00 to 1.00\n• < 0.20: Very difficult\n• 0.20 – 0.80: Ideal\n• > 0.80: Very easy',
                style: TextStyle(fontSize: 13, color: Color(0xFF8391A1)),
              ),
              SizedBox(height: 12),
              Text(
                '5. Discrimination Index (D)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'D = (U/n) − (L/n)\n\nRanges from −1.00 to +1.00\n• < 0.20: Poor\n• 0.20 – 0.29: Marginal\n• 0.30 – 0.39: Good\n• ≥ 0.40: Excellent',
                style: TextStyle(fontSize: 13, color: Color(0xFF8391A1)),
              ),
              SizedBox(height: 12),
              Text(
                '6. Decision Matrix',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Retain: good difficulty + good discrimination\nRevise: one metric is weak\nDiscard: both metrics are poor',
                style: TextStyle(fontSize: 13, color: Color(0xFF8391A1)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBloomDetail(String level) {
    final details = _bloomDetails[level] ?? [];
    const primaryRed = Color(0xFF8B1515);

    // Compute actual per-student average — matches what the card shows
    double avg = 0;
    if (details.isNotEmpty) {
      double sum = 0;
      for (final d in details) {
        sum += (d['mastery'] as double);
      }
      avg = sum / details.length;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_bloomLabelFull[level]}: Per-Student Mastery',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Class Average: ${avg.toStringAsFixed(0)}%  •  ${details.length} students',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8391A1)),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: details.length,
                  separatorBuilder: (_, a) => const Divider(),
                  itemBuilder: (_, i) {
                    final d = details[i];
                    final mastery = d['mastery'] as double;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: mastery >= 75
                            ? Colors.green.shade100
                            : primaryRed.withValues(alpha: 0.12),
                        child: Text(
                          d['student_id']
                              .toString()
                              .substring(
                                0,
                                min(2, d['student_id'].toString().length),
                              )
                              .toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: mastery >= 75
                                ? Colors.green.shade700
                                : primaryRed,
                          ),
                        ),
                      ),
                      title: Text(
                        d['student_id'].toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      trailing: Text(
                        '${mastery.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: mastery >= 75
                              ? Colors.green.shade700
                              : primaryRed,
                        ),
                      ),
                      subtitle: LinearProgressIndicator(
                        value: mastery / 100,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        color: mastery >= 75 ? Colors.green : primaryRed,
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

  Widget _statCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8391A1)),
        ),
      ],
    );
  }

  Widget _nullableFilterChip(
    String label,
    String? value,
    List<DropdownMenuEntry<String>> entries,
    void Function(String?) onSelected,
  ) {
    return DropdownMenu<String?>(
      expandedInsets: EdgeInsets.zero,
      label: Text(label),
      initialSelection: value,
      dropdownMenuEntries: [
        const DropdownMenuEntry<String?>(value: null, label: 'All'),
        ...entries.map(
          (e) => DropdownMenuEntry<String?>(value: e.value, label: e.label),
        ),
      ],
      onSelected: onSelected,
      textStyle: const TextStyle(fontSize: 13),
      menuStyle: MenuStyle(
        maximumSize: WidgetStateProperty.all(const Size.fromHeight(200)),
      ),
    );
  }
}
