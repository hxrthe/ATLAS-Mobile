import 'package:flutter/material.dart';
import '../../grading/grading_repository.dart';
import '../enroll_course_dialog.dart';

class StudentCoursesTab extends StatefulWidget {
  final List<Map<String, dynamic>> courses;
  final bool loading;
  final VoidCallback? onCoursesChanged;

  const StudentCoursesTab({
    super.key,
    required this.courses,
    required this.loading,
    this.onCoursesChanged,
  });

  @override
  State<StudentCoursesTab> createState() => _StudentCoursesTabState();
}

class _StudentCoursesTabState extends State<StudentCoursesTab> {
  final GradingRepository _repo = GradingRepository();

  @override
  Widget build(BuildContext context) {
    const Color textGrey = Color(0xFF8391A1);
    const Color primaryRed = Color(0xFF8B1515);

    if (widget.loading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }

    return SafeArea(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              const Text(
                'ENROLLED COURSES',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
              ),
              const SizedBox(height: 16),

              if (widget.courses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No enrolled courses yet.\nTap + to join a course with a code from your instructor.',
                      textAlign: TextAlign.center, style: TextStyle(color: textGrey)),
                ),

              for (int i = 0; i < widget.courses.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildCourseCard(
                  courseId: widget.courses[i]['course_id'] ?? '',
                  code: widget.courses[i]['course_code'] ?? '',
                  title: widget.courses[i]['course_title'] ?? '',
                  section: widget.courses[i]['section'] ?? '',
                  color: _courseColor(i),
                ),
              ],
              const SizedBox(height: 80), // space for FAB
            ],
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: () => _showEnrollDialog(context),
              backgroundColor: primaryRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Join Course', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Color _courseColor(int index) {
    const colors = [Color(0xFF8B1515), Color(0xFF1565C0), Color(0xFFD4811B), Color(0xFF2E7D32), Color(0xFF6A1B9A)];
    return colors[index % colors.length];
  }

  Widget _buildCourseCard({
    required String courseId,
    required String code,
    required String title,
    required String section,
    required Color color,
  }) {
    return Dismissible(
      key: Key(courseId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Unenroll', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text('Remove $code — $title from your courses?'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF8391A1), fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B1515),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Unenroll'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        try {
          await _repo.unenrollFromCourse(courseId);
          widget.onCoursesChanged?.call();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(code, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                    ),
                    if (section.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(section,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.swipe_left, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    const Text('Swipe left to unenroll', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ),
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
            widget.onCoursesChanged?.call();
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
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }
}
