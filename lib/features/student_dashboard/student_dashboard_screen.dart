import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../grading/grading_repository.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/student_settings_tab.dart';
import 'live_alerts_sheet.dart';
import 'tabs/student_courses_tab.dart';
import 'enroll_course_dialog.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  int _selectedIndex = 0;
  String _userName = 'Student';

  final GradingRepository _repo = GradingRepository();
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _recentGrades = [];
  Map<String, dynamic>? _ongoingAssessment;
  bool _loading = true;
  String? _error;

  final Color primaryRed = const Color(0xFF8B1515);
  final Color backgroundGrey = const Color(0xFFF4F6F9);
  final Color textGrey = const Color(0xFF8391A1);

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? 'Student';
    setState(() => _userName = name);
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // Refresh student details from server first
      await _repo.refreshStudentDetails();

      // Load courses from dashboard summary (now returns enrolled courses for students)
      final courses = await _repo.fetchFacultyCourses();
      final recentGrades = <Map<String, dynamic>>[];

      for (final c in courses) {
        try {
          final templates = await _repo.fetchTemplates(c['course_id']!);
          for (final t in templates) {
            try {
              final scans = await _repo.fetchScans(t.templateId);
              for (final s in scans) {
                if (s.studentIdentifier.isNotEmpty && s.scorePercent != null) {
                  recentGrades.add({
                    'template_name': t.name,
                    'course_code': c['course_code'],
                    'course_title': c['course_title'],
                    'course_id': c['course_id'],
                    'score': '${s.scoreRaw}/${t.totalItems}',
                    'percent': s.scorePercent,
                    'is_passed': s.scorePercent! >= (t.passingScore ?? 50),
                    'created_at': s.createdAt,
                    'assessment_id': t.assessmentId,
                  });
                }
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      recentGrades.sort((a, b) {
        final aDate = a['created_at'] as String? ?? '';
        final bDate = b['created_at'] as String? ?? '';
        return bDate.compareTo(aDate);
      });

      Map<String, dynamic>? ongoing;
      for (final c in courses) {
        try {
          final templates = await _repo.fetchTemplates(c['course_id']!);
          for (final t in templates) {
            if (t.assessmentId != null && t.hasAnswerKey) {
              ongoing = {
                'course_code': c['course_code'],
                'course_title': c['course_title'],
                'template_name': t.name,
                'template': t,
              };
              break;
            }
          }
          if (ongoing != null) break;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _courses = courses;
          _recentGrades = recentGrades.take(10).toList();
          _ongoingAssessment = ongoing;
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      _buildHomeTab(context),
      StudentCoursesTab(
        key: ValueKey('student_courses_$_loading'),
        courses: _courses,
        loading: _loading,
        onCoursesChanged: _loadAll,
      ),
      const StudentProfileScreen(),
      const StudentSettingsTab(),
    ];

    return Scaffold(
      backgroundColor: backgroundGrey,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEnrollDialog(context),
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Join Course', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: primaryRed,
        unselectedItemColor: textGrey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Courses'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Analytics'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      body: tabs[_selectedIndex],
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'STUDENT PORTAL',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 1.0),
                            ),
                            Text(
                              _userName,
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: primaryRed),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Stack(
                              alignment: Alignment.topRight,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.notifications, color: primaryRed, size: 28),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) => LiveAlertsSheet(alerts: _recentGrades),
                                    );
                                  },
                                ),
                                Positioned(
                                  right: 12,
                                  top: 10,
                                  child: Container(
                                    height: 10,
                                    width: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: backgroundGrey, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            const CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.grey,
                              backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=33'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    if (_ongoingAssessment != null) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: primaryRed.withOpacity(0.2), width: 1.5),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.alarm, color: Colors.orange, size: 20),
                                SizedBox(width: 8),
                                Text('ONGOING ASSESSMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_ongoingAssessment!['course_code']} — ${_ongoingAssessment!['template_name']}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            Text(
                              _ongoingAssessment!['course_title'] ?? '',
                              style: TextStyle(fontSize: 14, color: textGrey),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryRed,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 48),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('View Exam Details', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    Text(
                      'RECENTLY GRADED ASSESSMENTS',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 16),
                    if (_recentGrades.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text('No graded assessments yet.', style: TextStyle(fontSize: 13, color: textGrey)),
                      ),
                    for (int i = 0; i < _recentGrades.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _buildGradeCard(
                        subjectCode: _recentGrades[i]['course_code'] ?? '',
                        subjectTitle: _recentGrades[i]['course_title'] ?? '',
                        assessmentName: _recentGrades[i]['template_name'] ?? '',
                        score: _recentGrades[i]['score'] ?? '',
                        isPassed: _recentGrades[i]['is_passed'] == true,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGradeCard({
    required String subjectCode,
    required String subjectTitle,
    required String assessmentName,
    required String score,
    required bool isPassed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$subjectCode — $assessmentName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  subjectTitle,
                  style: TextStyle(fontSize: 12, color: textGrey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isPassed ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              score,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPassed ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEnrollDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => EnrollCourseDialog(
        onEnroll: (String courseCode) async {
          try {
            await _repo.enrollInCourse(courseCode);
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            // Reload courses
            await _loadAll();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Successfully enrolled in $courseCode!'),
                  backgroundColor: Colors.green.shade700,
                ),
              );
            }
          } catch (e) {
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString().replaceAll('Exception: ', '')),
                  backgroundColor: primaryRed,
                ),
              );
            }
          }
        },
      ),
    );
  }
}
