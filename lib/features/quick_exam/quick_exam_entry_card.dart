import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_skeleton.dart';
import 'quick_exam_hub_screen.dart';
import 'quick_exam_repository.dart';

/// Entry to the Major Exams hub (Home and Courses tabs) — shortcut for
/// exams, sheets, keys and records. Detailed work lives in Course / Reports.
class QuickExamEntryCard extends StatefulWidget {
  const QuickExamEntryCard({super.key});

  @override
  State<QuickExamEntryCard> createState() => _QuickExamEntryCardState();
}

class _QuickExamEntryCardState extends State<QuickExamEntryCard> {
  final _repo = QuickExamRepository();
  int? _exams;
  int? _sheets;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final exams = await _repo.fetchExams();
      if (!mounted) return;
      setState(() {
        _exams = exams.length;
        _sheets = exams.fold<int>(0, (sum, e) => sum + e.scanCount);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Major exam counts failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open({bool startWithNew = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickExamHubScreen(startWithNew: startWithNew),
      ),
    );
    if (mounted) _loadCounts();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final counts = _exams == null
        ? 'Shortcut for sheets, keys, records & item checks'
        : '$_exams exam${_exams == 1 ? '' : 's'} · $_sheets sheet${_sheets == 1 ? '' : 's'} · open Course or Reports for detail';
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: c.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.quiz_outlined, color: c.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Major Exams',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                AtlasLoadingMark(height: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: AtlasShimmer(
                                    child: SkeletonBox(
                                      height: 11,
                                      width: double.infinity,
                                      radius: 4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Text(
                            counts,
                            style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _open(startWithNew: true),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: const Text('Open'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
