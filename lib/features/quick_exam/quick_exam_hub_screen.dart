import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_pull_to_refresh.dart';
import '../../core/widgets/atlas_skeleton.dart';
import 'quick_exam_detail_screen.dart';
import 'quick_exam_form_screen.dart';
import 'quick_exam_models.dart';
import 'quick_exam_repository.dart';
import 'quick_exam_widgets.dart';
import 'quick_scan_detail_screen.dart';

/// Mobile-only quick exams: exams and recorded sheets, filterable by subject.
class QuickExamHubScreen extends StatefulWidget {
  /// Opens straight into the create form.
  final bool startWithNew;

  const QuickExamHubScreen({super.key, this.startWithNew = false});

  @override
  State<QuickExamHubScreen> createState() => _QuickExamHubScreenState();
}

class _QuickExamHubScreenState extends State<QuickExamHubScreen>
    with SingleTickerProviderStateMixin {
  final _repo = QuickExamRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  final _search = TextEditingController();
  Timer? _debounce;

  static const _legacyPrefix = 'subject:';

  List<QuickCourseOption> _courses = [];
  /// Older subjects that aren't one of the assigned courses.
  List<QuickSubject> _legacySubjects = [];
  /// A course id, `subject:<id>`, or null for all subjects.
  String? _chipId;

  List<QuickExam> _exams = [];
  bool _loadingExams = true;
  String? _examsError;

  List<QuickScan> _scans = [];
  int _scanTotal = 0;
  bool _loadingScans = true;
  String? _scansError;

  @override
  void initState() {
    super.initState();
    _reloadAll();
    if (widget.startWithNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _createExam());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reloadAll() =>
      Future.wait([_loadSubjects(), _loadExams(), _loadScans()]);

  Future<void> _loadSubjects() async {
    try {
      final options = await _repo.fetchSubjectOptions();
      if (!mounted) return;
      final linked = {for (final c in options.courses) ?c.subjectId};
      setState(() {
        _courses = options.courses;
        _legacySubjects = options.subjects
            .where((s) => !linked.contains(s.subjectId))
            .toList();
        final ids = {
          for (final c in _courses) c.courseId,
          for (final s in _legacySubjects) '$_legacyPrefix${s.subjectId}',
        };
        if (_chipId != null && !ids.contains(_chipId)) _chipId = null;
      });
    } catch (e) {
      debugPrint('Quick subjects load failed: $e');
    }
  }

  /// Subject filter for the API; [_noSubjectYet] when the chosen course has no exams.
  static const _noSubjectYet = '';

  String? get _subjectId {
    final chip = _chipId;
    if (chip == null) return null;
    if (chip.startsWith(_legacyPrefix)) return chip.substring(_legacyPrefix.length);
    final course = _courses.where((c) => c.courseId == chip);
    return course.isEmpty ? null : (course.first.subjectId ?? _noSubjectYet);
  }

  Future<void> _loadExams() async {
    setState(() {
      _loadingExams = true;
      _examsError = null;
    });
    final subjectId = _subjectId;
    if (subjectId == _noSubjectYet) {
      setState(() {
        _exams = [];
        _loadingExams = false;
      });
      return;
    }
    try {
      final exams = await _repo.fetchExams(subjectId: subjectId);
      if (!mounted || subjectId != _subjectId) return;
      setState(() {
        _exams = exams;
        _loadingExams = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingExams = false;
        _examsError = friendlyError(e, fallback: 'Could not load your exams.');
      });
    }
  }

  Future<void> _loadScans() async {
    setState(() {
      _loadingScans = true;
      _scansError = null;
    });
    final subjectId = _subjectId;
    final query = _search.text;
    if (subjectId == _noSubjectYet) {
      setState(() {
        _scans = [];
        _scanTotal = 0;
        _loadingScans = false;
      });
      return;
    }
    try {
      final res = await _repo.fetchRecords(subjectId: subjectId, query: query);
      if (!mounted || subjectId != _subjectId || query != _search.text) return;
      setState(() {
        _scans = res.scans;
        _scanTotal = res.total;
        _loadingScans = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingScans = false;
        _scansError = friendlyError(e, fallback: 'Could not load records.');
      });
    }
  }

  void _selectSubject(String? id) {
    if (id == _chipId) return;
    setState(() => _chipId = id);
    _loadExams();
    _loadScans();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadScans);
  }

  Future<void> _createExam() async {
    final created = await Navigator.push<QuickExam>(
      context,
      MaterialPageRoute(
        builder: (_) => QuickExamFormScreen(
          initialCourseId: _chipId != null && !_chipId!.startsWith(_legacyPrefix)
              ? _chipId
              : null,
          initialSubjectId: _subjectId == _noSubjectYet ? null : _subjectId,
        ),
      ),
    );
    if (created == null || !mounted) return;
    await _loadSubjects();
    _loadExams();
    if (!mounted) return;
    await _openExam(created);
  }

  Future<void> _openExam(QuickExam exam) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuickExamDetailScreen(exam: exam)),
    );
    if (mounted) _reloadAll();
  }

  Future<void> _openScan(QuickScan scan) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => QuickScanDetailScreen(scan: scan)),
    );
    if (changed == true && mounted) {
      _loadScans();
      _loadExams();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Exams'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: c.onPrimary,
          unselectedLabelColor: c.onPrimary.withValues(alpha: 0.7),
          indicatorColor: c.onPrimary,
          tabs: const [Tab(text: 'Exams'), Tab(text: 'Records')],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: _createExam,
              backgroundColor: c.primary,
              foregroundColor: c.onPrimary,
              icon: const Icon(Icons.add),
              label: const Text('New exam'),
            )
          : null,
      body: Column(
        children: [
          const SizedBox(height: 12),
          QuickSubjectChips(
            subjects: [
              for (final c in _courses) (id: c.courseId, label: c.name),
              for (final s in _legacySubjects)
                (id: '$_legacyPrefix${s.subjectId}', label: s.name),
            ],
            selectedId: _chipId,
            onSelected: _selectSubject,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildExamsTab(c), _buildRecordsTab(c)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamsTab(AtlasColors c) {
    Widget body;
    if (_loadingExams && _exams.isEmpty) {
      body = const AtlasSkeletonList(lines: 3, leadingSize: 40);
    } else if (_examsError != null) {
      body = ListView(
        children: [QuickErrorState(message: _examsError!, onRetry: _loadExams)],
      );
    } else if (_exams.isEmpty) {
      body = ListView(
        children: [
          QuickEmptyState(
            icon: Icons.quiz_outlined,
            title: _subjectId == null ? 'No exams yet' : 'No exams in this subject',
            message: 'Create a quiz for one of your courses with up to 100 items, add '
                'the key, print the sheet and scan answered sheets.',
            action: ElevatedButton.icon(
              onPressed: _createExam,
              icon: const Icon(Icons.add),
              label: const Text('Create exam'),
            ),
          ),
        ],
      );
    } else {
      final groups = <String, List<QuickExam>>{};
      for (final e in _exams) {
        groups.putIfAbsent(e.subjectName, () => []).add(e);
      }
      final names = groups.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          for (final name in names) ...[
            if (_subjectId == null) ...[
              QuickSectionLabel('$name · ${groups[name]!.length}'),
              const SizedBox(height: 8),
            ],
            for (final e in groups[name]!) ...[
              _QuickExamCard(exam: e, onTap: () => _openExam(e)),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],
        ],
      );
    }
    return AtlasPullToRefresh(onRefresh: _reloadAll, child: body);
  }

  Widget _buildRecordsTab(AtlasColors c) {
    Widget list;
    if (_loadingScans && _scans.isEmpty) {
      list = const AtlasSkeletonList(count: 6, leadingSize: 40);
    } else if (_scansError != null) {
      list = ListView(
        children: [QuickErrorState(message: _scansError!, onRetry: _loadScans)],
      );
    } else if (_scans.isEmpty) {
      list = ListView(
        children: [
          QuickEmptyState(
            icon: Icons.folder_open_outlined,
            title: _search.text.trim().isEmpty ? 'No records yet' : 'No matching records',
            message: _search.text.trim().isEmpty
                ? 'Scanned exam sheets will appear here.'
                : 'Try another student ID or name.',
          ),
        ],
      );
    } else {
      list = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _scanTotal > _scans.length
                  ? 'Showing ${_scans.length} of $_scanTotal records'
                  : '$_scanTotal record(s)',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          ),
          for (final s in _scans) ...[
            QuickScanTile(scan: s, showExam: true, onTap: () => _openScan(s)),
            const SizedBox(height: 8),
          ],
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search student ID or name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _loadScans();
                      },
                    ),
            ),
          ),
        ),
        Expanded(child: AtlasPullToRefresh(onRefresh: _loadScans, child: list)),
      ],
    );
  }
}

class _QuickExamCard extends StatelessWidget {
  final QuickExam exam;
  final VoidCallback onTap;

  const _QuickExamCard({required this.exam, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final keyColor = exam.hasFullKey
        ? c.pass
        : (exam.hasAnyKey ? c.ambiguous : c.fail);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: c.primary.withValues(alpha: 0.1),
              child: Text(
                '${exam.totalItems}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${exam.totalItems} items · ${exam.scanCount} sheet(s)'
                    '${exam.averagePercent == null ? '' : ' · avg ${formatPercent(exam.averagePercent)}'}',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.vpn_key_rounded, size: 13, color: keyColor),
                      const SizedBox(width: 4),
                      Text(
                        exam.hasFullKey
                            ? 'Key ready'
                            : exam.hasAnyKey
                                ? 'Key ${exam.keyedItems}/${exam.totalItems}'
                                : 'No key yet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: keyColor,
                        ),
                      ),
                      if (exam.flaggedCount > 0) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.flag_rounded, size: 13, color: c.ambiguous),
                        const SizedBox(width: 2),
                        Text(
                          '${exam.flaggedCount}',
                          style: TextStyle(fontSize: 12, color: c.ambiguous),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: c.textSecondary),
          ],
        ),
      ),
    );
  }
}
