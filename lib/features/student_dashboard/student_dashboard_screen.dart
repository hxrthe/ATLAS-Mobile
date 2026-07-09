import 'package:flutter/material.dart';
import 'tabs/analytics_tab.dart'; // Make sure this is the file where you pasted the StudentProfileScreen earlier
import 'tabs/student_settings_tab.dart';
import 'live_alerts_sheet.dart';
import 'tabs/student_courses_tab.dart';
// TODO: Import your completed Analytics / Student Profile screen here:
// import 'tabs/analytics_tab.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  int _selectedIndex = 0;

  // Brand Colors
  final Color primaryRed = const Color(0xFF8B1515);
  final Color backgroundGrey = const Color(0xFFF4F6F9);
  final Color textGrey = const Color(0xFF8391A1);

  @override
  Widget build(BuildContext context) {
    // 1. The list of screens to switch between
    final List<Widget> tabs = [
      _buildHomeTab(context),         // Slot 1 (Index 0): Dashboard
      const StudentCoursesTab(),      // Slot 2 (Index 1): Courses (Replaced the placeholder!)
      const StudentProfileScreen(),   // Slot 3 (Index 2): Analytics
      const StudentSettingsTab(),     // Slot 4 (Index 3): Settings
    ];

    return Scaffold(
      backgroundColor: backgroundGrey,

      // 2. Updated Bottom Navigation Bar matching your design
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

      // 3. Render the currently selected tab
      body: tabs[_selectedIndex],
    );
  }

  // 4. Extracted Dashboard UI
  Widget _buildHomeTab(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Section with Alert Icon
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
                      'Art Delacion',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: primaryRed),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Alerts Icon with Notification Dot
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        IconButton(
                          icon: Icon(Icons.notifications, color: primaryRed, size: 28),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true, // Allows the sheet to take up more than half the screen
                              backgroundColor: Colors.transparent, // Ensures our custom rounded corners show up
                              builder: (context) => const LiveAlertsSheet(),
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
                    // Profile Avatar
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

            // Active Assessment Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: primaryRed.withOpacity(0.2), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.alarm, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'ONGOING ASSESSMENT',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'CICS-302 — Midterm Exam',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text(
                    'Web Systems & Technologies',
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

            // Recent Grades Section
            Text(
              'RECENTLY GRADED ASSESSMENTS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),

            _buildGradeCard(
              subjectCode: 'CICS-301',
              subjectTitle: 'Software Engineering',
              assessmentName: 'Quiz 2 (TOS Aligned)',
              score: '45/50',
              isPassed: true,
            ),
            const SizedBox(height: 12),
            _buildGradeCard(
              subjectCode: 'CICS-202',
              subjectTitle: 'Database Systems',
              assessmentName: 'Summative Test 1',
              score: '38/50',
              isPassed: true,
            ),
          ],
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
}

// Quick Placeholder Widget so the app compiles immediately without missing files
class PlaceholderTab extends StatelessWidget {
  final String title;
  const PlaceholderTab({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
      ),
    );
  }
}