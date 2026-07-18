import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../grading/grading_repository.dart';
import '../../grading/models.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  final GradingRepository _repo = GradingRepository();

  String _userName = 'Student';
  double _overallMastery = 0;
  int _totalScans = 0;
  int _passedScans = 0;
  double _averagePercent = 0;
  Map<String, Map<String, dynamic>> _competencies = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _userName = prefs.getString('user_name') ?? 'Student';

      final courses = await _repo.fetchFacultyCourses();
      final allScans = <BubbleScan>[];
      final templateMap = <String, BubbleTemplate>{};

      for (final c in courses) {
        try {
          final templates = await _repo.fetchTemplates(c['course_id']!);
          for (final t in templates) {
            templateMap[t.templateId] = t;
            try {
              final scans = await _repo.fetchScans(t.templateId);
              allScans.addAll(scans);
            } catch (_) {}
          }
        } catch (_) {}
      }

      final validScans = allScans.where((s) => s.studentIdentifier.isNotEmpty && s.scorePercent != null).toList();

      double totalPercent = 0;
      int passed = 0;
      for (final s in validScans) {
        totalPercent += s.scorePercent!;
        final t = templateMap[s.templateId];
        if (t != null && s.scorePercent! >= (t.passingScore ?? 50)) {
          passed++;
        }
      }

      final avgPercent = validScans.isNotEmpty ? totalPercent / validScans.length : 0.0;

      // Build competency map from scan data grouped by template
      final competencies = <String, Map<String, dynamic>>{};
      for (final s in validScans) {
        final t = templateMap[s.templateId];
        if (t == null) continue;
        final key = t.name;
        if (!competencies.containsKey(key)) {
          competencies[key] = {
            'name': key,
            'total': t.totalItems,
            'scans': <BubbleScan>[],
            'template': t,
          };
        }
        (competencies[key]!['scans'] as List<BubbleScan>).add(s);
      }

      if (mounted) {
        setState(() {
          _totalScans = validScans.length;
          _passedScans = passed;
          _averagePercent = avgPercent;
          double mastery = 0.0;
          if (validScans.isNotEmpty) {
            mastery = passed * 100.0 / validScans.length;
          }
          _overallMastery = mastery;
          _competencies = competencies;
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
    final Color primaryRed = const Color(0xFF8B1515);
    final Color darkRed = const Color(0xFF5A0C0C);
    final Color textGrey = const Color(0xFF8391A1);
    final Color backgroundGrey = const Color(0xFFF8F9FA);

    if (_loading) {
      return Scaffold(
        backgroundColor: backgroundGrey,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: backgroundGrey,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Color(0xFF8B1515))),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final letterGrade = _letterGradeFromPercent(_averagePercent);

    return Scaffold(
      backgroundColor: backgroundGrey,
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACADEMIC PROFILE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textGrey, letterSpacing: 0.5),
                    ),
                    Text(
                      _userName,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E232C)),
                    ),
                  ],
                ),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=5'),
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
            const SizedBox(height: 24),

            // Global Outcome Attainment Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryRed, darkRed],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primaryRed.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Global Outcome Attainment',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '${_overallMastery.toStringAsFixed(0)}% Mastery',
                        style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Container(
                        height: 8,
                        width: _totalScans > 0
                            ? (MediaQuery.of(context).size.width - 48) * (_overallMastery / 100)
                            : 0,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Calculated across $_totalScans graded scans',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Text(letterGrade, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          const Text('AVERAGE GRADE', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 0.5)),
                        ],
                      ),
                      Container(height: 40, width: 1, color: Colors.white.withValues(alpha: 0.2)),
                      Column(
                        children: [
                          Text('${_averagePercent.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          const Text('SCORE AVERAGE', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Assessment Results Section
            if (_competencies.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ASSESSMENT RESULTS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
                  ),
                  Text('$_passedScans / $_totalScans passed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryRed)),
                ],
              ),
              const SizedBox(height: 16),
              ..._competencies.entries.map((entry) {
                final data = entry.value;
                final scans = data['scans'] as List<BubbleScan>;
                final template = data['template'] as BubbleTemplate;
                final avg = scans.isEmpty
                    ? 0.0
                    : scans.map((s) => s.scorePercent ?? 0).reduce((a, b) => a + b) / scans.length;
                final passedCount = scans.where((s) => s.scorePercent! >= (template.passingScore ?? 50)).length;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildResultCard(
                    name: data['name'] as String,
                    avgPercent: avg,
                    passed: passedCount,
                    total: scans.length,
                    passingScore: template.passingScore ?? 50,
                  ),
                );
              }),
            ],

            if (_competencies.isEmpty) ...[
              Text(
                'NO GRADED ASSESSMENTS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              const Text('Submit answer sheets to see your analytics here.', style: TextStyle(fontSize: 13, color: Color(0xFF8391A1))),
            ],
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildResultCard({
    required String name,
    required double avgPercent,
    required int passed,
    required int total,
    required double passingScore,
  }) {
    final bool allPassed = passed == total && total > 0;
    final Color accent = allPassed ? const Color(0xFF00C853) : const Color(0xFFD4811B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '${avgPercent.toStringAsFixed(0)}%',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: accent),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(
                  '$passed/$total passed (${passingScore.toStringAsFixed(0)}% threshold)',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8391A1)),
                ),
              ],
            ),
          ),
          Icon(
            allPassed ? Icons.check_circle : Icons.trending_up,
            color: accent,
            size: 24,
          ),
        ],
      ),
    );
  }

  String _letterGradeFromPercent(double percent) {
    if (percent >= 97) return 'A+';
    if (percent >= 93) return 'A';
    if (percent >= 90) return 'A-';
    if (percent >= 87) return 'B+';
    if (percent >= 83) return 'B';
    if (percent >= 80) return 'B-';
    if (percent >= 77) return 'C+';
    if (percent >= 73) return 'C';
    if (percent >= 70) return 'C-';
    if (percent > 0) return 'D';
    return 'N/A';
  }
}
