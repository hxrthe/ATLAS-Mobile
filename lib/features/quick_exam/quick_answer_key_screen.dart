import 'package:flutter/material.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/atlas_alerts.dart';
import '../grading/answer_key.dart';
import 'quick_exam_models.dart';
import 'quick_exam_repository.dart';
import 'quick_exam_widgets.dart';

/// Tap-to-fill answer key for a quick exam. Pops the updated exam on save.
class QuickAnswerKeyScreen extends StatefulWidget {
  final QuickExam exam;

  const QuickAnswerKeyScreen({super.key, required this.exam});

  @override
  State<QuickAnswerKeyScreen> createState() => _QuickAnswerKeyScreenState();
}

class _QuickAnswerKeyScreenState extends State<QuickAnswerKeyScreen> {
  static const double _rowHeight = 52;

  final _repo = QuickExamRepository();
  final _scroll = ScrollController();
  late final Map<String, String> _key = Map.of(widget.exam.answerKey);
  late final List<String> _letters =
      'ABCD'.substring(0, widget.exam.numChoices).split('');
  bool _saving = false;
  bool _dirty = false;

  int get _total => widget.exam.totalItems;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String? _partStartingAt(int item) {
    for (final p in widget.exam.parts) {
      if (p.startItem == item && widget.exam.parts.length > 1) return p.label;
    }
    return null;
  }

  void _pick(int item, String letter) {
    setState(() {
      final k = '$item';
      if (_key[k] == letter) {
        _key.remove(k);
      } else {
        _key[k] = letter;
      }
      _dirty = true;
    });
    if (item < _total && _scroll.hasClients) {
      final target = (item - 2) * _rowHeight;
      if (target > _scroll.offset + _rowHeight * 3) {
        _scroll.animateTo(
          target.clamp(0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  /// Accepts "ABCDA…" or "1A 2B, 3-C"; ignores letters outside the choices.
  Map<String, String> _parse(String raw) {
    final text = raw.toUpperCase();
    final out = <String, String>{};
    final numbered = RegExp(r'(\d+)\s*[\.\)\-:=]?\s*([A-D*])');
    final matches = numbered.allMatches(text).toList();
    if (matches.isNotEmpty) {
      for (final m in matches) {
        final n = int.parse(m.group(1)!);
        final l = m.group(2)!;
        if (n >= 1 && n <= _total && (_letters.contains(l) || l == bonusKey)) {
          out['$n'] = l;
        }
      }
      return out;
    }
    var i = 1;
    for (final ch in text.split('')) {
      if (i > _total) break;
      if (ch == '-' || ch == '_' || ch == '?') {
        i++;
      } else if (_letters.contains(ch) || ch == bonusKey) {
        out['${i++}'] = ch;
      }
    }
    return out;
  }

  Future<void> _paste() async {
    final parsed = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _PasteKeyDialog(parse: _parse),
    );
    if (parsed == null || !mounted) return;
    if (parsed.isEmpty) {
      AtlasAlerts.showError(context, 'No answers recognised.');
      return;
    }
    setState(() {
      _key.addAll(parsed);
      _dirty = true;
    });
    AtlasAlerts.showSuccess(context, 'Filled ${parsed.length} item(s).');
  }

  void _clear() {
    AtlasAlerts.showConfirmation(
      context: context,
      title: 'Clear answer key?',
      content: 'All selected answers on this screen will be removed.',
      confirmText: 'Clear',
      isDestructive: true,
      onConfirm: () => setState(() {
        _key.clear();
        _dirty = true;
      }),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await _repo.saveAnswerKey(widget.exam.examId, _key);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AtlasAlerts.showError(
        context,
        friendlyError(e, fallback: 'Could not save the answer key.'),
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your answer key changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    final keyed = _key.length;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Answer key'),
          actions: [
            IconButton(
              tooltip: 'Paste answers',
              onPressed: _paste,
              icon: const Icon(Icons.content_paste_rounded),
            ),
            IconButton(
              tooltip: 'Clear all',
              onPressed: keyed == 0 ? null : _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: c.card,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.exam.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '$keyed / $_total keyed',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: keyed == _total ? c.pass : c.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _total == 0 ? 0 : keyed / _total,
                      minHeight: 6,
                      backgroundColor: c.cardMuted,
                      color: keyed == _total ? c.pass : c.primary,
                    ),
                  ),
                  if (widget.exam.scanCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Saving re-grades all ${widget.exam.scanCount} recorded sheet(s).',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: c.divider),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: _total,
                itemBuilder: (context, index) {
                  final item = index + 1;
                  final part = _partStartingAt(item);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (part != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          child: Text(
                            part.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      _buildRow(c, item),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
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
                    : Text(
                        keyed < _total
                            ? 'Save key ($keyed of $_total)'
                            : 'Save answer key',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(AtlasColors c, int item) {
    final selected = _key['$item'];
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '$item.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected == null ? c.textSecondary : c.textPrimary,
                ),
              ),
            ),
            for (final l in _letters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _pick(item, l),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected == l ? c.primary : Colors.transparent,
                      border: Border.all(
                        color: selected == l ? c.primary : c.border,
                        width: 1.6,
                      ),
                    ),
                    child: Text(
                      l,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected == l ? c.onPrimary : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            BonusKeyChip(
              selected: isBonusKey(selected),
              onTap: () => _pick(item, bonusKey),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasteKeyDialog extends StatefulWidget {
  final Map<String, String> Function(String raw) parse;

  const _PasteKeyDialog({required this.parse});

  @override
  State<_PasteKeyDialog> createState() => _PasteKeyDialogState();
}

class _PasteKeyDialogState extends State<_PasteKeyDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste answer key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Type the answers in order (e.g. ABDCA…, use - to skip, * for bonus) or '
            'numbered (e.g. 1A 2C 3*).',
            style: TextStyle(fontSize: 13, color: context.atlas.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 4,
            textCapitalization: TextCapitalization.characters,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, widget.parse(_ctrl.text)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
