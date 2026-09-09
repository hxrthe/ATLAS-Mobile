import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../grading/grading_repository.dart';
import '../../core/widgets/atlas_loading_view.dart';

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

  static const primaryRed = Color(0xFF8B1515);
  static const textGrey = Color(0xFF8391A1);
  static const darkText = Color(0xFF1E232C);

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Answer key saved'),
            backgroundColor: Color(0xFF198754),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: primaryRed),
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
      backgroundColor: const Color(0xFFF4F6F9),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBack,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios, size: 16, color: primaryRed),
                SizedBox(width: 4),
                Text(
                  'Courses',
                  style: TextStyle(
                    fontSize: 14,
                    color: primaryRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(' / ', style: TextStyle(color: textGrey, fontSize: 14)),
          ),
          Expanded(
            child: Text(
              '${widget.courseCode} / ${_tabController.index == 0 ? 'Evaluation Materials' : 'Students & Scores'}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: darkText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryRed, Color(0xFF5A0C0C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryRed.withValues(alpha: 0.25),
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
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.courseTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _infoChip(Icons.assignment, '${_assessments.length} assessments'),
              const SizedBox(width: 12),
              _infoChip(Icons.quiz, '${_items.length} items'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 16),
      child: TabBar(
        controller: _tabController,
        labelColor: primaryRed,
        unselectedLabelColor: textGrey,
        indicatorColor: primaryRed,
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
    if (_loadingEM) {
      return const AtlasLoadingView(layout: AtlasLoadingLayout.list);
    }
    if (_emError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_emError!, style: const TextStyle(color: primaryRed)),
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
      return const Center(
        child: Text(
          'No items for this assessment',
          style: TextStyle(color: textGrey),
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _subTabBtn('Questions', 0),
              const SizedBox(width: 8),
              _subTabBtn('Answer Key', 1),
              const SizedBox(width: 8),
              _subTabBtn('Passing Score', 2),
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

  Widget _subTabBtn(String label, int index) {
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
              ? primaryRed.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? primaryRed : textGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionsList() {
    List<Map<String, dynamic>> filtered = _items;

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No questions for this assessment',
          style: TextStyle(color: textGrey),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8ECF4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: primaryRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    qNum,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryRed,
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
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: textGrey,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      item['question_text'] ?? 'Item $qNum',
                      style: const TextStyle(fontSize: 14, color: darkText),
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
                              (c) => Text(
                                c,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: textGrey,
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
                _answerBadge(answer),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _answerBadge(String letter) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: primaryRed,
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerKeyPanel() {
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'No items in assessment',
          style: TextStyle(color: textGrey),
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
                        ? primaryRed.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: answer.isNotEmpty
                          ? primaryRed
                          : const Color(0xFFE8ECF4),
                      width: answer.isNotEmpty ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        itemNum,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: darkText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        answer.isNotEmpty ? answer : '?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: answer.isNotEmpty ? primaryRed : textGrey,
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
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Passing score saved: ${_passingScore!.toStringAsFixed(0)}%',
            ),
            backgroundColor: const Color(0xFF198754),
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
          SnackBar(content: Text(msg), backgroundColor: primaryRed),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassingScore = false);
    }
  }

  Widget _buildPassingScorePanel() {
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
                      onChanged: (v) => setState(() => _passingScore = v),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0%',
                        style: const TextStyle(fontSize: 11, color: textGrey),
                      ),
                      Text(
                        '100%',
                        style: const TextStyle(fontSize: 11, color: textGrey),
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
                                  ? primaryRed
                                  : primaryRed.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$v%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: current == v ? Colors.white : primaryRed,
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
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  _savingPassingScore ? 'Saving...' : 'Save Passing Score',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryRed,
                  foregroundColor: Colors.white,
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
    if (_loadingScores) {
      return const AtlasLoadingView(layout: AtlasLoadingLayout.list);
    }
    if (_scoresError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_scoresError!, style: const TextStyle(color: primaryRed)),
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
      return const Center(
        child: Text('No students found', style: TextStyle(color: textGrey)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            primaryRed.withValues(alpha: 0.06),
          ),
          border: TableBorder.all(
            color: const Color(0xFFE8ECF4),
            borderRadius: BorderRadius.circular(8),
          ),
          columns: [
            const DataColumn(
              label: Text(
                'SR Code',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: darkText,
                ),
              ),
            ),
            const DataColumn(
              label: Text(
                'Section',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: darkText,
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: darkText,
                ),
              ),
            ),
          ],
          rows: displayRows.map((r) {
            final sid = (r['sr_code'] ?? r['student_id'] ?? '').toString();
            final sec = (r['section'] ?? '').toString();
            final score = r['score'];
            final pct = r['percent'];
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    sec,
                    style: const TextStyle(fontSize: 13, color: textGrey),
                  ),
                ),
                DataCell(
                  Center(
                    child: Text(
                      display,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: darkText,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8ECF4))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedAssessmentId,
                decoration: InputDecoration(
                  labelText: 'Assessment',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4F6F9),
                ),
                isExpanded: true,
                style: const TextStyle(fontSize: 13, color: darkText),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8ECF4))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedAssessmentId,
                decoration: InputDecoration(
                  labelText: 'Assessment',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4F6F9),
                ),
                isExpanded: true,
                style: const TextStyle(fontSize: 13, color: darkText),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE8ECF4)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4F6F9),
                ),
                isExpanded: true,
                style: const TextStyle(fontSize: 13, color: darkText),
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
