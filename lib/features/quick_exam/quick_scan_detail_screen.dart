import 'package:flutter/material.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/atlas_alerts.dart';
import '../grading/answer_key.dart';
import 'quick_exam_models.dart';
import 'quick_exam_repository.dart';
import 'quick_exam_widgets.dart';

/// One recorded sheet: fix the student ID/name or a misread bubble, or delete it.
/// Pops `true` when the record was changed or deleted.
class QuickScanDetailScreen extends StatefulWidget {
  final QuickScan scan;
  final QuickExam? exam;

  const QuickScanDetailScreen({super.key, required this.scan, this.exam});

  @override
  State<QuickScanDetailScreen> createState() => _QuickScanDetailScreenState();
}

class _QuickScanDetailScreenState extends State<QuickScanDetailScreen> {
  final _repo = QuickExamRepository();
  late QuickScan _scan = widget.scan;
  late QuickExam? _exam = widget.exam;
  late final TextEditingController _studentId =
      TextEditingController(text: widget.scan.studentIdentifier ?? '');
  late final TextEditingController _studentName =
      TextEditingController(text: widget.scan.studentName ?? '');
  late Map<String, String> _responses = Map.of(widget.scan.responses);
  bool _saving = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    if (_exam == null || _exam!.answerKey.isEmpty) _loadExam();
  }

  @override
  void dispose() {
    _studentId.dispose();
    _studentName.dispose();
    super.dispose();
  }

  Future<void> _loadExam() async {
    try {
      final exam = await _repo.fetchExam(_scan.examId);
      if (mounted) setState(() => _exam = exam);
    } catch (e) {
      debugPrint('Quick exam fetch failed: $e');
    }
  }

  bool get _dirty =>
      _studentId.text.trim() != (_scan.studentIdentifier ?? '') ||
      _studentName.text.trim() != (_scan.studentName ?? '') ||
      !_sameResponses(_responses, _scan.responses);

  static bool _sameResponses(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  int get _totalItems =>
      _exam?.totalItems ??
      (_scan.maxScore?.toInt() ??
          _responses.keys.map(int.tryParse).whereType<int>().fold(0, (a, b) => a > b ? a : b));

  Future<void> _editResponse(int item) async {
    final letters = 'ABCD'.substring(0, _exam?.numChoices ?? 4).split('');
    final current = _responses['$item'] ?? '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.atlas;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item $item',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final l in letters)
                      ChoiceChip(
                        label: Text(l),
                        selected: current == l,
                        onSelected: (_) => Navigator.pop(ctx, l),
                      ),
                    ChoiceChip(
                      label: const Text('Blank'),
                      selected: current.isEmpty || current == '?',
                      onSelected: (_) => Navigator.pop(ctx, ''),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _responses = Map.of(_responses)..['$item'] = picked;
    });
  }

  Future<void> _save() async {
    final updates = <String, dynamic>{
      if (_studentId.text.trim() != (_scan.studentIdentifier ?? ''))
        'student_identifier': _studentId.text.trim(),
      if (_studentName.text.trim() != (_scan.studentName ?? ''))
        'student_name': _studentName.text.trim(),
      if (!_sameResponses(_responses, _scan.responses)) 'responses': _responses,
    };
    if (updates.isEmpty) return;
    setState(() => _saving = true);
    try {
      final saved = await _repo.updateScan(_scan.scanId, updates);
      if (!mounted) return;
      setState(() {
        _scan = saved;
        _responses = Map.of(saved.responses);
        _studentId.text = saved.studentIdentifier ?? '';
        _studentName.text = saved.studentName ?? '';
        _saving = false;
        _changed = true;
      });
      AtlasAlerts.showSuccess(context, 'Record updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AtlasAlerts.showError(
        context,
        friendlyError(e, fallback: 'Could not update the record.'),
      );
    }
  }

  void _delete() {
    AtlasAlerts.showConfirmation(
      context: context,
      title: 'Delete record?',
      content: 'The sheet of ${_scan.studentLabel} will be removed from this exam.',
      confirmText: 'Delete',
      isDestructive: true,
      onConfirm: () async {
        try {
          await _repo.deleteScan(_scan.scanId);
          if (mounted) Navigator.pop(context, true);
        } catch (e) {
          if (!mounted) return;
          AtlasAlerts.showError(
            context,
            friendlyError(e, fallback: 'Could not delete the record.'),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final key = _exam?.answerKey ?? const <String, String>{};
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sheet record'),
          actions: [
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _buildHeader(c),
            const SizedBox(height: 20),
            const QuickSectionLabel('Student'),
            const SizedBox(height: 10),
            TextField(
              controller: _studentId,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Student ID',
                hintText: 'Leave blank if unknown',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _studentName,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Student name',
                hintText: 'Filled from the ID when known',
              ),
            ),
            const SizedBox(height: 24),
            QuickSectionLabel(
              'Responses',
              trailing: Text(
                'Tap an item to fix it',
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
            ),
            const SizedBox(height: 10),
            if (key.isEmpty && _exam != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'This exam has no answer key yet, so nothing is graded.',
                  style: TextStyle(fontSize: 12, color: c.ambiguous),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 1; i <= _totalItems; i++)
                  _buildResponseCell(c, i, _responses['$i'], key['$i']),
              ],
            ),
          ],
        ),
        bottomNavigationBar: _dirty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: c.onPrimary,
                              ),
                            )
                          : const Text(
                              'Save and re-grade',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildHeader(AtlasColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scan.examName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _scan.subjectName,
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Score ${formatScore(_scan.scoreRaw, _scan.maxScore)} · '
                  '${formatShortDate(_scan.createdAt)}',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                if (_scan.isFlagged && (_scan.flagReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _scan.flagReason!,
                    style: TextStyle(fontSize: 12, color: c.ambiguous),
                  ),
                ],
              ],
            ),
          ),
          QuickScorePill(
            percent: _scan.scorePercent,
            passed: _scan.passed,
            flagged: _scan.isFlagged,
          ),
        ],
      ),
    );
  }

  Widget _buildResponseCell(
    AtlasColors c,
    int item,
    String? response,
    String? correct,
  ) {
    final r = (response ?? '').trim().toUpperCase();
    final blank = r.isEmpty || r == '?';
    final Color tone;
    if (correct == null) {
      tone = c.textSecondary;
    } else if (isBonusKey(correct)) {
      tone = c.bonus;
    } else if (blank || r.length > 1) {
      tone = c.ambiguous;
    } else {
      tone = r == correct ? c.correct : c.incorrect;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _editResponse(item),
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tone.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(
              '$item',
              style: TextStyle(fontSize: 11, color: c.textSecondary),
            ),
            Text(
              blank ? '—' : r,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
            if (correct != null && r != correct)
              Text(
                'key $correct',
                style: TextStyle(fontSize: 10, color: c.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
