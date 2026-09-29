import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../scanner/scanner_screen.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import '../faculty_dashboard/course_detail_screen.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/atlas_loading_view.dart';
import '../../core/widgets/atlas_pull_to_refresh.dart';
import '../../core/widgets/atlas_info_button.dart';
import '../../core/widgets/pulse_dot.dart';
import '../settings/account_security_screen.dart';
import 'home_widgets.dart';
import 'tabs/courses_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/settings_tab.dart';

class FacultyDashboardScreen extends StatefulWidget {
  const FacultyDashboardScreen({super.key});

  @override
  State<FacultyDashboardScreen> createState() => _FacultyDashboardScreenState();
}

class _FacultyDashboardScreenState extends State<FacultyDashboardScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _userName = 'Instructor';
  String? _userPhotoUrl;
  Timer? _inactivityTimer;
  Timer? _eventsTimer;

  // Real data
  final GradingRepository _repo = GradingRepository();
  List<Map<String, dynamic>> _courses = [];
  Map<String, dynamic>? _activeCourse;
  List<BubbleTemplate> _activeTemplates = [];
  List<BubbleTemplate> _allTemplates = [];
  List<Map<String, dynamic>> _systemEvents = [];
  String? _activeAssessmentType;

  /// student-scores payload per template id (rows with section + score).
  Map<String, Map<String, dynamic>> _templateScores = {};
  bool _loading = true;
  String? _error;

  late AnimationController _navSlideController;
  late Animation<Offset> _navSlideAnimation;

  static const Color _darkRed = Color(0xFF5A0C0C);

  @override
  void initState() {
    super.initState();
    _navSlideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _navSlideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, 1.5)).animate(
          CurvedAnimation(parent: _navSlideController, curve: Curves.easeInOut),
        );
    _initLoad();
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _eventsTimer?.cancel();
    _navSlideController.dispose();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(minutes: 15), _handleInactivity);
  }

  void _handleInactivity() {
    if (!mounted) return;

    // Perform logout
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const LoginScreen(autoLogout: true),
      ),
      (route) => false,
    );
  }

  Future<void> _initLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? 'Instructor';
    final photoUrl = prefs.getString('user_photo_url');
    setState(() {
      _userName = name;
      _userPhotoUrl = photoUrl;
    });

    await _loadAll();
    // Refresh events periodically
    _eventsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadEvents(),
    );
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final courses = await _repo.fetchFacultyCourses();
      final allTemplates = <BubbleTemplate>[];
      for (final c in courses) {
        try {
          final t = await _repo.fetchTemplates(c['course_id']!);
          allTemplates.addAll(t);
        } catch (_) {}
      }

      // Active course = first course that has templates with answer keys
      Map<String, dynamic>? activeCourse;
      List<BubbleTemplate> activeTemplates = [];
      for (final c in courses) {
        final ct = allTemplates
            .where((t) => t.courseId == c['course_id'])
            .toList();
        if (ct.any((t) => t.hasAnswerKey || t.assessmentId != null)) {
          activeCourse = c;
          activeTemplates = ct;
          break;
        }
      }
      activeCourse ??= courses.isNotEmpty ? courses.first : null;

      final events = await _fetchWeekScans();

      // Fetch assessment type for the active course
      String? assessmentType;
      if (activeCourse != null) {
        try {
          final assessments = await _repo.fetchAssessments(
            activeCourse['course_id']!,
          );
          if (assessments.isNotEmpty) {
            assessmentType = assessments.first['assessment_type'] as String?;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _courses = courses;
          _activeCourse = activeCourse;
          _activeTemplates = activeTemplates;
          _allTemplates = allTemplates;
          _systemEvents = events;
          _activeAssessmentType = assessmentType;
          _loading = false;
        });
        _loadTemplateScores();
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

  Future<List<Map<String, dynamic>>> _fetchWeekScans() async {
    try {
      final week = rangeFor(ScanRange.week);
      return await _repo.fetchScansInRange(from: week.start, to: week.end);
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadEvents() async {
    final events = await _fetchWeekScans();
    if (mounted) setState(() => _systemEvents = events);
  }

  Future<void> _loadTemplateScores() async {
    final course = _activeCourse;
    if (course == null) return;
    final courseId = course['course_id'].toString();
    final results = <String, Map<String, dynamic>>{};
    await Future.wait(
      _activeTemplates.where((t) => t.assessmentId != null).map((t) async {
        try {
          results[t.templateId] = await _repo.fetchStudentScores(
            courseId,
            t.assessmentId!,
          );
        } catch (_) {}
      }),
    );
    if (mounted && _activeCourse?['course_id'] == courseId) {
      setState(() => _templateScores = results);
    }
  }

  void _switchActive(String courseId) {
    final course = _courses.firstWhere((c) => c['course_id'] == courseId);
    final templates = _allTemplates
        .where((t) => t.courseId == courseId)
        .toList();
    setState(() {
      _activeCourse = course;
      _activeTemplates = templates;
      _templateScores = {};
    });
    _loadTemplateScores();
  }

  List<Map<String, dynamic>> _scoreRows(String templateId) =>
      ((_templateScores[templateId]?['students'] ??
                      _templateScores[templateId]?['rows'])
                  as List<dynamic>? ??
              [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

  void _openScanner(BuildContext context) {
    if (_activeCourse == null) return;
    _navigateToScanner(
      context,
      _activeCourse!['course_id']!,
      '${_activeCourse!['course_code']} - ${_activeCourse!['course_title']}',
    );
  }

  void _navigateToScanner(
    BuildContext context,
    String courseId,
    String courseName,
  ) async {
    // Pause inactivity timer while scanning
    _inactivityTimer?.cancel();

    final effectiveCourseId = courseId.isEmpty ? null : courseId;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          preSelectedCourseId: effectiveCourseId,
          preSelectedCourseName: courseName,
        ),
      ),
    );

    // Resume timer when returning
    _resetInactivityTimer();
  }

  void _navigateToCourseDetail(
    String courseId,
    String courseCode,
    String courseTitle,
  ) async {
    await _navSlideController.forward();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseDetailScreen(
          courseId: courseId,
          courseCode: courseCode,
          courseTitle: courseTitle,
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
    _navSlideController.reverse();
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  String _assessmentTypeLabel(String? type) {
    switch (type?.toLowerCase()) {
      case 'prelim':
        return 'PRELIM';
      case 'midterm':
        return 'MIDTERM';
      case 'semi-finals':
        return 'SEMI-FINALS';
      case 'finals':
        return 'FINALS';
      default:
        return type?.toUpperCase() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final List<Widget> tabs = [
      _buildHomeTab(context),
      CoursesTab(
        key: ValueKey('courses_$_loading'),
        onCourseSelected:
            (String courseId, String courseCode, String courseTitle) {
              _navigateToCourseDetail(courseId, courseCode, courseTitle);
            },
      ),
      ReportsTab(key: ValueKey('reports_$_loading')),
      const SettingsTab(),
    ];

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      child: Scaffold(
        backgroundColor: context.atlas.scaffold,
        extendBody: true,
        bottomNavigationBar: SlideTransition(
          position: _navSlideAnimation,
          child: CustomPaint(
            painter: _NavBarShadowPainter(
              shape: _navBarShape,
              notchMargin: _navNotchMargin,
              fabRadius: 36,
              color: Colors.black.withValues(alpha: 0.18),
            ),
            child: BottomAppBar(
              height: 75,
              shape: _navBarShape,
              notchMargin: _navNotchMargin,
              color: context.atlas.card,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              padding: EdgeInsets.zero,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNavItem(0, Icons.home, 'Home'),
                        _buildNavItem(1, Icons.menu_book, 'Courses'),
                      ],
                    ),
                  ),
                  // Central part for FAB and label
                  SizedBox(
                    width: 100,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Text(
                            'Scanner',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNavItem(2, Icons.show_chart, 'Reports'),
                        _buildNavItem(3, Icons.manage_accounts, 'Settings'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: SlideTransition(
          position: _navSlideAnimation,
          child: SizedBox(
            height: 72,
            width: 72,
            child: FloatingActionButton(
              onPressed: () {
                _resetInactivityTimer();
                _navigateToScanner(context, "", "Scanner");
              },
              backgroundColor: c.primary,
              shape: const CircleBorder(),
              elevation: 10,
              child: const Icon(
                Icons.qr_code_scanner,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        body: tabs[_selectedIndex],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final colors = context.atlas;
    final active = colors.primary;
    final inactive = colors.textSecondary;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: isSelected ? active : inactive, size: 28),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? active : inactive,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    final c = context.atlas;

    return AtlasPullToRefresh(
      onRefresh: _loadAll,
      enabled: !_loading,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _loading
              ? const AtlasLoadingView(
                  key: ValueKey('home-loading'),
                  layout: AtlasLoadingLayout.home,
                )
              : _error != null
              ? ListView(
                  key: const ValueKey('home-error'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 180),
                    Center(
                      child: Text(_error!, style: TextStyle(color: c.primary)),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  key: const ValueKey('home-content'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'WELCOME INSTRUCTOR',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: c.textSecondary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              Text(
                                _userName,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: c.primary,
                                ),
                              ),
                            ],
                          ),
                          Tooltip(
                            message: 'Account & Security',
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AccountSecurityScreen(),
                                ),
                              ),
                              child: UserAvatar(
                                photoUrl: _userPhotoUrl,
                                name: _userName,
                                radius: 28,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Active Session Card
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [c.primary, _darkRed],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: c.primary.withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _activeCourse != null
                                        ? (_activeCourse!['course_code'] ?? '')
                                        : 'No Courses',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _sessionBadge(),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _activeCourse != null
                                        ? (_activeCourse!['course_title'] ?? '')
                                        : 'No active teaching load',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (_activeAssessmentType != null &&
                                    _activeAssessmentType!.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _assessmentTypeLabel(
                                        _activeAssessmentType,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _activeCourse != null
                                  ? () => _openScanner(context)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: c.primary,
                                minimumSize: const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.camera_alt, size: 20),
                              label: const Text(
                                'Scan Exam Sheets',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Pending Assessments
                      if (_pendingTemplates.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'PENDING ASSESSMENTS TO SCAN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: c.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: c.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_pendingTemplates.length} PENDING',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._pendingTemplates.map(
                          (t) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildTemplateCard(context, t),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Other courses
                      if (_courses.length > 1) ...[
                        Text(
                          'OTHER COURSES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: c.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _otherCoursesGrid(),
                      ],

                      const SizedBox(height: 32),

                      // System Events
                      _buildEventsCard(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Exams still waiting on answer sheets; one is done when every student in
  /// every section has a scan. Kept while its counts are still loading.
  List<BubbleTemplate> get _pendingTemplates => _activeTemplates.where((t) {
    if (!_templateScores.containsKey(t.templateId)) return true;
    final progress = sectionProgress(_scoreRows(t.templateId));
    if (progress.isEmpty) return true;
    return progress.any((p) => p.scanned < p.total);
  }).toList();

  bool get _hasActiveSession =>
      _activeCourse != null &&
      _activeTemplates.any((t) => t.hasAnswerKey || t.assessmentId != null);

  /// Two-column grid of the faculty's other courses; tapping one makes it active.
  Widget _otherCoursesGrid() {
    final c = context.atlas;
    final others = _courses
        .where((course) => course['course_id'] != _activeCourse?['course_id'])
        .toList();
    const gap = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final course in others)
              SizedBox(
                width: width,
                height: 128,
                child: Material(
                  color: c.primary,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _switchActive(course['course_id']!),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  course['course_code'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.swap_horiz,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Text(
                              course['course_title'] ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          const Text(
                            'Switch',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// White pill on the session card with a pulsing status dot.
  Widget _sessionBadge() {
    final c = context.atlas;
    final active = _hasActiveSession;
    final label = _activeCourse == null
        ? 'NO COURSES'
        : (active ? 'ACTIVE SESSION' : 'NO ANSWER KEY');
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(
            color: active ? const Color(0xFF00C853) : const Color(0xFFD4811B),
            animate: active,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              color: c.primary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeCard({required Widget child}) {
    final c = context.atlas;
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: child,
    );
  }

  Widget _buildEventsCard() {
    final c = context.atlas;
    const shown = 5;
    final events = _systemEvents.take(shown).toList();
    return _homeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseDot(animate: _systemEvents.isNotEmpty),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SYSTEM EVENTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: c.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Scans in the last 7 days · ${_systemEvents.length}',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              AtlasInfoButton(onTap: () => showScanEventsSheet(context, _repo)),
            ],
          ),
          const SizedBox(height: 6),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No scans this week. Tap the info button to browse older scans.',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            )
          else ...[
            for (var i = 0; i < events.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.divider),
              ScanEventTile(
                scan: events[i],
                timeLabel: _timeAgo(events[i]['created_at']?.toString() ?? ''),
              ),
            ],
            if (_systemEvents.length > shown)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${_systemEvents.length - shown} more this week',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, BubbleTemplate t) {
    final c = context.atlas;
    final ready = t.hasAnswerKey || t.assessmentId != null;
    final loaded = _templateScores.containsKey(t.templateId);
    final rows = _scoreRows(t.templateId);
    final progress = sectionProgress(rows);
    final totalItems =
        (_templateScores[t.templateId]?['total_items'] as num?)?.toInt() ??
        t.totalItems;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: ready
            ? Border(left: BorderSide(color: c.primary, width: 4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  ready ? Icons.description : Icons.format_list_bulleted,
                  color: ready ? c.primary : const Color(0xFFD4811B),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  t.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: c.textPrimary,
                  ),
                ),
              ),
              if (ready) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.correct.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'READY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: c.correct,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              AtlasInfoButton(
                onTap: t.assessmentId == null
                    ? () {}
                    : () => showAssessmentScansSheet(
                        context,
                        title: t.name,
                        subtitle:
                            '${_activeCourse?['course_code'] ?? ''} · $totalItems items',
                        rows: rows,
                        totalItems: totalItems,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!loaded)
            Text(
              'Loading sections…',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            )
          else if (progress.isEmpty)
            Text(
              'No students on a section for this course yet.',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            )
          else
            for (final p in progress)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.section,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '${p.scanned}/${p.total} scanned',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: p.scanned >= p.total
                                ? c.correct
                                : c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p.total == 0 ? 0 : p.scanned / p.total,
                        minHeight: 6,
                        backgroundColor: c.border,
                        color: p.scanned >= p.total ? c.correct : c.primary,
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

const _navBarShape = AutomaticNotchedShape(
  RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  CircleBorder(),
);
const _navNotchMargin = 10.0;

/// Soft shadow along the bottom bar's outline, notch included, so the curved
/// top edge reads against the page without shading inside the notch.
class _NavBarShadowPainter extends CustomPainter {
  final NotchedShape shape;
  final double notchMargin;
  final double fabRadius;
  final Color color;

  const _NavBarShadowPainter({
    required this.shape,
    required this.notchMargin,
    required this.fabRadius,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guest = Rect.fromCircle(
      center: Offset(size.width / 2, 0),
      radius: fabRadius,
    ).inflate(notchMargin);
    final path = shape.getOuterPath(Offset.zero & size, guest);
    canvas.drawPath(
      path.shift(const Offset(0, -1)),
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10),
    );
  }

  @override
  bool shouldRepaint(_NavBarShadowPainter old) =>
      old.color != color ||
      old.notchMargin != notchMargin ||
      old.fabRadius != fabRadius;
}
