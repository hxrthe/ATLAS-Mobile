import 'package:flutter/material.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/atlas_alerts.dart';
import '../grading/course_exam_parser.dart';
import '../grading/grading_repository.dart';

/// Create a major exam for a course by pasting questions and/or the answer key.
///
/// Saved to the web's assessment + bubble sheet tables; the screen then pops
/// the new assessment ID. Quizzes are made from the Quick Exam page instead.
class CourseExamCreateScreen extends StatefulWidget {
  final String courseId;
  final String courseCode;
  final String courseTitle;

  const CourseExamCreateScreen({
    super.key,
    required this.courseId,
    required this.courseCode,
    required this.courseTitle,
  });

  @override
  State<CourseExamCreateScreen> createState() => _CourseExamCreateScreenState();
}

class _CourseExamCreateScreenState extends State<CourseExamCreateScreen> {
  static const int maxItems = 100;

  final _repo = GradingRepository();
  final _title = TextEditingController();
  final _questions = TextEditingController();
  final _key = TextEditingController();
  final _passing = TextEditingController(text: '50');

  int? _choicesOverride;
  int _idColumns = 8;

  List<ParsedExamItem> _items = [];
  final Map<int, String> _answerOverrides = {};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _questions.dispose();
    _key.dispose();
    _passing.dispose();
    super.dispose();
  }

  int get _detectedChoices {
    var most = 0;
    for (final it in _items) {
      if (it.choices.length > most) most = it.choices.length;
      final a = it.answer;
      if (a != null) {
        final need = examLetters.indexOf(a) + 1;
        if (need > most) most = need;
      }
    }
    return most.clamp(2, 4);
  }

  int get _numChoices => _choicesOverride ?? _detectedChoices;

  String? _answerFor(int index) => _answerOverrides[index] ?? _items[index].answer;

  void _reparse() {
    final parsed = parseExamQuestions(_questions.text);
    final keyText = _key.text.trim();
    final key = keyText.isEmpty ? const <int, String>{} : parseAnswerKey(keyText);
    if (parsed.isEmpty && key.isNotEmpty) {
      final count = key.keys.reduce((a, b) => a > b ? a : b);
      for (var n = 1; n <= count; n++) {
        parsed.add(ParsedExamItem(answer: key[n]));
      }
    } else {
      key.forEach((n, letter) {
        if (n >= 1 && n <= parsed.length) parsed[n - 1].answer = letter;
      });
    }
    setState(() {
      if (parsed.length != _items.length) _answerOverrides.clear();
      _items = parsed;
    });
  }

  List<String> get _problems {
    final out = <String>[];
    if (_items.isEmpty) return out;
    if (_items.length > maxItems) {
      out.add('${_items.length} items found — a bubble sheet holds at most $maxItems.');
    }
    final allowed = examLetters.substring(0, _numChoices);
    final missing = <int>[];
    final outside = <int>[];
    for (var i = 0; i < _items.length; i++) {
      final a = _answerFor(i);
      if (a == null) {
        missing.add(i + 1);
      } else if (!allowed.contains(a)) {
        outside.add(i + 1);
      }
      if (_items[i].choices.length > _numChoices && !outside.contains(i + 1)) {
        outside.add(i + 1);
      }
    }
    String list(List<int> l) =>
        l.length > 8 ? '${l.take(8).join(', ')}… (${l.length})' : l.join(', ');
    if (missing.isNotEmpty) out.add('No answer for item ${list(missing)}.');
    if (outside.isNotEmpty) {
      out.add('Item ${list(outside)} uses choices beyond ${allowed[allowed.length - 1]}.');
    }
    return out;
  }

  bool get _canCreate =>
      _title.text.trim().isNotEmpty &&
      _items.isNotEmpty &&
      _problems.isEmpty &&
      _passingValue != null;

  double? get _passingValue {
    final v = double.tryParse(_passing.text.trim());
    return v == null || v < 0 || v > 100 ? null : v;
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _saving = true);
    try {
      await _createMajorExam();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AtlasAlerts.showError(
        context,
        friendlyError(e, fallback: 'Could not create the exam.'),
      );
    }
  }

  Future<void> _createMajorExam() async {
    final res = await _repo.createCourseExam({
      'course_id': widget.courseId,
      'title': _title.text.trim(),
      'exam_type': 'Major Examination',
      'num_choices': _numChoices,
      'num_id_columns': _idColumns,
      'passing_score': _passingValue,
      'items': [
        for (var i = 0; i < _items.length; i++)
          {..._items[i].toJson(), 'correct_answer': _answerFor(i)},
      ],
    });
    if (!mounted) return;
    AtlasAlerts.showSuccess(
      context,
      'Exam created. Download its answer sheet with the download button.',
    );
    Navigator.pop(context, res.assessmentId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New major exam · ${widget.courseCode}')),
      body: _buildForm(),
      bottomNavigationBar: _buildCreateBar(),
    );
  }

  Widget _label(String text, {Widget? trailing}) {
    final c = context.atlas;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: c.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildForm() {
    final c = context.atlas;
    final problems = _problems;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        _label('Exam'),
        TextField(
          controller: _title,
          maxLength: 150,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Exam title',
            hintText: 'e.g. Midterm Exam — Data Structures',
            counterText: '',
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.school_outlined, size: 16, color: c.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Major exam — saved to ${widget.courseCode}\'s evaluation materials '
                'and also shown on ATLAS web. For mobile-only exams, use New Exams on Home.',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _label(
          'Questions',
          trailing: TextButton(
            onPressed: _showFormatHelp,
            child: const Text('Format tips'),
          ),
        ),
        TextField(
          controller: _questions,
          minLines: 8,
          maxLines: 16,
          onChanged: (_) => _reparse(),
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            hintText: '1. What is 2 + 2?\nA. 3\nB. 4\nC. 5\nD. 6\nAnswer: B\n\n'
                '2. Next question…',
          ),
        ),
        const SizedBox(height: 14),
        _label('Answer key (optional)'),
        TextField(
          controller: _key,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _reparse(),
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            hintText: '1.B 2.A 3.D …  or  BADC…\n'
                'Paste only the key to make a key-only exam.',
          ),
        ),
        const SizedBox(height: 24),
        _label('Answer sheet'),
        _segment(
          title: 'Choices per item${_choicesOverride == null && _items.isNotEmpty ? ' (detected)' : ''}',
          values: const [2, 3, 4],
          label: (v) => 'A–${examLetters[v - 1]}',
          selected: _numChoices,
          onChanged: (v) => setState(() => _choicesOverride = v),
        ),
        const SizedBox(height: 14),
        _segment(
          title: 'Student ID digits',
          values: const [4, 5, 6, 7, 8],
          label: (v) => '$v',
          selected: _idColumns,
          onChanged: (v) => setState(() => _idColumns = v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passing,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Passing score',
            suffixText: '%',
            errorText: _passingValue == null ? 'Enter 0 to 100' : null,
          ),
        ),
        const SizedBox(height: 24),
        _label(
          'Preview',
          trailing: Text(
            _items.isEmpty ? '' : '${_items.length} item(s)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _items.length > maxItems ? c.fail : c.primary,
            ),
          ),
        ),
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Paste questions or an answer key to see the items here.',
              style: TextStyle(color: c.textSecondary),
            ),
          ),
        for (final p in problems)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: c.ambiguous),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(p, style: TextStyle(fontSize: 12.5, color: c.textPrimary)),
                ),
              ],
            ),
          ),
        if (problems.isNotEmpty) const SizedBox(height: 6),
        for (var i = 0; i < _items.length && i < maxItems + 5; i++) _buildItemCard(i),
      ],
    );
  }

  Widget _segment({
    required String title,
    required List<int> values,
    required String Function(int) label,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
    final c = context.atlas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: [
              for (final v in values) ButtonSegment(value: v, label: Text(label(v))),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(int i) {
    final c = context.atlas;
    final item = _items[i];
    final answer = _answerFor(i);
    final letters = examLetters.substring(0, _numChoices).split('');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: answer == null ? c.ambiguous : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${i + 1}. ${item.question.trim().isEmpty ? '(key only)' : item.question.trim()}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary),
          ),
          for (var j = 0; j < item.choices.length; j++)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                '${examLetters[j]}. ${item.choices[j]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: examLetters[j] == answer ? FontWeight.w800 : FontWeight.w400,
                  color: examLetters[j] == answer ? c.correct : c.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Answer', style: TextStyle(fontSize: 12, color: c.textSecondary)),
              const SizedBox(width: 10),
              for (final l in letters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _answerOverrides[i] = l),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: answer == l ? c.primary : Colors.transparent,
                        border: Border.all(color: answer == l ? c.primary : c.border, width: 1.5),
                      ),
                      child: Text(
                        l,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: answer == l ? c.onPrimary : c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreateBar() {
    final c = context.atlas;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving || !_canCreate ? null : _create,
            child: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: c.onPrimary),
                  )
                : Text(
                    'Create ${_items.isEmpty ? '' : '${_items.length}-item '}'
                    'major exam',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ),
    );
  }

  void _showFormatHelp() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.atlas;
        TextStyle mono() => TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: c.textPrimary);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pasting questions',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary)),
                const SizedBox(height: 10),
                Text('Number each question, list choices A–D, and mark the answer:',
                    style: TextStyle(color: c.textSecondary)),
                const SizedBox(height: 8),
                Text('1. Capital of France?\nA. Rome\nB. Paris\nC. Madrid\nD. Berlin\nAnswer: B', style: mono()),
                const SizedBox(height: 12),
                Text('Also accepted:', style: TextStyle(color: c.textSecondary)),
                const SizedBox(height: 6),
                Text('• choices on one line:  A. Rome  B. Paris  C. Madrid\n'
                    '• a * on the right choice:  *B. Paris\n'
                    '• answers in the key box:  1.B 2.C 3.A  or  BCA…\n'
                    '• key only (no questions): just fill the key box',
                    style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.5)),
                const SizedBox(height: 12),
                Text('Up to $maxItems items per sheet. Tap a letter in the preview to fix any answer.',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
              ],
            ),
          ),
        );
      },
    );
  }
}
