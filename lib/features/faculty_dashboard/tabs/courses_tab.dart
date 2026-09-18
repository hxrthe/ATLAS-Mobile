import 'package:flutter/material.dart';
import '../../grading/grading_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/atlas_loading_view.dart';
import '../../../core/widgets/atlas_pull_to_refresh.dart';

class CoursesTab extends StatefulWidget {
  final void Function(String courseId, String courseCode, String courseTitle)
  onCourseSelected;

  const CoursesTab({super.key, required this.onCourseSelected});

  @override
  State<CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<CoursesTab> {
  final GradingRepository _repository = GradingRepository();
  List<Map<String, dynamic>> _courses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() => _loading = true);
    try {
      final courses = await _repository.fetchFacultyCourses();
      if (mounted) {
        setState(() {
          _courses = courses;
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
    final c = context.atlas;

    return SafeArea(
      child: AtlasPullToRefresh(
        onRefresh: _loadCourses,
        enabled: !_loading,
        child: _loading
            ? const AtlasLoadingView(layout: AtlasLoadingLayout.courses)
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                children: [
                  Text(
                    'COURSE MANAGEMENT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.primary),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadCourses,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_loading && _error == null)
                    for (int i = 0; i < _courses.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _buildCourseCard(
                        _courses[i]['course_code'] ?? '',
                        _courses[i]['course_title'] ?? '',
                        _courses[i]['course_id'] ?? '',
                      ),
                    ],
                  if (!_loading && _error == null && _courses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No courses found in your teaching load.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textSecondary),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildCourseCard(String code, String title, String courseId) {
    final c = context.atlas;

    return GestureDetector(
      onTap: () => widget.onCourseSelected(courseId, code, title),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: c.primary.withValues(alpha: 0.1),
                child: Icon(Icons.book, color: c.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: c.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
