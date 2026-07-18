import 'dart:math';
import 'package:flutter/material.dart';
import '../../grading/grading_repository.dart';
import '../../grading/models.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final GradingRepository _repo = GradingRepository();
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _assessments = [];
  List<BubbleTemplate> _templates = [];
  List<BubbleScan> _scans = [];

  String? _filterCourseId;
  String? _filterAssessmentId;
  String? _filterTemplateId;

  double _classAverage = 0;
  int _scanCount = 0;
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

  Future<void> _loadAssessments(String courseId) async {
    try {
      final items = await _repo.fetchAssessments(courseId);
      if (mounted) setState(() => _assessments = items);
    } catch (_) {}
  }

  List<BubbleScan> get _filteredScans {
    return _scans.where((s) {
      if (_filterTemplateId != null &&
          s.templateId != _filterTemplateId) {
        return false;
      }
      return true;
    }).toList();
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

    // Simulated Bloom's mastery data
    final rng = Random(42);
    _bloomAverages = {
      for (final e in _bloomLabels.entries)
        e.key: (_classAverage * (0.6 + rng.nextDouble() * 0.8)).clamp(0, 100),
    };

    // Per-student simulated mastery
    _bloomDetails = {};
    _perStudent = [];
    final studentIds = filtered.map((s) => s.studentIdentifier).toSet().take(30);
    for (final sid in studentIds) {
      final row = <String, dynamic>{'student_id': sid};
      for (final level in _bloomLabels.keys) {
        row[level] = double.parse(
            ((_bloomAverages[level]! * (0.5 + rng.nextDouble())).clamp(0, 100))
                .toStringAsFixed(1));
      }
      _perStudent.add(row);
    }

    for (final level in _bloomLabels.keys) {
      _bloomDetails[level] = _perStudent
          .map((r) => {
                'student_id': r['student_id'],
                'mastery': r[level] as double,
              })
          .toList()
        ..sort((a, b) => (b['mastery'] as double).compareTo(a['mastery'] as double));
    }
  }

  void _filterCourse(String? courseId) {
    setState(() {
      _filterCourseId = courseId;
      _filterAssessmentId = null;
      _filterTemplateId = null;
      if (courseId != null) {
        _loadAssessments(courseId);
      } else {
        _assessments = [];
      }
    });
    _recalculate();
  }

  void _filterAssessment(String? assessmentId) {
    setState(() => _filterAssessmentId = assessmentId);
  }

  void _filterTemplate(String? templateId) {
    setState(() => _filterTemplateId = templateId);
    _recalculate();
  }

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFF8B1515);
    const textGrey = Color(0xFF8391A1);

    if (_loading) {
      return const SafeArea(
          child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: primaryRed)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final passingScore = _filteredScans.isNotEmpty
        ? _templates
            .where((t) => t.templateId == _filteredScans.first.templateId)
            .map((t) => t.passingScore)
            .firstOrNull
        : null;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            const Text(
              'PRESCRIPTIVE ASSESSMENT ANALYTICS',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: textGrey,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),

            // ── Filters ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _nullableFilterChip('Course', _filterCourseId,
                    _courses.map((c) => DropdownMenuEntry<String>(value: c['course_id'] ?? '', label: c['course_code'] ?? '')).toList(),
                    (v) => _filterCourse(v)),
                _nullableFilterChip('Assessment', _filterAssessmentId,
                    _assessments.map((a) => DropdownMenuEntry<String>(value: a['assessment_id'] ?? '', label: a['title'] ?? '')).toList(),
                    (v) => _filterAssessment(v)),
                _nullableFilterChip('Template', _filterTemplateId,
                    _templates.where((t) => _filterCourseId == null || t.courseId == _filterCourseId).map((t) => DropdownMenuEntry<String>(value: t.templateId, label: t.name)).toList(),
                    (v) => _filterTemplate(v)),
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
                      color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Class Performance',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('$_scanCount scans analyzed',
                      style:
                          const TextStyle(fontSize: 12, color: textGrey)),
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
                        child: _statCard(
                          'Passing',
                          passingScore != null
                              ? '${passingScore.toStringAsFixed(0)}%'
                              : 'N/A',
                          const Color(0xFF1E232C),
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
                        blurRadius: 10)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Bloom's Mastery (Class)",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text('Tap a bar to see per-student details',
                        style:
                            TextStyle(fontSize: 12, color: textGrey)),
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
                      final idx =
                          _bloomLabels.keys.toList().indexOf(e.key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          onTap: () =>
                              _showBloomDetail(e.key),
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
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${e.value.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: colors[idx % colors.length]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: e.value / 100,
                                  minHeight: 10,
                                  backgroundColor:
                                      Colors.grey.shade200,
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

  void _showBloomDetail(String level) {
    final details = _bloomDetails[level] ?? [];
    const primaryRed = Color(0xFF8B1515);
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
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${details.length} students',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF8391A1)),
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
                        backgroundColor:
                            mastery >= 75 ? Colors.green.shade100 : primaryRed.withValues(alpha: 0.12),
                        child: Text(
                          d['student_id'].toString().substring(0, min(2, d['student_id'].toString().length)).toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: mastery >= 75 ? Colors.green.shade700 : primaryRed,
                          ),
                        ),
                      ),
                      title: Text(
                        d['student_id'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                      ),
                      trailing: Text(
                        '${mastery.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color:
                              mastery >= 75 ? Colors.green.shade700 : primaryRed,
                        ),
                      ),
                      subtitle: LinearProgressIndicator(
                        value: mastery / 100,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        color:
                            mastery >= 75 ? Colors.green : primaryRed,
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
        Text(value,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF8391A1))),
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
      label: Text(label),
      initialSelection: value,
      dropdownMenuEntries: [
        const DropdownMenuEntry<String?>(value: null, label: 'All'),
        ...entries.map((e) => DropdownMenuEntry<String?>(value: e.value, label: e.label)),
      ],
      onSelected: onSelected,
      textStyle: const TextStyle(fontSize: 13),
      menuStyle: MenuStyle(
        maximumSize: WidgetStateProperty.all(
            const Size.fromHeight(200)),
      ),
    );
  }
}
