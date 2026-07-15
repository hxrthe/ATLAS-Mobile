import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/dashboard_models.dart';

class StudentGradesTab extends StatelessWidget {
  final String userName;
  final List<StudentGrade> grades;
  final Future<void> Function() onRefresh;

  const StudentGradesTab({super.key, required this.userName, required this.grades, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey.shade400 : const Color(0xFF6B7280);

    // Dynamic pass rate calculation
    final totalExams = grades.length;
    final passedExams = grades.where((g) => g.isPassed).length;
    final passingPercentage = totalExams > 0 ? ((passedExams / totalExams) * 100).toStringAsFixed(0) : '0';

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: const Color(0xFF8B1515),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STUDENT PORTAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: subtitleColor, letterSpacing: 1.0)),
                  Text(userName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
                ],
              ),
              CircleAvatar(radius: 24, backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant, backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=33')),
            ],
          ),
          const SizedBox(height: 32),

          // Overview Glass Card
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.2), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildOverviewStat('Passed', '$passedExams/$totalExams', Colors.green, textColor),
                    Container(height: 40, width: 1, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2)),
                    _buildOverviewStat('Clearance', '$passingPercentage%', const Color(0xFF8B1515), textColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          Text('Recent Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 16),

          if (grades.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No assessments graded yet.', style: TextStyle(color: subtitleColor, fontStyle: FontStyle.italic)),
            )
          else
            ...grades.map((grade) {
              final statusColor = grade.isPassed ? Colors.green : Colors.red;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        title: Text(grade.assessmentTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                        subtitle: Text(grade.courseCode, style: TextStyle(color: subtitleColor, fontSize: 13)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${grade.scoreAchieved} / ${grade.totalScore}',
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 18)),
                            Text(grade.isPassed ? 'Passed' : 'Failed', style: TextStyle(color: statusColor.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildOverviewStat(String label, String value, Color accent, Color textCol) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: accent)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textCol.withOpacity(0.6))),
      ],
    );
  }
}