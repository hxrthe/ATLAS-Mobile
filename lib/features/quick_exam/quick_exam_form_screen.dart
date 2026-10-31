import 'package:flutter/material.dart';

import '../../core/network/error_messages.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/atlas_skeleton.dart';
import '../../utils/atlas_alerts.dart';
import '../grading/answer_key.dart';
import 'quick_exam_models.dart';
import 'quick_exam_repository.dart';
import 'quick_exam_widgets.dart';
import 'quick_questions_editor_screen.dart';
import 'quick_sheet.dart';

class _PartDraft {
  final TextEditingController label;
  int endItem;

  _PartDraft(String text, this.endItem)
      : label = TextEditingController(text: text);
}

/// Create a quick exam, or edit one when [exam] is given. Pops the saved exam.
class QuickExamFormScreen extends StatefulWidget {
  final QuickExam? exam;
  final String? initialSubjectId;
  final String? initialCourseId;

  const QuickExamFormScreen({
    super.key,
    this.exam,
    this.initialSubjectId,
    this.initialCourseId,
  });

  @override
  State<QuickExamFormScreen> createState() => _QuickExamFormScreenState();
}

class _QuickExamFormScreenState extends State<QuickExamFormScreen> {
  static const _presets = [50, 60, 70, 80, 90, 100];
  static const _romans = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

  final _repo = QuickExamRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _items;
  late final TextEditingController _passing;

  static const _legacyPrefix = 'subject:';

  List<QuickCourseOption> _courses = [];
  /// A course id, or `subject:<id>` for an older exam whose subject isn't one
  /// of the assigned courses.
  String? _subjectChoice;
  bool _loadingSubjects = true;
  bool _saving = false;

  /// Questions + key from the editor; null until the editor is used.
  QuickQuestionsResult? _content;
  bool _openingEditor = false;

  late int _total;
  late int _choices;
  late int _idColumns;
  late bool _compact;
  final List<_PartDraft> _parts = [];

  bool get _isEdit => widget.exam != null;
  bool get _structureLocked => (widget.exam?.scanCount ?? 0) > 0;
  bool get _useCompact => _compact && QuickSheet.fitsCompact(_total);

  @override
  void initState() {
    super.initState();
    final e = widget.exam;
    _name = TextEditingController(text: e?.name ?? '');
    _total = e?.totalItems ?? 50;
    _choices = e?.numChoices ?? 4;
    _idColumns = e?.numIdColumns ?? 8;
    _compact = e?.isCompact ?? false;
    _items = TextEditingController(text: '$_total');
    _passing = TextEditingController(
      text: e == null ? '50' : formatPercent(e.passingPercent).replaceAll('%', ''),
    );
    if (e != null && e.parts.isNotEmpty) {
      for (final p in e.parts) {
        _parts.add(_PartDraft(p.label, p.endItem));
      }
    } else {
      _parts.add(_PartDraft('Part I', _total));
    }
    _normalizeParts();
    _loadSubjects();
  }

  @override
  void dispose() {
    _name.dispose();
    _items.dispose();
    _passing.dispose();
    for (final p in _parts) {
      p.label.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final courses = await _repo.fetchCourseOptions();
      if (!mounted) return;
      final wantedSubject = widget.exam?.subjectId ?? widget.initialSubjectId;
      final match = courses.where(
        (c) =>
            (widget.exam == null && c.courseId == widget.initialCourseId) ||
            (wantedSubject != null && c.subjectId == wantedSubject),
      );
      setState(() {
        _courses = courses;
        _loadingSubjects = false;
        if (match.isNotEmpty) {
          _subjectChoice = match.first.courseId;
        } else if (widget.exam != null) {
          _subjectChoice = '$_legacyPrefix${widget.exam!.subjectId}';
        } else if (courses.isNotEmpty) {
          _subjectChoice = courses.first.courseId;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSubjects = false);
      AtlasAlerts.showError(
        context,
        friendlyError(e, fallback: 'Could not load your subjects.'),
      );
    }
  }

  void _setTotal(int value) {
    final v = value.clamp(QuickSheet.minItems, QuickSheet.maxItems);
    setState(() {
      _total = v;
      if (_items.text != '$v') _items.text = '$v';
      _normalizeParts();
    });
  }

  /// Keeps parts contiguous, non-empty and ending exactly at [_total].
  void _normalizeParts() {
    while (_parts.length > _total) {
      _parts.removeLast().label.dispose();
    }
    var start = 1;
    for (var i = 0; i < _parts.length; i++) {
      final remaining = _parts.length - i - 1;
      final maxEnd = _total - remaining;
      final p = _parts[i];
      p.endItem = i == _parts.length - 1
          ? _total
          : p.endItem.clamp(start, maxEnd);
      start = p.endItem + 1;
    }
  }

  int _partStart(int index) => index == 0 ? 1 : _parts[index - 1].endItem + 1;

  void _addPart() {
    if (_parts.length >= _romans.length || _parts.length >= _total) return;
    setState(() {
      final last = _parts.last;
      final start = _partStart(_parts.length - 1);
      final span = last.endItem - start + 1;
      if (span < 2) return;
      last.endItem = start + span ~/ 2 - 1;
      _parts.add(_PartDraft('Part ${_romans[_parts.length]}', _total));
      _normalizeParts();
    });
  }

  void _removePart(int index) {
    if (_parts.length <= 1) return;
    setState(() {
      _parts.removeAt(index).label.dispose();
      _normalizeParts();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final typed = int.tryParse(_items.text.trim());
    if (!_structureLocked && (typed == null || typed < QuickSheet.minItems)) {
      _items.text = '$_total';
      AtlasAlerts.showError(
        context,
        'Exams need at least ${QuickSheet.minItems} items.',
      );
      return;
    }
    final choice = _subjectChoice;
    if (choice == null) {
      AtlasAlerts.showError(context, 'Choose one of your assigned courses.');
      return;
    }
    final legacySubject = choice.startsWith(_legacyPrefix)
        ? choice.substring(_legacyPrefix.length)
        : null;
    final passing = double.parse(_passing.text.trim());
    final e = widget.exam;
    final structureChanged = e == null ||
        e.totalItems != _total ||
        e.numChoices != _choices ||
        e.numIdColumns != _idColumns ||
        e.isCompact != _useCompact;

    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'subject_id': ?legacySubject,
      if (legacySubject == null) 'course_id': choice,
      'passing_score': passing,
      'parts': [
        for (var i = 0; i < _parts.length; i++)
          {
            'label': _parts[i].label.text.trim().isEmpty
                ? 'Part ${_romans[i]}'
                : _parts[i].label.text.trim(),
            'start_item': _partStart(i),
            'end_item': _parts[i].endItem,
          },
      ],
      if (structureChanged) ...{
        'total_items': _total,
        'num_choices': _choices,
        'num_id_columns': _idColumns,
        'layout_metadata': QuickSheet.layout(
          totalItems: _total,
          numChoices: _choices,
          idColumns: _idColumns,
          compact: _useCompact,
        ),
      },
    };

    final content = _content;
    final allowed = 'ABCD'.substring(0, _choices);
    final key = <String, String>{
      for (final entry in (content?.answerKey ?? const <String, String>{}).entries)
        if ((int.tryParse(entry.key) ?? 0) <= _total &&
            (allowed.contains(entry.value.toUpperCase()) ||
                entry.value.trim() == bonusKey))
          entry.key: entry.value.trim().toUpperCase(),
    };
    if (content != null) body['questions'] = _fittedQuestions(content);

    setState(() => _saving = true);
    try {
      var saved = await _repo.saveExam(body, examId: e?.examId);
      if (content != null && key.isNotEmpty) {
        saved = await _repo.saveAnswerKey(saved.examId, key);
      }
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (err) {
      if (!mounted) return;
      setState(() => _saving = false);
      AtlasAlerts.showError(
        context,
        friendlyError(err, fallback: 'Could not save the exam.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.atlas;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit major exam' : 'New major exam'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const QuickSectionLabel('Exam'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Exam name',
                hintText: 'e.g. Quiz 3 — Stoichiometry',
                counterText: '',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter an exam name.' : null,
            ),
            const SizedBox(height: 14),
            _buildSubjectPicker(c),
            const SizedBox(height: 24),
            QuickSectionLabel(
              'Answer sheet',
              trailing: _structureLocked
                  ? Text(
                      'Locked — has scans',
                      style: TextStyle(fontSize: 11, color: c.ambiguous),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            _buildItemsCard(c),
            const SizedBox(height: 14),
            _buildSegment(
              c,
              title: 'Choices per item',
              values: const [2, 3, 4],
              label: (v) => 'A–${'ABCD'[v - 1]}',
              selected: _choices,
              onChanged: (v) => setState(() => _choices = v),
            ),
            const SizedBox(height: 14),
            _buildSegment(
              c,
              title: 'Student ID digits',
              values: const [4, 5, 6, 7, 8],
              label: (v) => '$v',
              selected: _idColumns,
              onChanged: (v) => setState(() => _idColumns = v),
            ),
            if (QuickSheet.fitsCompact(_total)) ...[
              const SizedBox(height: 8),
              HalfPageSheetSwitch(
                value: _useCompact,
                totalItems: _total,
                locked: _structureLocked,
                onChanged: (v) => setState(() => _compact = v),
              ),
            ],
            const SizedBox(height: 16),
            QuickSectionLabel(
              'Parts',
              trailing: TextButton.icon(
                onPressed: _parts.length < _romans.length &&
                        _parts.last.endItem - _partStart(_parts.length - 1) >= 1
                    ? _addPart
                    : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add part'),
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _parts.length; i++) _buildPartRow(c, i),
            const SizedBox(height: 24),
            const QuickSectionLabel('Questions & answer key'),
            const SizedBox(height: 10),
            _buildContentCard(c),
            const SizedBox(height: 24),
            const QuickSectionLabel('Grading'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _passing,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Passing score',
                suffixText: '%',
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n < 0 || n > 100) return 'Enter 0 to 100.';
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
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
                        _isEdit ? 'Save changes' : 'Create exam',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectPicker(AtlasColors c) {
    if (_loadingSubjects) {
      return const AtlasShimmer(child: SkeletonBox(height: 58, radius: 12));
    }
    final legacy = _subjectChoice?.startsWith(_legacyPrefix) == true;
    if (_courses.isEmpty && !legacy) {
      return Text(
        'You have no assigned courses yet. Exams can only be created for '
        'courses assigned to you.',
        style: TextStyle(fontSize: 13, color: c.textSecondary),
      );
    }
    final items = <DropdownMenuItem<String>>[
      for (final course in _courses)
        DropdownMenuItem(
          value: course.courseId,
          child: Text(course.name, overflow: TextOverflow.ellipsis),
        ),
      if (legacy)
        DropdownMenuItem(
          value: _subjectChoice,
          child: Text(widget.exam!.subjectName, overflow: TextOverflow.ellipsis),
        ),
    ];
    return DropdownButtonFormField<String>(
      key: ValueKey('subject-${_courses.length}'),
      initialValue: _subjectChoice,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Subject (assigned course)'),
      hint: const Text('Choose a course'),
      items: items,
      onChanged: (v) => setState(() => _subjectChoice = v),
    );
  }

  /// Editor questions resized to the current item and choice counts.
  List<Map<String, dynamic>>? _fittedQuestions(QuickQuestionsResult content) {
    final qs = content.questions;
    if (qs == null) return null;
    final out = [
      for (var i = 0; i < _total; i++)
        {
          'question_text': i < qs.length ? qs[i]['question_text'] : '',
          'choices': i < qs.length
              ? (qs[i]['choices'] as List).cast<String>().take(_choices).toList()
              : <String>[],
        },
    ];
    final any = out.any(
      (q) =>
          (q['question_text'] as String).trim().isNotEmpty ||
          (q['choices'] as List<String>).any((c) => c.trim().isNotEmpty),
    );
    return any ? out : null;
  }

  Future<void> _openEditor() async {
    if (_openingEditor) return;
    var questions = <QuickQuestion>[];
    var key = <String, String>{};
    final content = _content;
    if (content != null) {
      final qs = content.questions ?? const [];
      questions = [
        for (var i = 0; i < qs.length; i++)
          QuickQuestion(
            itemNumber: i + 1,
            text: qs[i]['question_text'] as String,
            choices: (qs[i]['choices'] as List).cast<String>(),
          ),
      ];
      key = content.answerKey;
    } else if (widget.exam != null) {
      var exam = widget.exam!;
      final partial = (exam.hasQuestions && exam.questions.isEmpty) ||
          (exam.hasAnyKey && exam.answerKey.isEmpty);
      if (partial) {
        setState(() => _openingEditor = true);
        try {
          exam = await _repo.fetchExam(exam.examId);
        } catch (err) {
          if (!mounted) return;
          setState(() => _openingEditor = false);
          AtlasAlerts.showError(
            context,
            friendlyError(err, fallback: 'Could not load the questions.'),
          );
          return;
        }
        if (!mounted) return;
        setState(() => _openingEditor = false);
      }
      questions = exam.questions;
      key = exam.answerKey;
    }
    final result = await Navigator.push<QuickQuestionsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => QuickQuestionsEditorScreen(
          totalItems: _total,
          numChoices: _choices,
          initialQuestions: questions,
          initialKey: key,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _content = result);
  }

  Widget _buildContentCard(AtlasColors c) {
    final content = _content;
    final e = widget.exam;
    final String summary;
    if (content != null) {
      summary = '${content.questionCount} question${content.questionCount == 1 ? '' : 's'} · '
          '${content.answerKey.length}/$_total answers';
    } else if (e != null && (e.hasQuestions || e.hasAnyKey)) {
      summary = '${e.hasQuestions ? 'Questions saved' : 'No questions'} · '
          '${e.keyedItems}/${e.totalItems} answers';
    } else {
      summary = 'Optional — paste them or type them in. You can also add the key later.';
    }
    final hasAny = content != null || (e != null && (e.hasQuestions || e.hasAnyKey));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.list_alt_outlined, color: c.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(summary, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ),
          const SizedBox(width: 8),
          _openingEditor
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _openEditor,
                  child: Text(hasAny ? 'Edit' : 'Add'),
                ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(AtlasColors c) {
    final locked = _structureLocked;
    final cols = QuickSheet.columnsFor(_total);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Number of items',
                style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary),
              ),
              const Spacer(),
              IconButton(
                onPressed: locked || _total <= QuickSheet.minItems
                    ? null
                    : () => _setTotal(_total - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 56,
                child: TextField(
                  controller: _items,
                  enabled: !locked,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n >= QuickSheet.minItems) _setTotal(n);
                  },
                ),
              ),
              IconButton(
                onPressed: locked || _total >= QuickSheet.maxItems
                    ? null
                    : () => _setTotal(_total + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          Slider(
            value: _total.clamp(QuickSheet.minItems, QuickSheet.maxItems).toDouble(),
            min: QuickSheet.minItems.toDouble(),
            max: QuickSheet.maxItems.toDouble(),
            divisions: QuickSheet.maxItems - QuickSheet.minItems,
            label: '$_total',
            onChanged: locked ? null : (v) => _setTotal(v.round()),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  label: Text('$p'),
                  selected: _total == p,
                  onSelected: locked ? null : (_) => _setTotal(p),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${QuickSheet.minItems}–${QuickSheet.maxItems} items · Long bond sheet · $cols answer columns'
            '${cols == 3 ? ' (compact layout above ${QuickSheet.twoColumnMaxItems} items)' : ''}',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(
    AtlasColors c, {
    required String title,
    required List<int> values,
    required String Function(int) label,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: [
              for (final v in values)
                ButtonSegment(value: v, label: Text(label(v))),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: _structureLocked ? null : (s) => onChanged(s.first),
          ),
        ),
      ],
    );
  }

  Widget _buildPartRow(AtlasColors c, int i) {
    final p = _parts[i];
    final start = _partStart(i);
    final isLast = i == _parts.length - 1;
    final maxEnd = _total - (_parts.length - i - 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: p.label,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Label',
                hintText: 'Part ${_romans[i]}',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: isLast
                ? InputDecorator(
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Items',
                    ),
                    child: Text('$start – ${p.endItem}'),
                  )
                : DropdownButtonFormField<int>(
                    key: ValueKey('part-$i-$start-${p.endItem}-$maxEnd'),
                    initialValue: p.endItem,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Items',
                    ),
                    items: [
                      for (var e = start; e <= maxEnd; e++)
                        DropdownMenuItem(value: e, child: Text('$start – $e')),
                    ],
                    onChanged: (v) => setState(() {
                      if (v == null) return;
                      p.endItem = v;
                      _normalizeParts();
                    }),
                  ),
          ),
          IconButton(
            onPressed: _parts.length > 1 ? () => _removePart(i) : null,
            icon: Icon(Icons.close, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
