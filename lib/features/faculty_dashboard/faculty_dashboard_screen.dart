import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../scanner/scanner_screen.dart';
import 'tabs/courses_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/settings_tab.dart';
import '../dashboard/dashboard_repository.dart';
import '../../models/dashboard_models.dart';

class FacultyDashboardScreen extends StatefulWidget {
  const FacultyDashboardScreen({super.key});

  @override
  State<FacultyDashboardScreen> createState() => _FacultyDashboardScreenState();
}

class _FacultyDashboardScreenState extends State<FacultyDashboardScreen> {
  int _selectedIndex = 0;

  final DashboardRepository _repository = DashboardRepository();
  late Future<Map<String, List<dynamic>>> _dashboardData;
  String _userName = 'Loading...';

  final Color primaryRed = const Color(0xFF8B1515);
  final Color darkRed = const Color(0xFF5A0C0C);
  final Color successGreen = const Color(0xFF198754);

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _dashboardData = _repository.fetchFacultyData();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Instructor';
    });
  }

  Future<void> _refreshDashboard() async {
    setState(() {
      _dashboardData = _repository.fetchFacultyData();
    });
    await _dashboardData;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedIconColor = isDark ? Colors.grey.shade500 : const Color(0xFF8391A1);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF0A0A0A), const Color(0xFF2A0808)]
                    : [const Color(0xFFF4F6F9), const Color(0xFFFFEBEB)],
              ),
            ),
          ),

          SafeArea(
            child: FutureBuilder<Map<String, List<dynamic>>>(
              future: _dashboardData,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: primaryRed));
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)));
                } else if (!snapshot.hasData) {
                  return Center(child: Text('No data available.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)));
                }

                final courses = snapshot.data!['courses'] as List<Course>;
                final assessments = snapshot.data!['assessments'] as List<Assessment>;

                return IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _buildHomeTab(context, courses, assessments, isDark),
                    CoursesTab(courses: courses, onRefresh: _refreshDashboard),
                    ReportsTab(assessments: assessments, onRefresh: _refreshDashboard),
                    SettingsTab(userName: _userName),
                  ],
                );
              },
            ),
          ),
        ],
      ),

      extendBody: true,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.7),
              border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white, width: 0.5)),
            ),
            child: BottomNavigationBar(
              elevation: 0,
              backgroundColor: Colors.transparent,
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
              selectedItemColor: primaryRed,
              unselectedItemColor: unselectedIconColor,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Courses'),
                BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Reports'),
                BottomNavigationBarItem(icon: Icon(Icons.manage_accounts), label: 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context, List<Course> courses, List<Assessment> assessments, bool isDark) {
    final hasActiveCourse = courses.isNotEmpty;
    final activeCourseCode = hasActiveCourse ? courses.first.code : 'No Active Classes';
    final activeCourseTitle = hasActiveCourse ? courses.first.title : 'Enjoy your break!';

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      color: primaryRed,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WELCOME INSTRUCTOR',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: 1.0),
                    ),
                    Text(_userName,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ],
                ),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      backgroundImage: const NetworkImage('https://i.pravatar.cc/150?img=11'),
                    ),
                    Container(
                      height: 14, width: 14,
                      decoration: BoxDecoration(
                        color: successGreen, shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),

            // FIXED: Red Glassmorphism Active Session Card
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primaryRed.withOpacity(isDark ? 0.4 : 0.8), // Adjusted for better visibility
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2), // Forced pure white for contrast on red
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: const Text('ACTIVE SESSION', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),

                      // Forced pure white text for readability against the red background
                      Text(activeCourseCode, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1)),
                      Text(activeCourseTitle, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16, fontWeight: FontWeight.w500)),

                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ScannerScreen(
                              accessToken: "YOUR_USER_JWT_TOKEN",    // Replace with your actual token variable
                            ),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white, // Solid white button
                          foregroundColor: primaryRed, // Red text/icon
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Scan Exam Sheets', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PENDING ASSESSMENTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryRed.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${assessments.length} EXAMS', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (assessments.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('No pending exams.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)))
            else
              ...assessments.map((assessment) {
                final prettyDate = DateFormat('MMM d, yyyy').format(DateTime.parse(assessment.dateDue));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _buildGlassCard(
                    context: context,
                    isDark: isDark,
                    title: assessment.title,
                    subtitle: '${assessment.courseCode} • Due: $prettyDate',
                    icon: Icons.description,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // FIXED: Reusable Frosted Glass Card Widget now using dynamic text themes
  Widget _buildGlassCard({required BuildContext context, required bool isDark, required String title, required String subtitle, required IconData icon}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6),
                width: 1.5
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primaryRed.withOpacity(0.2)),
                  ),
                  child: Icon(icon, color: isDark ? Colors.red.shade300 : primaryRed)
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Uses onSurface for high contrast
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                // Uses onSurfaceVariant for subtitle
                Text(subtitle, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
              Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}