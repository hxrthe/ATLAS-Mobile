import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../auth/login_screen.dart';
import '../scanner/scanner_screen.dart';
import '../scanner/scanner_widgets.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import '../faculty_dashboard/course_detail_screen.dart';
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
  Timer? _inactivityTimer;

  // Real data
  final GradingRepository _repo = GradingRepository();
  List<Map<String, dynamic>> _courses = [];
  Map<String, dynamic>? _activeCourse;
  List<BubbleTemplate> _activeTemplates = [];
  List<BubbleTemplate> _allTemplates = [];
  List<Map<String, dynamic>> _systemEvents = [];
  bool _loading = true;
  String? _error;

  late AnimationController _navSlideController;
  late Animation<Offset> _navSlideAnimation;

  final Color primaryRed = const Color(0xFF8B1515);
  final Color darkRed = const Color(0xFF5A0C0C);
  final Color textGrey = const Color(0xFF8391A1);
  final Color backgroundGrey = const Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    _navSlideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _navSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1.5),
    ).animate(CurvedAnimation(
      parent: _navSlideController,
      curve: Curves.easeInOut,
    ));
    _initLoad();
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
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
    setState(() => _userName = name);

    await _loadAll();
    // Refresh events periodically
    Timer.periodic(const Duration(seconds: 30), (_) => _loadEvents());
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
        final ct = allTemplates.where((t) => t.courseId == c['course_id']).toList();
        if (ct.any((t) => t.hasAnswerKey || t.assessmentId != null)) {
          activeCourse = c;
          activeTemplates = ct;
          break;
        }
      }
      activeCourse ??= courses.isNotEmpty ? courses.first : null;

      final events = await _repo.fetchRecentScans(limit: 20);

      if (mounted) {
        setState(() {
          _courses = courses;
          _activeCourse = activeCourse;
          _activeTemplates = activeTemplates;
          _allTemplates = allTemplates;
          _systemEvents = events;
          _loading = false;
        });
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

  Future<void> _loadEvents() async {
    try {
      final events = await _repo.fetchRecentScans(limit: 20);
      if (mounted) setState(() => _systemEvents = events);
    } catch (_) {}
  }

  void _switchActive(String courseId) {
    final course = _courses.firstWhere((c) => c['course_id'] == courseId);
    final templates =
        _allTemplates.where((t) => t.courseId == courseId).toList();
    setState(() {
      _activeCourse = course;
      _activeTemplates = templates;
    });
  }

    void _openSectionSheet(BuildContext context) {
    if (_activeCourse == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SectionSelectionSheet(
        courseId: _activeCourse!['course_id']!,
        courseName:
            '${_activeCourse!['course_code']} - ${_activeCourse!['course_title']}',
        templates:
            _activeTemplates.isNotEmpty ? _activeTemplates : _allTemplates.where((t) => t.courseId == _activeCourse!['course_id']).toList(),
      ),
    ).then((result) {
      // 🟢 FIX: Check context.mounted instead of just mounted
      if (!context.mounted) return;

      if (result != null) {
        _navigateToScanner(
          context,
          _activeCourse!['course_id']!,
          '${_activeCourse!['course_code']} - ${_activeCourse!['course_title']}',
          preselectedTemplate: result['template'] as BubbleTemplate?,
        );
      }
    });
  }

  void _navigateToScanner(BuildContext context, String courseId,
      String courseName,
      {BubbleTemplate? preselectedTemplate}) async {
    // Pause inactivity timer while scanning
    _inactivityTimer?.cancel();
    
    final effectiveCourseId = courseId.isEmpty ? null : courseId;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          preSelectedCourseId: effectiveCourseId,
          preSelectedCourseName: courseName,
          preselectedTemplate: preselectedTemplate,
        ),
      ),
    );
    
    // Resume timer when returning
    _resetInactivityTimer();
  }

  void _navigateToCourseDetail(String courseId, String courseCode,
      String courseTitle) async {
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      _buildHomeTab(context),
      CoursesTab(
        key: ValueKey('courses_$_loading'),
        onCourseSelected:
            (String courseId, String courseCode, String courseTitle) {
          _navigateToCourseDetail(courseId, courseCode, courseTitle);
        },
      ),
      ReportsTab(
        key: ValueKey('reports_$_loading'),
      ),
      const SettingsTab(),
    ];

    return Listener(
      onPointerDown: (_) => _resetInactivityTimer(),
      child: Scaffold(
        backgroundColor: backgroundGrey,
        extendBody: true,
        bottomNavigationBar: SlideTransition(
        position: _navSlideAnimation,
        child: BottomAppBar(
        height: 75,
        shape: const AutomaticNotchedShape(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          CircleBorder(),
        ),
        notchMargin: 10.0,
        color: Colors.white,
        elevation: 20,
        shadowColor: Colors.black.withValues(alpha: 0.5),
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
                        color: textGrey,
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
          backgroundColor: primaryRed,
          shape: const CircleBorder(),
          elevation: 10,
          child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 36),
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
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isSelected ? primaryRed : textGrey,
            size: 28,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? primaryRed : textGrey,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: primaryRed)))
                : SingleChildScrollView(
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
                                color: textGrey,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              _userName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: primaryRed,
                              ),
                            ),
                          ],
                        ),
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            const CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.grey,
                              backgroundImage:
                                  NetworkImage('https://i.pravatar.cc/150?img=11'),
                            ),
                            Container(
                              height: 14,
                              width: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: backgroundGrey, width: 2),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Active Session Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryRed, darkRed],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: primaryRed.withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4811B).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _activeCourse != null
                                  ? (_activeTemplates.any((t) =>
                                              t.hasAnswerKey ||
                                              t.assessmentId != null)
                                          ? 'ACTIVE SESSION'
                                          : 'NO ANSWER KEY')
                                  : 'NO COURSES',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _activeCourse != null
                                ? (_activeCourse!['course_code'] ?? '')
                                : 'No Courses',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            _activeCourse != null
                                ? (_activeCourse!['course_title'] ?? '')
                                : 'No active teaching load',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_activeTemplates.any(
                              (t) => t.hasAnswerKey || t.assessmentId != null))
                            Row(
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Color(0xFF00E676), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  '${_activeTemplates.where((t) => t.hasAnswerKey).length} answer key(s) ready',
                                  style: const TextStyle(
                                    color: Color(0xFF00E676),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed:
                                _activeCourse != null ? () => _openSectionSheet(context) : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: primaryRed,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text(
                              'Scan Exam Sheets',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Pending Assessments
                    if (_activeTemplates.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'PENDING ASSESSMENTS TO SCAN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: textGrey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryRed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_activeTemplates.length} TEMPLATES',
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
                      ..._activeTemplates.map((t) {
                        final isActive = _activeTemplates.any(
                            (at) => at.hasAnswerKey || at.assessmentId != null);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildTemplateCard(t,
                              isActive: isActive, isFirst: t.hasAnswerKey || t.assessmentId != null),
                        );
                      }),
                      const SizedBox(height: 16),
                    ],

                    // Other courses
                    if (_courses.length > 1) ...[
                      Text(
                        'OTHER COURSES',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: textGrey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._courses.where((c) => c['course_id'] != _activeCourse?['course_id']).map((c) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GestureDetector(
                            onTap: () => _switchActive(c['course_id']!),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE8ECF4)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: primaryRed.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.swap_horiz,
                                        color: primaryRed, size: 18),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c['course_code'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFF1E232C)),
                                        ),
                                        Text(
                                          c['course_title'] ?? '',
                                          style: TextStyle(
                                              fontSize: 12, color: textGrey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text('Switch',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: primaryRed,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],

                    const SizedBox(height: 32),

                    // System Events
                    Row(
                      children: [
                        Container(
                          height: 8,
                          width: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SYSTEM EVENTS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: textGrey,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_systemEvents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No scans yet. Start scanning to see events.',
                          style: TextStyle(fontSize: 13, color: textGrey),
                        ),
                      ),
                    ..._systemEvents.map((ev) {
                      final flagged = ev['is_flagged'] == true;
                      final score = ev['score_percent'] != null
                          ? '${(ev['score_percent'] as double).toStringAsFixed(0)}%'
                          : 'N/A';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              flagged ? Icons.flag : Icons.check_circle,
                              color: flagged
                                  ? Colors.orange.shade600
                                  : const Color(0xFF00E676),
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scanned ${ev['template_name'] ?? "sheet"} — ${ev['course_code'] ?? ""} | ${ev['student_id'] ?? "Unknown"} ($score)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _timeAgo(ev['created_at'] ?? ''),
                                    style: TextStyle(
                                        fontSize: 11, color: textGrey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTemplateCard(
    BubbleTemplate t, {
    required bool isActive,
    required bool isFirst,
  }) {
    return GestureDetector(
      onTap: () => _switchActive(t.courseId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: isFirst
              ? Border(left: BorderSide(color: primaryRed, width: 4))
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isFirst ? Icons.description : Icons.format_list_bulleted,
                color: isFirst ? primaryRed : const Color(0xFFD4811B),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${t.totalItems} items · ${t.numChoices} choices · ${t.hasAnswerKey ? "Key set" : "No key"}',
                    style: TextStyle(fontSize: 12, color: textGrey),
                  ),
                ],
              ),
            ),
            if (isFirst)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'READY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF198754),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
