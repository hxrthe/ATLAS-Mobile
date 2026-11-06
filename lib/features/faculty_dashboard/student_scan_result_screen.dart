import 'package:flutter/material.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_loading_view.dart';
import '../../utils/atlas_alerts.dart';
import '../grading/answer_key.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import '../scanner/omr_models.dart';
import '../scanner/scanner_widgets.dart';

/// Opens the Review-Papers-style Scan Result for a scored student row.
Future<void> openStudentScanResult(
  BuildContext context, {
  required String templateId,
  required String studentId,
  String? templateName,
  double? passingScore,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => StudentScanResultScreen(
        templateId: templateId,
        studentId: studentId,
        templateName: templateName,
        passingScore: passingScore,
      ),
    ),
  );
}

class StudentScanResultScreen extends StatefulWidget {
  final String templateId;
  final String studentId;
  final String? templateName;
  final double? passingScore;

  const StudentScanResultScreen({
    super.key,
    required this.templateId,
    required this.studentId,
    this.templateName,
    this.passingScore,
  });

  @override
  State<StudentScanResultScreen> createState() =>
      _StudentScanResultScreenState();
}

class _StudentScanResultScreenState extends State<StudentScanResultScreen> {
  final GradingRepository _repo = GradingRepository();

  bool _loading = true;
  String? _error;
  BubbleTemplate? _template;
  ScanRecord? _record;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final template = await _repo.fetchTemplateDetail(widget.templateId);
      final scans = await _repo.fetchScans(widget.templateId);
      final scan = _matchScan(scans, widget.studentId);
      if (scan == null) {
        throw Exception(
          'No scanned answer sheet found for ${widget.studentId}.',
        );
      }
      if (!mounted) return;
      setState(() {
        _template = template;
        _record = _toRecord(scan, template);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e, fallback: 'Could not load scan result.');
      });
    }
  }

  static String _normId(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static BubbleScan? _matchScan(List<BubbleScan> scans, String studentId) {
    final target = _normId(studentId);
    if (target.isEmpty) return null;

    BubbleScan? best;
    DateTime? bestAt;
    for (final s in scans) {
      final sid = _normId(s.studentIdentifier);
      if (sid.isEmpty) continue;
      final exact = sid == target;
      final loose = sid.endsWith(target) || target.endsWith(sid);
      if (!exact && !loose) continue;
      final at = DateTime.tryParse(s.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (best == null ||
          (exact && _normId(best.studentIdentifier) != target) ||
          at.isAfter(bestAt!)) {
        best = s;
        bestAt = at;
      }
    }
    return best;
  }

  static ScanRecord _toRecord(BubbleScan scan, BubbleTemplate template) {
    final flagged = <int>[];
    final total = template.totalItems > 0
        ? template.totalItems
        : scan.responses.length;
    for (var i = 1; i <= total; i++) {
      final resp = (scan.responses['$i'] ?? '?').trim();
      final ambiguous = resp.isEmpty ||
          resp == '?' ||
          resp.replaceAll(RegExp(r'[^A-Za-z]'), '').length > 1;
      if (ambiguous) flagged.add(i);
    }
    return ScanRecord(
      id: scan.scanId,
      templateId: scan.templateId,
      templateName: template.name,
      studentIdentifier: scan.studentIdentifier,
      responses: Map<String, String>.from(scan.responses),
      answerKey: Map<String, String>.from(template.answerKey),
      scorePercent: scan.scorePercent,
      scoreRaw: scan.scoreRaw,
      maxScore: scan.maxScore,
      isFlagged: scan.isFlagged || flagged.isNotEmpty,
      flagReason: scan.flagReason,
      flaggedItems: flagged,
      createdAt: DateTime.tryParse(scan.createdAt) ?? DateTime.now(),
      serverScanId: scan.scanId,
    );
  }

  void _editAnswers() {
    final record = _record;
    if (record == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditAnswersSheet(
        record: record,
        template: _template,
        onSave: (updated) => _saveEditedAnswers(record, updated),
      ),
    );
  }

  Future<void> _saveEditedAnswers(
    ScanRecord record,
    Map<String, String> updatedResponses,
  ) async {
    final key = record.answerKey.isNotEmpty
        ? record.answerKey
        : (_template?.answerKey ?? {});
    final total = _template?.totalItems ??
        (key.isNotEmpty ? key.length : updatedResponses.length);
    var correct = 0;
    final flagged = <int>[];
    for (var i = 1; i <= total; i++) {
      final item = i.toString();
      final resp = (updatedResponses[item] ?? '?').trim();
      final expected = key[item] ?? key[item.padLeft(2, '0')];
      final ambiguous = resp.isEmpty ||
          resp == '?' ||
          resp.replaceAll(RegExp(r'[^A-Za-z]'), '').length > 1;
      if (isBonusKey(expected)) {
        correct++;
      } else if (ambiguous) {
        flagged.add(i);
      } else if (isKeyCorrect(resp, expected)) {
        correct++;
      }
    }
    final pct = total > 0 ? (correct / total) * 100.0 : 0.0;
    final scanId = record.serverScanId ?? record.id;
    try {
      final saved = await _repo.updateScan(scanId, {
        'responses': updatedResponses,
        'is_flagged': flagged.isNotEmpty,
        'flag_reason':
            flagged.isEmpty ? null : '${flagged.length} invalid item(s)',
      });
      if (!mounted) return;
      setState(() {
        _record = record.copyWith(
          responses: Map<String, String>.from(saved.responses),
          scorePercent: saved.scorePercent ?? pct,
          scoreRaw: saved.scoreRaw ?? correct.toDouble(),
          maxScore: saved.maxScore ?? total.toDouble(),
          isFlagged: saved.isFlagged || flagged.isNotEmpty,
          flagReason: saved.flagReason,
          clearFlagReason: !(saved.isFlagged || flagged.isNotEmpty),
          flaggedItems: flagged,
        );
      });
      AtlasAlerts.showSuccess(context, 'Answers updated');
    } catch (e) {
      if (!mounted) return;
      AtlasAlerts.showError(
        context,
        friendlyError(e, fallback: 'Could not save answers.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    if (_loading) {
      return Scaffold(
        backgroundColor: c.scaffold,
        appBar: AppBar(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          title: const Text('Scan Result'),
        ),
        body: const AtlasLoadingView(layout: AtlasLoadingLayout.list),
      );
    }
    if (_error != null || _record == null) {
      return Scaffold(
        backgroundColor: c.scaffold,
        appBar: AppBar(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          title: const Text('Scan Result'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? 'Scan not found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return PaperDetailView(
      record: _record!,
      template: _template,
      passingScore:
          widget.passingScore ?? _template?.passingScore ?? 50,
      onBack: () => Navigator.of(context).pop(),
      onEditAnswers: _editAnswers,
    );
  }
}
