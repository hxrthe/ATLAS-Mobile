import '../scanner/scanner_screen.dart';
import 'tabs/courses_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/settings_tab.dart';
import 'package:flutter/material.dart';

class FacultyDashboardScreen extends StatefulWidget {
  const FacultyDashboardScreen({super.key});

  @override
  State<FacultyDashboardScreen> createState() => _FacultyDashboardScreenState();
}

class _FacultyDashboardScreenState extends State<FacultyDashboardScreen> {
  int _selectedIndex = 0; // Tracks the active bottom navigation tab

  // Brand Colors mapped from your design
  final Color primaryRed = const Color(0xFF8B1515);
  final Color darkRed = const Color(0xFF5A0C0C);
  final Color successGreen = const Color(0xFF198754);
  final Color textGrey = const Color(0xFF8391A1);
  final Color backgroundGrey = const Color(0xFFF4F6F9);

  @override
  Widget build(BuildContext context) {
    // 1. Define the list of screens to show based on the selected index
    final List<Widget> tabs = [
      _buildHomeTab(context), // We will move your current UI into this method below
      const CoursesTab(),
      const ReportsTab(),
      const SettingsTab(),
    ];

    return Scaffold(
      backgroundColor: backgroundGrey,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: primaryRed,
        unselectedItemColor: textGrey,
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
      // 2. Render the currently selected tab
      body: tabs[_selectedIndex],
    );
  }

  // 3. Wrap your existing dashboard UI inside this helper method
  Widget _buildHomeTab(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              
              // 1. App Header (Profile & Welcome)
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
                        'Dr. Hearty Delacion',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: primaryRed,
                        ),
                      ),
                    ],
                  ),
                  // Profile Avatar with Online Status Indicator
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.grey,
                        backgroundImage: NetworkImage(
                          'https://i.pravatar.cc/150?img=11', // Placeholder avatar
                        ),
                      ),
                      Container(
                        height: 14,
                        width: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          shape: BoxShape.circle,
                          border: Border.all(color: backgroundGrey, width: 2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 2. Active Session Card (Gradient Banner)
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
                      color: primaryRed.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Active Session Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4811B).withOpacity(0.9), // Gold/Orange
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ACTIVE SESSION',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    const Text(
                      'CICS-302',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const Text(
                      'Web Systems & Technologies',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'TOS Matrix: Complete & Proportional',
                          style: TextStyle(
                            color: const Color(0xFF00E676),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Scan Exam Sheets Button
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ScannerScreen(),
                          ),
                        );
                      },

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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 3. Pending Assessments Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PENDING ASSESSMENTS TO SCAN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryRed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '2 EXAMS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Pending Assessment List Items
              _buildAssessmentCard(
                title: 'Midterm Exam (TOS Proportional)',
                subtitle: 'Software Engineering (CICS-301)',
                icon: Icons.description,
                borderColor: primaryRed,
              ),
              const SizedBox(height: 12),
              _buildAssessmentCard(
                title: 'Summative Quiz 3',
                subtitle: 'Database Systems (CICS-202)',
                icon: Icons.format_list_bulleted,
                borderColor: const Color(0xFFD4811B), // Lighter indicator
              ),
              const SizedBox(height: 32),

              // 4. System Events Section
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
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: textGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              _buildSystemEventItem(
                event: 'Processed 42 Exam Sheets — CICS-302',
                time: '10 mins ago',
              ),
              const SizedBox(height: 16),
              _buildSystemEventItem(
                event: 'TOS Matrix recalculation saved — CICS-202',
                time: '2 hours ago',
              ),
            ],
          ),
        ),
    );
  }


  // Helper widget to build the custom Assessment Cards
  Widget _buildAssessmentCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect( // Ensures the left border respects the rounded corners
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primaryRed),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: textGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to build the System Event lines
  Widget _buildSystemEventItem({required String event, required String time}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  color: textGrey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}