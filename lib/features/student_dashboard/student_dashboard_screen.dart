import 'dart:ui'; // Required for ImageFilter.blur
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dashboard/dashboard_repository.dart';
import '../../models/dashboard_models.dart';
import 'tabs/student_courses_tab.dart';
import 'tabs/student_grades_tab.dart';
import 'tabs/student_settings_tab.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  _StudentDashboardScreenState createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  int _selectedIndex = 0;
  final DashboardRepository _repository = DashboardRepository();
  late Future<Map<String, List<dynamic>>> _dashboardData;
  String _userName = 'Loading...';

  final Color primaryRed = const Color(0xFF8B1515);
  final Color successGreen = const Color(0xFF198754);

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _dashboardData = _repository.fetchStudentData();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Student';
    });
  }

  Future<void> _refreshStudentData() async {
    setState(() {
      _dashboardData = _repository.fetchStudentData();
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
          // Ambient Mesh Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF0A0A0A), const Color(0xFF1A1525)] // Deep dark canvas
                    : [const Color(0xFFF4F6F9), const Color(0xFFEBF3FF)], // Light clean canvas
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
                  return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: isDark ? Colors.white : Colors.black)));
                } else if (!snapshot.hasData) {
                  return Center(child: Text('No data available.', style: TextStyle(color: isDark ? Colors.white : Colors.black)));
                }

                final courses = snapshot.data!['courses'] as List<Course>;
                final grades = snapshot.data!['grades'] as List<StudentGrade>;

                return IndexedStack(
                  index: _selectedIndex,
                  children: [
                    StudentGradesTab(userName: _userName, grades: grades, onRefresh: _refreshStudentData),
                    StudentCoursesTab(courses: courses, onRefresh: _refreshStudentData),
                    StudentSettingsTab(userName: _userName),
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
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'Grades'),
                BottomNavigationBarItem(icon: Icon(Icons.class_outlined), label: 'Courses'),
                BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}