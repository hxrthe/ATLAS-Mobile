import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_filter_chip.dart';
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
  bool _loadingScores = false;
  String? _scoresError;
  int _scoreTotalItems = 0;
  double _scorePassingPercent = 50;
  List<String> _scoreSections = [];
  List<String> _scoreGradeLevels = [];
  String? _scoreSectionFilter;
  String? _scoreGradeFilter;
  String? _scoreStatusFilter;
  String _scoreSearch = '';
  final TextEditingController _scoreSearchCtrl = TextEditingController();

  double? _passingScore;
  bool _loadingPassingScore = false;
  bool _savingPassingScore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadWorkspace();
    _loadSectionCounts();
  }

  /// Students per section for the header, from the course roster (blocks).
  Map<String, int>? _sectionCounts;

  Future<void> _loadSectionCounts() async {
    final students = await _repo.fetchCourseStudents(widget.courseId);
    final counts = <String, int>{};
    for (final s in students) {
      final name = (s['section'] ?? '').toString().trim();
      final key = name.isEmpty ? 'Unassigned' : name;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final sorted = Map.fromEntries(counts.entries.toList()
      ..sort((a, b) {
        if (a.key == 'Unassigned') return 1;
        if (b.key == 'Unassigned') return -1;
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      }));
    if (mounted) setState(() => _sectionCounts = sorted);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scoreSearchCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
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

      final selId = rawAssessments.isNotEmpty
          ? rawAssessments.first['assessment_id']?.toString()
          : null;

      if (mounted) {
        setState(() {
          _assessments = rawAssessments;
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
      final rows = rawStudents
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      List<String> strings(dynamic v) =>
          (v as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      if (mounted) {
        setState(() {
          _scoreRows = rows;
          _scoreTotalItems = (data['total_items'] as num?)?.toInt() ?? 0;
          _scorePassingPercent =
              (data['passing_percent'] as num?)?.toDouble() ?? 50;
          _scoreSections = strings(data['sections']);
          _scoreGradeLevels = strings(data['grade_levels']);
          if (!_scoreSections.contains(_scoreSectionFilter)) {
            _scoreSectionFilter = null;
          }
          if (!_scoreGradeLevels.contains(_scoreGradeFilter)) {
            _scoreGradeFilter = null;
          }
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
      bottomNavigationBar: _buildAssessmentBar(),
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
          if (_sectionCounts == null)
            SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: onHero),
            )
          else if (_sectionCounts!.isEmpty)
            _infoChip(Icons.groups_2_outlined, 'No sections yet', onHero)
          else
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final e in _sectionCounts!.entries)
                  _infoChip(
                    Icons.groups_2_outlined,
                    '${e.key} · ${e.value} student${e.value == 1 ? '' : 's'}',
                    onHero,
                  ),
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
                      (item['question_text'] ?? 'Item $qNum').toString(),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: c.textPrimary,
                      ),
                      softWrap: true,
                    ),
                    if (choices.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final choice in choices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            choice,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: _isKeyChoice(choice, answer)
                                  ? c.correct
                                  : c.textSecondary,
                              fontWeight: _isKeyChoice(choice, answer)
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
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

  bool _isKeyChoice(String choice, String answer) {
    if (answer.isEmpty) return false;
    final t = choice.trimLeft().toUpperCase();
    return t.startsWith('$answer.') ||
        t.startsWith('$answer)') ||
        t.startsWith('$answer ') ||
        t == answer;
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
        courseId: widget.courseId,
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
        courseId: widget.courseId,
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

  List<Map<String, dynamic>> get _filteredScoreRows => _scoreRowsFor(
        section: _scoreSectionFilter,
        grade: _scoreGradeFilter,
        status: _scoreStatusFilter,
      );

  List<Map<String, dynamic>> _scoreRowsFor({
    String? section,
    String? grade,
    String? status,
  }) {
    final q = _scoreSearch.trim().toLowerCase();
    return _scoreRows.where((r) {
      if (section != null && r['section'] != section) {
        return false;
      }
      if (grade != null && r['grade_level'] != grade) {
        return false;
      }
      final scored = r['score'] != null;
      switch (status) {
        case 'passed':
          if (r['passed'] != true) return false;
        case 'failed':
          if (!scored || r['passed'] == true) return false;
        case 'missing':
          if (scored) return false;
      }
      if (q.isNotEmpty) {
        final hay = '${r['student_id'] ?? ''} ${r['student_name'] ?? ''}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  String _fmtNum(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static const _scoreStatusOptions = [
    FilterOption('passed', 'Passed'),
    FilterOption('failed', 'Failed'),
    FilterOption('missing', 'Not yet scanned'),
  ];

  int get _activeScoreFilters =>
      [_scoreSectionFilter, _scoreGradeFilter, _scoreStatusFilter]
          .where((v) => v != null)
          .length;

  List<({String label, VoidCallback onRemove})> get _appliedScoreChips => [
        if (_scoreSectionFilter != null)
          (
            label: _scoreSectionFilter!,
            onRemove: () => setState(() => _scoreSectionFilter = null),
          ),
        if (_scoreGradeFilter != null)
          (
            label: _scoreGradeFilter!,
            onRemove: () => setState(() => _scoreGradeFilter = null),
          ),
        if (_scoreStatusFilter != null)
          (
            label: _scoreStatusOptions
                .firstWhere((o) => o.value == _scoreStatusFilter)
                .label,
            onRemove: () => setState(() => _scoreStatusFilter = null),
          ),
      ];

  Future<void> _openScoreFilters() async {
    final result = await showAtlasFilterSheet(
      context,
      groups: [
        FilterGroup(
          key: 'section',
          title: 'Section',
          allLabel: 'All sections',
          options: _scoreSections.map((s) => FilterOption(s, s)).toList(),
        ),
        FilterGroup(
          key: 'grade',
          title: 'Grade level',
          allLabel: 'All levels',
          options: _scoreGradeLevels.map((g) => FilterOption(g, g)).toList(),
        ),
        const FilterGroup(
          key: 'status',
          title: 'Status',
          allLabel: 'All students',
          options: _scoreStatusOptions,
        ),
      ],
      initial: {
        'section': _scoreSectionFilter,
        'grade': _scoreGradeFilter,
        'status': _scoreStatusFilter,
      },
      applyLabel: (d) {
        final n = _scoreRowsFor(
          section: d['section'],
          grade: d['grade'],
          status: d['status'],
        ).length;
        return 'Show $n student${n == 1 ? '' : 's'}';
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      _scoreSectionFilter = result['section'];
      _scoreGradeFilter = result['grade'];
      _scoreStatusFilter = result['status'];
    });
  }

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
    if (_selectedAssessmentId == null) {
      return Center(
        child: Text('No assessments for this course',
            style: TextStyle(color: c.textSecondary)),
      );
    }

    final rows = _filteredScoreRows;
    final scored = rows.where((r) => r['score'] != null).toList();
    final passed = scored.where((r) => r['passed'] == true).length;
    final meanScore = scored.isEmpty
        ? null
        : scored
                  .map((r) => (r['score'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              scored.length;

    return RefreshIndicator(
      onRefresh: _loadScores,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _scoreSearchCtrl,
                  onChanged: (v) => setState(() => _scoreSearch = v),
                  style: TextStyle(fontSize: 13, color: c.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search SR code or name',
                    hintStyle: TextStyle(color: c.textSecondary, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search, size: 20, color: c.textSecondary),
                    suffixIcon: _scoreSearch.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _scoreSearchCtrl.clear();
                              setState(() => _scoreSearch = '');
                            },
                          ),
                    filled: true,
                    fillColor: c.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AtlasFilterButton(
                activeCount: _activeScoreFilters,
                onPressed: _openScoreFilters,
              ),
            ],
          ),
          if (_appliedScoreChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            AtlasAppliedChipsRow(
              chips: _appliedScoreChips,
              onClearAll: () => setState(() {
                _scoreSectionFilter = null;
                _scoreGradeFilter = null;
                _scoreStatusFilter = null;
              }),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _scoreStat(
                'Scanned',
                '${scored.length}/${rows.length}',
                c.textPrimary,
              ),
              const SizedBox(width: 8),
              _scoreStat(
                'Mean score',
                meanScore == null
                    ? '—'
                    : '${_fmtNum(meanScore)}/${_scoreTotalItems == 0 ? '—' : _scoreTotalItems}',
                c.primary,
              ),
              const SizedBox(width: 8),
              _scoreStat(
                'Pass rate',
                scored.isEmpty
                    ? '—'
                    : '${(passed / scored.length * 100).toStringAsFixed(0)}%',
                passed * 2 >= scored.length && scored.isNotEmpty
                    ? c.pass
                    : c.fail,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Passing mark: ${_fmtNum(_scorePassingPercent)}%'
            '${_scoreTotalItems > 0 ? ' (${_fmtNum(_scorePassingPercent / 100 * _scoreTotalItems)} of $_scoreTotalItems items)' : ''}',
            style: TextStyle(fontSize: 11, color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _scoreRows.isEmpty
                      ? 'No students yet. Students appear here once they are on a section that takes this course, or have been scanned.'
                      : 'No students match these filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary),
                ),
              ),
            )
          else
            _buildScoresTable(rows, c),
        ],
      ),
    );
  }

  Widget _scoreStat(String label, String value, Color color) {
    final c = context.atlas;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildScoresTable(List<Map<String, dynamic>> rows, AtlasColors c) {
    TextStyle head() => TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
          color: c.textPrimary,
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        horizontalMargin: 12,
        headingRowHeight: 40,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 58,
        headingRowColor:
            WidgetStateProperty.all(c.primary.withValues(alpha: 0.06)),
        dataRowColor: WidgetStateProperty.all(c.card),
        border: TableBorder.all(
          color: c.border,
          borderRadius: BorderRadius.circular(8),
        ),
        columns: [
          DataColumn(label: Text('SR Code', style: head())),
          DataColumn(label: Text('Section', style: head())),
          DataColumn(label: Text('Grade', style: head())),
          DataColumn(label: Text('Score', style: head()), numeric: true),
          DataColumn(label: Text('Status', style: head())),
        ],
        rows: rows.map((r) {
          final sid = (r['student_id'] ?? '').toString();
          final name = (r['student_name'] ?? '').toString();
          final score = r['score'] as num?;
          final max = (r['max_score'] as num?) ?? _scoreTotalItems;
          final pct = r['percent'] as num?;
          final passedRow = r['passed'] == true;
          return DataRow(
            cells: [
              DataCell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sid.isEmpty ? '—' : sid,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: c.textPrimary,
                      ),
                    ),
                    if (name.isNotEmpty)
                      Text(name,
                          style: TextStyle(
                              fontSize: 11, color: c.textSecondary)),
                  ],
                ),
              ),
              DataCell(Text((r['section'] ?? '').toString(),
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary))),
              DataCell(Text((r['grade_level'] ?? '').toString(),
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary))),
              DataCell(
                score == null
                    ? Text('—', style: TextStyle(color: c.textSecondary))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_fmtNum(score)} / ${max == 0 ? '—' : _fmtNum(max)}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          if (pct != null)
                            Text('${pct.toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontSize: 10.5, color: c.textSecondary)),
                        ],
                      ),
              ),
              DataCell(_statusPill(
                score == null
                    ? 'Not scanned'
                    : (passedRow ? 'Passed' : 'Failed'),
                score == null
                    ? c.textSecondary
                    : (passedRow ? c.pass : c.fail),
              )),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ═══ Bottom Bar ═══════════════════════════════════════════════════════

  Widget _buildAssessmentBar() {
    final c = context.atlas;
    final ids = _assessments
        .map((a) => (a['assessment_id'] ?? '').toString())
        .toSet();
    final selected = ids.contains(_selectedAssessmentId)
        ? _selectedAssessmentId
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        child: DropdownButtonFormField<String>(
          key: ValueKey('assessment-$selected-${_assessments.length}'),
          initialValue: selected,
          decoration: InputDecoration(
            labelText: 'Assessment',
            labelStyle: TextStyle(color: c.textSecondary),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    );
  }
}
