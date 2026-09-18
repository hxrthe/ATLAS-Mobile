import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_loading_view.dart';
import '../grading/grading_repository.dart';

class CourseDetailScreen extends StatefulWidget {
  final String courseId;
  final String courseCode;
  final String courseTitle;
  final VoidCallback onBack;

  const CourseDetailScreen({
    super.key,
    required this.courseId,
    required this.courseCode,
    required this.courseTitle,
    required this.onBack,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GradingRepository _repo = GradingRepository();

  List<Map<String, dynamic>> _assessments = [];
  String? _selectedAssessmentId;

  List<Map<String, dynamic>> _items = [];
  Map<String, String> _localAnswerKey = {};
  bool _loadingEM = true;
  String? _emError;
  int _emSubTab = 0;

  List<Map<String, dynamic>> _scoreRows = [];
  List<Map<String, dynamic>> _enrolledStudents = [];
  bool _loadingScores = false;
  String? _scoresError;
  String? _scoreSectionFilter;

  double? _passingScore;
  bool _loadingPassingScore = false;
  bool _savingPassingScore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadWorkspace();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    debugPrint(
      'Tab changed to: ${_tabController.index}, selectedAssessment: $_selectedAssessmentId, scoreRows: ${_scoreRows.length}',
    );
    if (_tabController.index == 1 &&
        _scoreRows.isEmpty &&
        !_loadingScores &&
        _selectedAssessmentId != null) {
      _loadScores();
    }
    setState(() {});
  }

  Future<void> _loadWorkspace() async {
    setState(() {
      _loadingEM = true;
      _emError = null;
    });
    try {
      final ws = await _repo.fetchCourseWorkspace(widget.courseId);
      final rawAssessments =
          (ws['assessments'] as List<dynamic>?)
              ?.map((a) => a as Map<String, dynamic>)
              .toList() ??
          [];

      // Fetch enrolled students from dedicated endpoint
      final enrolled = await _repo.fetchCourseStudents(widget.courseId);

      String? selId;
      if (rawAssessments.isNotEmpty)
        selId = rawAssessments.first['assessment_id']?.toString();

      if (mounted) {
        setState(() {
          _assessments = rawAssessments;
          _enrolledStudents = enrolled;
          _selectedAssessmentId = selId;
        });
        if (selId != null) {
          await _loadAssessmentItems(selId);
        } else {
          setState(() => _loadingEM = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingEM = false;
          _emError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _loadAssessmentItems(String assessmentId) async {
    try {
      final detail = await _repo.fetchAssessmentDetail(assessmentId);
      final rawItems =
          (detail['items'] as List<dynamic>?)
              ?.map((i) => i as Map<String, dynamic>)
              .toList() ??
          [];
      final key = <String, String>{};
      for (final item in rawItems) {
        final itemId = (item['item_id'] ?? '').toString();
        final answer = (item['correct_answer'] ?? '').toString().trim();
        if (itemId.isNotEmpty && answer.isNotEmpty) {
          key[itemId] = answer;
        }
      }

      if (mounted) {
        setState(() {
          _items = rawItems;
          _localAnswerKey = key;
          _loadingEM = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingEM = false;
          _emError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _onAssessmentChanged(String? newId) async {
    if (newId == null || newId == _selectedAssessmentId) return;
    setState(() {
      _selectedAssessmentId = newId;
      _loadingEM = true;
      _scoreRows = [];
      _scoresError = null;
      _passingScore = null;
      _loadingPassingScore = false;
    });
    await _loadAssessmentItems(newId);
    if (_tabController.index == 1) await _loadScores();
  }

  Future<void> _loadScores() async {
    if (_selectedAssessmentId == null) return;
    setState(() {
      _loadingScores = true;
      _scoresError = null;
    });
    try {
      final data = await _repo.fetchStudentScores(
        widget.courseId,
        _selectedAssessmentId!,
      );
      final rawStudents =
          (data['students'] as List<dynamic>?) ??
          (data['rows'] as List<dynamic>?) ??
          [];
      final rows =
          rawStudents.map((r) => r as Map<String, dynamic>).toList();
      debugPrint('Score rows: $rows');
      if (mounted) {
        setState(() {
          _scoreRows = rows;
          _loadingScores = false;
        });
      }
    } catch (e) {
      debugPrint('Load scores error: $e');
      if (mounted) {
        setState(() {
          _loadingScores = false;
          _scoresError = _friendlyScoresError(e);
        });
      }
    }
  }

  String _friendlyScoresError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
      final status = e.response?.statusCode;
      if (status != null) {
        return 'Could not load scores (server error $status). Please retry.';
      }
      return 'Could not load scores. Check your connection and retry.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }

  Future<void> _saveAnswerKey() async {
    if (_selectedAssessmentId == null) return;
    try {
      for (final item in _items) {
        final itemId = (item['item_id'] ?? '').toString();
        final newAnswer = _localAnswerKey[itemId];
        if (newAnswer != null && newAnswer.isNotEmpty) {
          await _repo.updateAssessmentItem(itemId, {
            'correct_answer': newAnswer,
          });
        }
      }
      if (mounted) {
        final c = context.atlas;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Answer key saved'),
            backgroundColor: c.correct,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: context.atlas.primary,
          ),
        );
      }
    }
  }

  void _cycleAnswer(String itemId) {
    const choices = ['A', 'B', 'C', 'D'];
    final cur = _localAnswerKey[itemId] ?? '';
    if (cur.isEmpty) {
      setState(() => _localAnswerKey[itemId] = 'A');
    } else {
      final next = choices[(choices.indexOf(cur) + 1) % choices.length];
      setState(() => _localAnswerKey[itemId] = next);
    }
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

  /// Extract the section for the current course from a student's data.
  String _sectionForCourse(Map<String, dynamic> student) {
    // First try flat 'section' field (if backend flattens it)
    final flatSection = (student['section'] ?? '').toString().trim();
    if (flatSection.isNotEmpty) return flatSection;

    // Parse courses_enrolled (may be JSON string or list)
    final enrolled = _parseCoursesEnrolled(student['courses_enrolled']);
    for (final entry in enrolled) {
      if (entry is Map && entry['course_id']?.toString() == widget.courseId) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.atlas.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            _buildBreadcrumb(),
            _buildCourseCard(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildEMTab(), _buildScoresTab()],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _tabController.index == 0
          ? _buildEMBottomBar()
          : _buildScoresBottomBar(),
    );
  }

  Widget _buildBreadcrumb() {
    final c = context.atlas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: c.card,
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios, size: 16, color: c.primary),
                const SizedBox(width: 4),
                Text(
                  'Courses',
                  style: TextStyle(
                    fontSize: 14,
                    color: c.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              ' / ',
              style: TextStyle(color: c.textSecondary, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              '${widget.courseCode} / ${_tabController.index == 0 ? 'Evaluation Materials' : 'Students & Scores'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard() {
    final c = context.atlas;
    final onHero = c.onPrimary.withValues(alpha: 0.85);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.primary, const Color(0xFF5A0C0C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.courseCode,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: c.onPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.courseTitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: onHero,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoChip(Icons.assignment, '${_assessments.length} assessments', onHero),
              const SizedBox(width: 12),
              _infoChip(Icons.quiz, '${_items.length} items', onHero),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _buildTabBar() {
    final c = context.atlas;
    return Container(
      color: c.card,
      margin: const EdgeInsets.only(top: 16),
      child: TabBar(
        controller: _tabController,
        labelColor: c.primary,
        unselectedLabelColor: c.textSecondary,
        indicatorColor: c.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: const [
          Tab(text: 'Evaluation Materials'),
          Tab(text: 'Students & Scores'),
        ],
      ),
    );
  }

  // ═══ EM Tab ══════════════════════════════════════════════════════════

  Widget _buildEMTab() {
    final c = context.atlas;
    if (_loadingEM) {
      return const AtlasLoadingView(layout: AtlasLoadingLayout.list);
    }
    if (_emError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_emError!, style: TextStyle(color: c.primary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadWorkspace,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No items for this assessment',
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: c.card,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _subTabBtn('Questions', 0, c),
              const SizedBox(width: 8),
              _subTabBtn('Answer Key', 1, c),
              const SizedBox(width: 8),
              _subTabBtn('Passing Score', 2, c),
            ],
          ),
        ),
        Expanded(child: _buildEMSubPanel()),
      ],
    );
  }

  Widget _buildEMSubPanel() {
    switch (_emSubTab) {
      case 1:
        return _buildAnswerKeyPanel();
      case 2:
        return _buildPassingScorePanel();
      default:
        return _buildQuestionsList();
    }
  }

  Widget _subTabBtn(String label, int index, AtlasColors c) {
    final active = index == _emSubTab;
    return GestureDetector(
      onTap: () {
        setState(() => _emSubTab = index);
        if (index == 2 && _passingScore == null && !_loadingPassingScore)
          _loadPassingScore();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? c.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? c.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionsList() {
    final c = context.atlas;
    List<Map<String, dynamic>> filtered = _items;

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No questions for this assessment',
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final item = filtered[i];
        final itemId = (item['item_id'] ?? '').toString();
        final qNum = (item['item_number'] ?? (i + 1)).toString();
        final answer = _localAnswerKey[itemId] ?? '';
        final section = (item['section_title'] ?? '').toString().trim();
        final choices =
            (item['choices'] as List<dynamic>?)
                ?.map((c) => c.toString())
                .toList() ??
            [];

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    qNum,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: c.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (section.isNotEmpty)
                      Text(
                        section,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      item['question_text'] ?? 'Item $qNum',
                      style: TextStyle(fontSize: 14, color: c.textPrimary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (choices.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: choices
                            .map(
                              (choice) => Text(
                                choice,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.textSecondary,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (answer.isNotEmpty) ...[
                const SizedBox(width: 8),
                _answerBadge(answer, c),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _answerBadge(String letter, AtlasColors c) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.primary,
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: c.onPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerKeyPanel() {
    final c = context.atlas;
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No items in assessment',
          style: TextStyle(color: c.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final item = _items[i];
              final itemId = (item['item_id'] ?? '').toString();
              final itemNum = (item['item_number'] ?? (i + 1)).toString();
              final answer = _localAnswerKey[itemId] ?? '';
              return GestureDetector(
                onTap: () => _cycleAnswer(itemId),
                child: Container(
                  decoration: BoxDecoration(
                    color: answer.isNotEmpty
                        ? c.primary.withValues(alpha: 0.08)
                        : c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: answer.isNotEmpty ? c.primary : c.border,
                      width: answer.isNotEmpty ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        itemNum,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        answer.isNotEmpty ? answer : '?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: answer.isNotEmpty ? c.primary : c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveAnswerKey,
              icon: const Icon(Icons.save, size: 18),
              label: const Text(
                'Save Answer Key',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══ Passing Score ═══════════════════════════════════════════════════

  Future<void> _loadPassingScore() async {
    if (_selectedAssessmentId == null) return;
    setState(() => _loadingPassingScore = true);
    try {
      final template = await _repo.fetchTemplateByAssessment(
        _selectedAssessmentId!,
      );
      if (mounted) {
        setState(() {
          _passingScore = template.passingScore ?? 50;
          _loadingPassingScore = false;
        });
      }
    } catch (_) {
      // Template may not exist yet — default to 50%
      if (mounted) {
        setState(() {
          _passingScore = 50;
          _loadingPassingScore = false;
        });
      }
    }
  }

  Future<void> _savePassingScore() async {
    if (_selectedAssessmentId == null || _passingScore == null) return;
    setState(() => _savingPassingScore = true);
    try {
      // Always fetch template to guarantee a valid course_id
      final template = await _repo.fetchTemplateByAssessment(
        _selectedAssessmentId!,
      );
      final templateId = template.templateId;
      final courseId = template.courseId.isNotEmpty
          ? template.courseId
          : widget.courseId;
      if (courseId.isEmpty) throw Exception('course_id is required');
      await _repo.updateTemplatePassingScore(
        templateId,
        _passingScore!,
        courseId,
      );
      if (mounted) {
        final c = context.atlas;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Passing score saved: ${_passingScore!.toStringAsFixed(0)}%',
            ),
            backgroundColor: c.correct,
          ),
        );
      }
    } catch (e) {
      String msg;
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          msg =
              body['detail']?.toString() ??
              body['passing_score']?.toString() ??
              body.values.first?.toString() ??
              'Failed to save';
        } else {
          msg = e.message ?? 'Failed to save';
        }
      } else {
        msg = e.toString().replaceAll('Exception: ', '');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: context.atlas.primary,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassingScore = false);
    }
  }

  Widget _buildPassingScorePanel() {
    final c = context.atlas;
    if (_loadingPassingScore) {
      return const Center(child: CircularProgressIndicator());
    }

    final current = _passingScore ?? 50;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
                boxShadow: [
                  BoxShadow(
                    color: c.textPrimary.withValues(alpha: 0.04),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(Icons.grading, size: 48, color: c.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Passing Score Threshold',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Students scoring at or above this percentage\nwill be marked as passed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${current.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: c.primary,
                      inactiveTrackColor: c.primary.withValues(alpha: 0.12),
                      thumbColor: c.primary,
                      overlayColor: c.primary.withValues(alpha: 0.12),
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
                      onChanged: (v) => setState(() => _passingScore = v),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0%',
                        style: TextStyle(fontSize: 11, color: c.textSecondary),
                      ),
                      Text(
                        '100%',
                        style: TextStyle(fontSize: 11, color: c.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Quick-set buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [50, 60, 70, 75].map((v) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _passingScore = v.toDouble()),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: current == v
                                  ? c.primary
                                  : c.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$v%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: current == v ? c.onPrimary : c.primary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingPassingScore ? null : _savePassingScore,
                icon: _savingPassingScore
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  _savingPassingScore ? 'Saving...' : 'Save Passing Score',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══ Scores Tab ══════════════════════════════════════════════════════

  Widget _buildScoresTab() {
    final c = context.atlas;
    if (_loadingScores) {
      return const AtlasLoadingView(layout: AtlasLoadingLayout.list);
    }
    if (_scoresError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_scoresError!, style: TextStyle(color: c.primary)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadScores, child: const Text('Retry')),
          ],
        ),
      );
    }

    // Merge enrolled students with scores
    List<Map<String, dynamic>> displayRows = [];

    debugPrint('=== Scores Tab Debug ===');
    debugPrint('Enrolled students count: ${_enrolledStudents.length}');
    debugPrint('Score rows count: ${_scoreRows.length}');
    debugPrint('Course ID: ${widget.courseId}');
    if (_enrolledStudents.isNotEmpty) {
      final first = _enrolledStudents.first;
      debugPrint('First enrolled student keys: ${first.keys.toList()}');
      debugPrint('First enrolled student user_id: ${_studentUserId(first)}');
      debugPrint('First enrolled student sr_code: ${first['sr_code']}');
      debugPrint(
        'First enrolled student section: "${_sectionForCourse(first)}"',
      );
    }
    if (_scoreRows.isNotEmpty) {
      debugPrint('First score row keys: ${_scoreRows.first.keys.toList()}');
      debugPrint('First score row: ${_scoreRows.first}');
    }
    debugPrint('========================');

    // Filter enrolled students by section if applicable
    List<Map<String, dynamic>> filteredStudents = _enrolledStudents;
    if (_scoreSectionFilter != null && _scoreSectionFilter!.isNotEmpty) {
      filteredStudents = filteredStudents
          .where((s) => _sectionForCourse(s) == _scoreSectionFilter)
          .toList();
    }

    for (final student in filteredStudents) {
      final userId = _studentUserId(student);
      final srCode = (student['sr_code'] ?? student['sr-code'] ?? userId)
          .toString();
      final section = _sectionForCourse(student);

      // Match by platform user UUID or SR code (bubble sheets store SR codes)
      final scoreMatch = _scoreRows.firstWhere((r) {
        final sid =
            (r['student_id'] ?? r['user_id'] ?? r['student_identifier'] ?? '')
                .toString();
        return sid == userId || (srCode.isNotEmpty && sid == srCode);
      }, orElse: () => {});

      if (scoreMatch.isNotEmpty) {
        displayRows.add(
          Map<String, dynamic>.from(scoreMatch)
            ..['section'] = section
            ..['sr_code'] = srCode,
        );
      } else {
        displayRows.add({
          'student_id': userId,
          'sr_code': srCode,
          'section': section,
          'score': null,
          'percent': null,
          'assessment_title':
              _assessments.firstWhere(
                (a) =>
                    (a['assessment_id'] ?? '').toString() ==
                    _selectedAssessmentId,
                orElse: () => {},
              )['title'] ??
              'Score',
        });
      }
    }

    // Keep scanned scores that did not match an enrolled student (unknown SR code)
    final matchedIds = {
      for (final r in displayRows)
        (r['student_id'] ?? r['sr_code'] ?? '').toString(),
    }..removeWhere((id) => id.isEmpty);
    for (final score in _scoreRows) {
      final sid =
          (score['student_id'] ?? score['student_identifier'] ?? '').toString();
      if (sid.isNotEmpty && matchedIds.contains(sid)) continue;
      displayRows.add({
        ...Map<String, dynamic>.from(score),
        'sr_code': sid.isNotEmpty ? sid : (score['sr_code'] ?? '—'),
        'section': score['section'] ?? '',
      });
      if (sid.isNotEmpty) matchedIds.add(sid);
    }

    if (displayRows.isEmpty) {
      return Center(
        child: Text('No students found', style: TextStyle(color: c.textSecondary)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            c.primary.withValues(alpha: 0.06),
          ),
          dataRowColor: WidgetStateProperty.all(c.card),
          border: TableBorder.all(
            color: c.border,
            borderRadius: BorderRadius.circular(8),
          ),
          columns: [
            DataColumn(
              label: Text(
                'SR Code',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: c.textPrimary,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Section',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: c.textPrimary,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                (displayRows.isNotEmpty &&
                        (displayRows.first['assessment_title'] ?? '')
                            .toString()
                            .isNotEmpty)
                    ? displayRows.first['assessment_title'].toString()
                    : 'Score',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
          rows: displayRows.map((r) {
            final sid = (r['sr_code'] ?? r['student_id'] ?? '').toString();
            final sec = (r['section'] ?? '').toString();
            final score = r['score'];
            final pct = r['percent'];
            final hasScore = pct != null || score != null;
            final display = pct != null
                ? '${(pct as num).toStringAsFixed(0)}%'
                : score != null
                ? (score as num).toStringAsFixed(1)
                : '-';
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    sid,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    sec,
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ),
                DataCell(
                  Center(
                    child: Text(
                      display,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: hasScore ? c.textPrimary : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ═══ Bottom Bars ══════════════════════════════════════════════════════

  Widget _buildEMBottomBar() {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedAssessmentId,
                decoration: InputDecoration(
                  labelText: 'Assessment',
                  labelStyle: TextStyle(color: c.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  filled: true,
                  fillColor: c.inputFill,
                ),
                isExpanded: true,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
                dropdownColor: c.card,
                items: _assessments
                    .map(
                      (a) => DropdownMenuItem<String>(
                        value: (a['assessment_id'] ?? '').toString(),
                        child: Text(
                          a['title']?.toString() ?? 'Untitled',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _onAssessmentChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoresBottomBar() {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedAssessmentId,
                decoration: InputDecoration(
                  labelText: 'Assessment',
                  labelStyle: TextStyle(color: c.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  filled: true,
                  fillColor: c.inputFill,
                ),
                isExpanded: true,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
                dropdownColor: c.card,
                items: _assessments
                    .map(
                      (a) => DropdownMenuItem<String>(
                        value: (a['assessment_id'] ?? '').toString(),
                        child: Text(
                          a['title']?.toString() ?? 'Untitled',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _onAssessmentChanged,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _scoreSectionFilter,
                decoration: InputDecoration(
                  labelText: 'Section',
                  labelStyle: TextStyle(color: c.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.border),
                  ),
                  filled: true,
                  fillColor: c.inputFill,
                ),
                isExpanded: true,
                style: TextStyle(fontSize: 13, color: c.textPrimary),
                dropdownColor: c.card,
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All Sections'),
                  ),
                  ..._uniqueStudentSections().map(
                    (s) => DropdownMenuItem<String>(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _scoreSectionFilter = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
