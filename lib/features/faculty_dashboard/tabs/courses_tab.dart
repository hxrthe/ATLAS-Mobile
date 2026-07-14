import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/dashboard_models.dart';

class CoursesTab extends StatelessWidget {
  final List<Course> courses;
  final Future<void> Function() onRefresh;

  const CoursesTab({super.key, required this.courses, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    // 1. Theme Logic Setup
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryRed = const Color(0xFF8B1515);

    // Explicitly define text colors to guarantee visibility
    final titleColor = isDark ? Colors.white : Colors.black87;
    final metaColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    final headerColor = isDark ? Colors.white : primaryRed;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: primaryRed,
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100), // Extra bottom padding for nav bar
          children: [
            Text('My Classes', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: headerColor)),
            const SizedBox(height: 24),

            if (courses.isEmpty)
              Text('You have no active classes assigned this semester.', style: TextStyle(color: metaColor, fontSize: 16))
            else
              ...courses.map((course) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6),
                          width: 1.5,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? primaryRed.withOpacity(0.3) : primaryRed.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isDark ? primaryRed.withOpacity(0.5) : Colors.transparent),
                                  ),
                                  child: Text(course.code, style: TextStyle(color: isDark ? Colors.red.shade200 : primaryRed, fontWeight: FontWeight.bold)),
                                ),
                                Icon(Icons.more_horiz, color: metaColor),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(course.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor)),
                            const SizedBox(height: 16),
                            Divider(height: 1, color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildCourseMeta(Icons.people_outline, 'Enrolled', '--', metaColor, titleColor),
                                _buildCourseMeta(Icons.access_time, 'Schedule', 'TBA', metaColor, titleColor),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseMeta(IconData icon, String label, String value, Color metaColor, Color valColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: metaColor),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(color: metaColor, fontSize: 12)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: valColor)),
      ],
    );
  }
}