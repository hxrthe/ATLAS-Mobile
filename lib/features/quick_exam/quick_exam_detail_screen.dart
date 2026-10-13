import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_pull_to_refresh.dart';
import '../../core/widgets/atlas_skeleton.dart';
import '../../utils/atlas_alerts.dart';
import '../grading/answer_key.dart';
import '../scanner/scanner_screen.dart';
import 'quick_answer_key_screen.dart';
import 'quick_exam_form_screen.dart';
import 'quick_exam_models.dart';
import 'quick_exam_repository.dart';
import 'quick_exam_widgets.dart';
import 'quick_scan_detail_screen.dart';
import 'quick_sheet.dart';

enum _ScanSort { recent, studentId, scoreHigh, scoreLow }

enum _SheetAction { download, share, print }

class QuickExamDetailScreen extends StatefulWidget {
  final QuickExam exam;

  const QuickExamDetailScreen({super.key, required this.exam});

  @override
  State<QuickExamDetailScreen> createState() => _QuickExamDetailScreenState();
}

class _QuickExamDetailScreenState extends State<QuickExamDetailScreen>
    with TickerProviderStateMixin {
  final _repo = QuickExamRepository();
  late QuickExam _exam = widget.exam;
  late TabController _tabs = TabController(length: _tabCount, vsync: this);
  QuickExamRecords? _records;
  bool _loading = true;
  String? _error;
  bool _busyPdf = false;
  _ScanSort _sort = _ScanSort.recent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Records, Item analysis, plus Questions when the faculty pasted them.
  int get _tabCount => _exam.hasQuestions ? 3 : 2;

  /// Call inside setState after [_exam] changes.
  void _syncTabs() {
    if (_tabs.length == _tabCount) return;
    final old = _tabs;
    _tabs = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: old.index.clamp(0, _tabCount - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _records == null;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.fetchExam(_exam.examId),
        _repo.fetchExamRecords(_exam.examId),
      ]);
      if (!mounted) return;
      setState(() {
        _exam = results[0] as QuickExam;
        _records = results[1] as QuickExamRecords;
        _loading = false;
        _syncTabs();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e, fallback: 'Could not load this exam.');
      });
    }
  }

  Future<void> _openAnswerKey() async {
    final saved = await Navigator.push<QuickExam>(
      context,
      MaterialPageRoute(builder: (_) => QuickAnswerKeyScreen(exam: _exam)),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _exam = saved;
      _syncTabs();
    });
    AtlasAlerts.showSuccess(context, 'Answer key saved');
    _load();
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<QuickExam>(
      context,
      MaterialPageRoute(builder: (_) => QuickExamFormScreen(exam: _exam)),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _exam = saved;
      _syncTabs();
    });
    _load();
  }

  void _delete() {
    final count = _records?.scanCount ?? _exam.scanCount;
    AtlasAlerts.showConfirmation(
      context: context,
      title: 'Delete exam?',
      content: count > 0
          ? '"${_exam.name}" and its $count recorded sheet(s) will be permanently deleted.'
          : '"${_exam.name}" will be permanently deleted.',
      confirmText: 'Delete',
      isDestructive: true,
      onConfirm: () async {
        try {
          await _repo.deleteExam(_exam.examId);
          if (mounted) Navigator.pop(context, true);
        } catch (e) {
          if (!mounted) return;
          AtlasAlerts.showError(
            context,
            friendlyError(e, fallback: 'Could not delete the exam.'),
          );
        }
      },
    );
  }

  String get _pdfName {
    final base = _exam.name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return '${base.isEmpty ? 'Exam' : base} answer sheet';
  }

  Future<void> _sheetPdf(_SheetAction action) async {
    if (_busyPdf) return;
    setState(() => _busyPdf = true);
    try {
      final bytes = await QuickSheet.buildPdf(
        totalItems: _exam.totalItems,
        numChoices: _exam.numChoices,
        qrPayload: _exam.qrPayload,
        idColumns: _exam.numIdColumns,
        compact: _exam.isCompact,
        title: _exam.name,
      );
      switch (action) {
        case _SheetAction.download:
          final saved = await FilePicker.saveFile(
            dialogTitle: 'Save answer sheet',
            fileName: '$_pdfName.pdf',
            bytes: bytes,
            mimeType: 'application/pdf',
            type: FileType.custom,
            allowedExtensions: const ['pdf'],
          );
          if (saved != null && mounted) {
            AtlasAlerts.showSuccess(
              context,
              'Answer sheet saved to your phone',
            );
          }
        case _SheetAction.share:
          await Printing.sharePdf(bytes: bytes, filename: '$_pdfName.pdf');
        case _SheetAction.print:
          await Printing.layoutPdf(
            onLayout: (_) async => bytes,
            name: _pdfName,
          );
      }
    } catch (e) {
      if (mounted) {
        AtlasAlerts.showError(
          context,
          friendlyError(e, fallback: 'Could not create the answer sheet.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  Future<void> _scan() async {
    if (!_exam.hasFullKey) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            _exam.hasAnyKey ? 'Answer key incomplete' : 'No answer key',
          ),
          content: Text(
            _exam.hasAnyKey
                ? 'Only ${_exam.keyedItems} of ${_exam.totalItems} items have answers. '
                      'Sheets are re-graded when you finish the key.'
                : 'Scanned sheets will be recorded and graded once you add the answer key.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Scan anyway'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(quickExam: _exam.toTemplate()),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openScan(QuickScan scan) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QuickScanDetailScreen(scan: scan, exam: _exam),
      ),
    );
    if (changed == true && mounted) _load();
  }

  List<QuickScan> get _sortedScans {
    final list = List<QuickScan>.of(_records?.scans ?? const []);
    switch (_sort) {
      case _ScanSort.recent:
        list.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
      case _ScanSort.studentId:
        list.sort((a, b) => a.studentLabel.compareTo(b.studentLabel));
      case _ScanSort.scoreHigh:
        list.sort(
          (a, b) => (b.scorePercent ?? -1).compareTo(a.scorePercent ?? -1),
        );
      case _ScanSort.scoreLow:
        list.sort(
          (a, b) => (a.scorePercent ?? 101).compareTo(b.scorePercent ?? 101),
        );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Scaffold(
      appBar: AppBar(
        title: Text(_exam.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _edit();
                case 'download':
                  _sheetPdf(_SheetAction.download);
                case 'print':
                  _sheetPdf(_SheetAction.print);
                case 'share':
                  _sheetPdf(_SheetAction.share);
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit exam')),
              PopupMenuItem(
                value: 'download',
                child: Text('Save sheet to phone'),
              ),
              PopupMenuItem(value: 'print', child: Text('Print sheet')),
              PopupMenuItem(value: 'share', child: Text('Share sheet PDF')),
              PopupMenuItem(value: 'delete', child: Text('Delete exam')),
            ],
          ),
        ],
      ),
      body: AtlasPullToRefresh(
        onRefresh: _load,
        enabled: !_loading,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _buildHeader(c)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabs,
                  labelColor: c.primary,
                  unselectedLabelColor: c.textSecondary,
                  indicatorColor: c.primary,
                  tabs: [
                    Tab(
                      text:
                          'Records (${_records?.scanCount ?? _exam.scanCount})',
                    ),
                    const Tab(text: 'Item analysis'),
                    if (_exam.hasQuestions) const Tab(text: 'Questions'),
                  ],
                ),
                c.scaffold,
              ),
            ),
          ],
          body: _loading
              ? const AtlasSkeletonList()
              : _error != null
              ? ListView(
                  children: [QuickErrorState(message: _error!, onRetry: _load)],
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildRecords(c),
                    _buildItemAnalysis(c),
                    if (_exam.hasQuestions) _buildQuestions(c),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(AtlasColors c) {
    final r = _records;
    final keyColor = _exam.hasFullKey
        ? c.pass
        : (_exam.hasAnyKey ? c.ambiguous : c.fail);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.primary, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _exam.subjectName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: c.primary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_exam.totalItems} items · ${_exam.choiceRange} · '
                  '${_exam.numIdColumns}-digit ID · pass ${formatPercent(_exam.passingPercent)}',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.vpn_key_rounded, size: 16, color: keyColor),
                    const SizedBox(width: 6),
                    Text(
                      _exam.hasFullKey
                          ? 'Answer key complete'
                          : 'Answer key ${_exam.keyedItems}/${_exam.totalItems}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: keyColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openAnswerKey,
                        icon: const Icon(Icons.vpn_key_outlined, size: 18),
                        label: const Text('Key'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busyPdf
                            ? null
                            : () => _sheetPdf(_SheetAction.download),
                        icon: _busyPdf
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _scan,
                        icon: const Icon(
                          Icons.document_scanner_outlined,
                          size: 18,
                        ),
                        label: const Text('Scan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              QuickStatTile(
                label: 'Average',
                value: formatPercent(r?.averagePercent),
              ),
              const SizedBox(width: 8),
              QuickStatTile(
                label: 'Highest',
                value: formatPercent(r?.highestPercent),
                color: c.pass,
              ),
              const SizedBox(width: 8),
              QuickStatTile(
                label: 'Lowest',
                value: formatPercent(r?.lowestPercent),
                color: c.fail,
              ),
              const SizedBox(width: 8),
              QuickStatTile(
                label: 'Passed',
                value: r == null ? '—' : '${r.passedCount}/${r.scanCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestions(AtlasColors c) {
    final questions = _exam.questions;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: questions.length,
      itemBuilder: (_, i) {
        final q = questions[i];
        final answer = _exam.answerKey['${q.itemNumber}'] ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${q.itemNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: c.primary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q.text.trim().isEmpty
                          ? 'Item ${q.itemNumber}'
                          : q.text.trim(),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: c.textPrimary,
                      ),
                    ),
                    if (q.choices.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (var j = 0; j < q.choices.length && j < 4; j++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${'ABCD'[j]}. ${q.choices[j]}',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: 'ABCD'[j] == answer
                                  ? c.correct
                                  : c.textSecondary,
                              fontWeight: 'ABCD'[j] == answer
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (answer.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isBonusKey(answer) ? c.pass : c.primary,
                  ),
                  child: isBonusKey(answer)
                      ? Icon(Icons.star_rounded, size: 18, color: c.onPrimary)
                      : Text(
                          answer,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: c.onPrimary,
                          ),
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecords(AtlasColors c) {
    final scans = _sortedScans;
    if (scans.isEmpty) {
      return ListView(
        children: [
          QuickEmptyState(
            icon: Icons.document_scanner_outlined,
            title: 'No sheets recorded yet',
            message:
                'Print the answer sheet, then tap Scan to record answered sheets.',
            action: ElevatedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan sheets'),
            ),
          ),
        ],
      );
    }
    final flagged = _records?.flaggedCount ?? 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          children: [
            if (flagged > 0)
              Text(
                '$flagged flagged',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.ambiguous,
                ),
              ),
            const Spacer(),
            DropdownButton<_ScanSort>(
              value: _sort,
              underline: const SizedBox.shrink(),
              style: TextStyle(fontSize: 13, color: c.textPrimary),
              dropdownColor: c.card,
              items: const [
                DropdownMenuItem(
                  value: _ScanSort.recent,
                  child: Text('Most recent'),
                ),
                DropdownMenuItem(
                  value: _ScanSort.studentId,
                  child: Text('Student ID'),
                ),
                DropdownMenuItem(
                  value: _ScanSort.scoreHigh,
                  child: Text('Highest score'),
                ),
                DropdownMenuItem(
                  value: _ScanSort.scoreLow,
                  child: Text('Lowest score'),
                ),
              ],
              onChanged: (v) => setState(() => _sort = v ?? _sort),
            ),
          ],
        ),
        for (final s in scans) ...[
          QuickScanTile(scan: s, onTap: () => _openScan(s)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildItemAnalysis(AtlasColors c) {
    final items = _records?.items ?? const <QuickItemStat>[];
    if ((_records?.scanCount ?? 0) == 0 || items.isEmpty) {
      return ListView(
        children: const [
          QuickEmptyState(
            icon: Icons.insights_outlined,
            title: 'No data yet',
            message: 'Item analysis appears after sheets are recorded.',
          ),
        ],
      );
    }
    final letters = 'ABCD'.substring(0, _exam.numChoices).split('');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final it = items[i];
        final pct = it.percentCorrect;
        final tone = pct == null
            ? c.textSecondary
            : pct >= 75
            ? c.pass
            : pct >= 40
            ? c.ambiguous
            : c.fail;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Item ${it.item}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    it.correctAnswer == null
                        ? 'no key'
                        : 'key ${keyLabel(it.correctAnswer)}',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                  const Spacer(),
                  Text(
                    pct == null ? '—' : '${formatPercent(pct)} correct',
                    style: TextStyle(fontWeight: FontWeight.w800, color: tone),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct ?? 0) / 100,
                  minHeight: 6,
                  backgroundColor: c.cardMuted,
                  color: tone,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  for (final l in letters)
                    Text(
                      '$l: ${it.choiceCounts[l] ?? 0}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: l == it.correctAnswer
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: l == it.correctAnswer
                            ? c.correct
                            : c.textSecondary,
                      ),
                    ),
                  Text(
                    'Blank: ${it.blank}',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Record row used by the exam detail and the Records tab.
class QuickScanTile extends StatelessWidget {
  final QuickScan scan;
  final VoidCallback onTap;
  final bool showExam;

  const QuickScanTile({
    super.key,
    required this.scan,
    required this.onTap,
    this.showExam = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final name = (scan.studentName ?? '').trim();
    final subtitle = [
      if (showExam) '${scan.examName} · ${scan.subjectName}',
      'Score ${formatScore(scan.scoreRaw, scan.maxScore)} · ${formatShortDate(scan.createdAt)}',
    ].join('\n');
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scan.isFlagged ? c.ambiguous : c.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: c.primary.withValues(alpha: 0.1),
                child: Icon(
                  scan.isFlagged ? Icons.flag_rounded : Icons.person_outline,
                  size: 18,
                  color: scan.isFlagged ? c.ambiguous : c.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty
                          ? scan.studentLabel
                          : '$name · ${scan.studentLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              QuickScorePill(
                percent: scan.scorePercent,
                passed: scan.passed,
                flagged: scan.isFlagged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;

  _TabBarDelegate(this.tabBar, this.background);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Container(color: background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.tabBar != tabBar || old.background != background;
}
