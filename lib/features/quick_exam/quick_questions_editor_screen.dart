import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../utils/atlas_alerts.dart';
import '../grading/answer_key.dart';
import '../grading/course_exam_parser.dart';
import 'quick_exam_models.dart';
import 'quick_exam_widgets.dart';

/// What the editor hands back: questions (null when none were written) and
/// the answer key keyed by item number.
class QuickQuestionsResult {
  final List<Map<String, dynamic>>? questions;
  final Map<String, String> answerKey;

  const QuickQuestionsResult({required this.questions, required this.answerKey});

  int get questionCount => questions?.where((q) {
        final text = (q['question_text'] as String).trim();
        final choices = (q['choices'] as List).cast<String>();
        return text.isNotEmpty || choices.any((c) => c.trim().isNotEmpty);
      }).length ??
      0;
}

class _ItemDraft {
  final TextEditingController question;
  final List<TextEditingController> choices;
  String? answer;

  _ItemDraft({String question = '', List<String> choices = const [], this.answer})
      : question = TextEditingController(text: question),
        choices = List.generate(
          4,
          (i) => TextEditingController(text: i < choices.length ? choices[i] : ''),
        );

  void dispose() {
    question.dispose();
    for (final c in choices) {
      c.dispose();
    }
  }
}

/// Paste or type the questions, choices and answer key for a quick exam.
class QuickQuestionsEditorScreen extends StatefulWidget {
  final int totalItems;
  final int numChoices;
  final List<QuickQuestion> initialQuestions;
  final Map<String, String> initialKey;

  const QuickQuestionsEditorScreen({
    super.key,
    required this.totalItems,
    required this.numChoices,
    this.initialQuestions = const [],
    this.initialKey = const {},
  });

  @override
  State<QuickQuestionsEditorScreen> createState() => _QuickQuestionsEditorScreenState();
}

class _QuickQuestionsEditorScreenState extends State<QuickQuestionsEditorScreen> {
  final _pasteQuestions = TextEditingController();
  final _pasteKey = TextEditingController();
  late final List<_ItemDraft> _items;
  bool _manual = false;

  String get _letters => examLetters.substring(0, widget.numChoices);

  @override
  void initState() {
    super.initState();
    final byNumber = {for (final q in widget.initialQuestions) q.itemNumber: q};
    _items = List.generate(widget.totalItems, (i) {
      final q = byNumber[i + 1];
      final a = widget.initialKey['${i + 1}'];
      return _ItemDraft(
        question: q?.text ?? '',
        choices: q?.choices ?? const [],
        answer: a != null && (_letters.contains(a) || isBonusKey(a)) ? a : null,
      );
    });
    _manual = widget.initialQuestions.isNotEmpty || widget.initialKey.isNotEmpty;
  }

  @override
  void dispose() {
    _pasteQuestions.dispose();
    _pasteKey.dispose();
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  int get _answered => _items.where((it) => it.answer != null).length;

  void _applyPaste() {
    final parsed = parseExamQuestions(_pasteQuestions.text);
    final key = parseAnswerKey(_pasteKey.text, maxItems: widget.totalItems);
    if (parsed.isEmpty && key.isEmpty) {
      AtlasAlerts.showError(context, 'Nothing to read — paste questions or an answer key.');
      return;
    }
    var answers = 0;
    setState(() {
      for (var i = 0; i < widget.totalItems; i++) {
        final it = _items[i];
        if (i < parsed.length) {
          final p = parsed[i];
          it.question.text = p.question.trim();
          for (var c = 0; c < 4; c++) {
            it.choices[c].text = c < p.choices.length ? p.choices[c].trim() : '';
          }
          if (p.answer != null && _letters.contains(p.answer!)) it.answer = p.answer;
        }
        final k = key[i + 1];
        if (k != null && _letters.contains(k)) it.answer = k;
        if (it.answer != null) answers++;
      }
      _manual = true;
    });
    final extra = parsed.length > widget.totalItems
        ? ' ${parsed.length - widget.totalItems} extra question(s) were left out.'
        : parsed.isNotEmpty && parsed.length < widget.totalItems
            ? ' Only ${parsed.length} of ${widget.totalItems} questions were found.'
            : '';
    AtlasAlerts.showSuccess(
      context,
      'Filled ${parsed.length.clamp(0, widget.totalItems)} question(s) and $answers answer(s).$extra',
    );
  }

  void _done() {
    final questions = [
      for (final it in _items)
        {
          'question_text': it.question.text.trim(),
          'choices': [
            for (var c = 0; c < widget.numChoices; c++) it.choices[c].text.trim(),
          ],
        },
    ];
    final anyWritten = questions.any(
      (q) =>
          (q['question_text'] as String).isNotEmpty ||
          (q['choices'] as List<String>).any((c) => c.isNotEmpty),
    );
    Navigator.pop(
      context,
      QuickQuestionsResult(
        questions: anyWritten ? questions : null,
        answerKey: {
          for (var i = 0; i < _items.length; i++)
            if (_items[i].answer != null) '${i + 1}': _items[i].answer!,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Scaffold(
      appBar: AppBar(title: const Text('Questions & answer key')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Paste'), icon: Icon(Icons.content_paste, size: 18)),
                  ButtonSegment(value: true, label: Text('Manual'), icon: Icon(Icons.edit_note, size: 18)),
                ],
                selected: {_manual},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _manual = s.first),
              ),
            ),
          ),
          Expanded(child: _manual ? _buildManual(c) : _buildPaste(c)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _done,
              child: Text(
                'Done · $_answered/${widget.totalItems} answered',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaste(AtlasColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const QuickSectionLabel('Questions and choices'),
        const SizedBox(height: 8),
        TextField(
          controller: _pasteQuestions,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(
            hintText: '1. What is 2 + 2?\nA. 3\nB. 4 *\nC. 5\nD. 6\nAnswer: B',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Number each question. Mark the right choice with * or an "Answer: B" line, '
          'or use the answer key box below.',
          style: TextStyle(fontSize: 12, color: c.textSecondary),
        ),
        const SizedBox(height: 20),
        const QuickSectionLabel('Answer key (optional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _pasteKey,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: '1.B 2.C 3.A …  or  BCAD…'),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _applyPaste,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Read pasted text'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'You can review and fix every item in Manual afterwards.',
          style: TextStyle(fontSize: 12, color: c.textSecondary),
        ),
      ],
    );
  }

  Widget _buildManual(AtlasColors c) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) => _buildItem(c, i),
    );
  }

  Widget _buildItem(AtlasColors c, int i) {
    final it = _items[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: it.answer == null ? c.border : c.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 8),
                child: Text(
                  '${i + 1}.',
                  style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: it.question,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Question (optional)', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var ch = 0; ch < widget.numChoices; ch++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(_letters[ch]),
                    selected: it.answer == _letters[ch],
                    visualDensity: VisualDensity.compact,
                    onSelected: (sel) => setState(() => it.answer = sel ? _letters[ch] : null),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: it.choices[ch],
                      decoration: InputDecoration(
                        hintText: 'Choice ${_letters[ch]} (optional)',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  it.answer == null
                      ? 'Tap a letter to set the answer'
                      : isBonusKey(it.answer)
                          ? 'Bonus — every paper gets this point'
                          : 'Answer: ${it.answer}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: it.answer == null ? c.textSecondary : c.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              BonusKeyChip(
                selected: isBonusKey(it.answer),
                onTap: () => setState(
                  () => it.answer = isBonusKey(it.answer) ? null : bonusKey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
