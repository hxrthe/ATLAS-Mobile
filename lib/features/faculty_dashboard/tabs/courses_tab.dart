import 'package:flutter/material.dart';
import '../../grading/grading_repository.dart';
import '../../scanner/offline_pack.dart';
import '../../../core/layout/dashboard_insets.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/atlas_loading_view.dart';
import '../../../core/widgets/atlas_pull_to_refresh.dart';
import '../../quick_exam/quick_exam_entry_card.dart';

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
  bool _usingSaved = false;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final courses = await _repository.fetchFacultyCourses();
      await OfflinePack.saveCourses(courses);
      if (mounted) {
        setState(() {
          _courses = courses;
          _usingSaved = false;
          _loading = false;
        });
      }
    } catch (e) {
      final saved = await OfflinePack.loadCourses();
      if (!mounted) return;
      if (saved.isNotEmpty) {
        setState(() {
          _courses = saved;
          _usingSaved = true;
          _error = null;
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        _usingSaved = false;
        _error = friendlyError(e, fallback: 'Could not load your courses. Please try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;

    // Full-bleed over branded grid; bottom nav stays on the Scaffold.
    if (_loading) {
      return const AtlasLoadingView(layout: AtlasLoadingLayout.courses);
    }

    return SafeArea(
      bottom: false,
      child: AtlasPullToRefresh(
        onRefresh: _loadCourses,
        enabled: true,
        child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: dashboardScrollPadding(context),
                children: [
                  Text(
                    'MAJOR EXAMINATION',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const QuickExamEntryCard(),
                  const SizedBox(height: 28),
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
                  if (_usingSaved)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Showing courses saved on this device.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
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
                  if (_error == null)
                    for (int i = 0; i < _courses.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _buildCourseCard(
                        _courses[i]['course_code'] ?? '',
                        _courses[i]['course_title'] ?? '',
                        _courses[i]['course_id'] ?? '',
                      ),
                    ],
                  if (_error == null && _courses.isEmpty)
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
