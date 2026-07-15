import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/dashboard_models.dart';

class StudentCoursesTab extends StatelessWidget {
  final List<Course> courses;
  final Future<void> Function() onRefresh;

  const StudentCoursesTab({super.key, required this.courses, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey.shade400 : const Color(0xFF6B7280);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: const Color(0xFF8B1515),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          children: [
            Text('Enrolled Courses', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF8B1515))),
            const SizedBox(height: 24),

            if (courses.isEmpty)
              Text('You are not currently enrolled in any classes.', style: TextStyle(color: subtitleColor, fontSize: 16))
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
                        border: Border.all(color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.15), width: 1.5),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(20),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFF8B1515).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.class_outlined, color: Theme.of(context).colorScheme.primary),
                        ),
                        title: Text(course.code, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(course.title, style: TextStyle(color: subtitleColor, fontSize: 14)),
                        ),
                        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: subtitleColor.withOpacity(0.5)),
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
}