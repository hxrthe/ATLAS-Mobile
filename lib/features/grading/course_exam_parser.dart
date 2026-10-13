/// Turns pasted exam text into items for `POST grading/course-exams/`.
///
/// Questions may be numbered (`1.` / `1)`) or separated by their choices;
/// choices may sit on their own lines or inline (`A. x  B. y`). Answers come
/// from `Answer: B` lines, a `*` on the right choice, or a separate key.
library;

const String examLetters = 'ABCD';

class ParsedExamItem {
  String question;
  final List<String> choices;
  String? answer;

  ParsedExamItem({this.question = '', List<String>? choices, this.answer})
      : choices = choices ?? [];

  Map<String, dynamic> toJson() => {
        'question_text': question.trim(),
        'choices': choices.map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
        'correct_answer': answer,
      };
}

final RegExp _questionStart = RegExp(r'^\s*(?:Q\s*)?(\d{1,3})\s*[\.\):]\s*(.*)$', caseSensitive: false);
final RegExp _choiceLine = RegExp(r'^\s*(\*)?\s*\(?([A-Da-d])[\.\)]\s*(.*)$');
final RegExp _inlineChoice = RegExp(r'(?:^|\s)(\*)?\(?([A-D])[\.\)]\s+');
final RegExp _answerLine = RegExp(
  r'^\s*(?:correct\s+answer|answer\s+key|answer|ans|key)\s*[:\-=]?\s*\(?([A-Da-d])\b',
  caseSensitive: false,
);
final RegExp _correctMark = RegExp(r'\s*(?:\*|\(correct\)|✓|✔)\s*$', caseSensitive: false);

/// Splits `A. x B. y C. z` into choices when a line holds two or more that
/// start with A. With [allowPrefix], text before the first choice is allowed
/// and returned through [prefixOut].
List<({String letter, String text, bool marked})>? _splitInline(
  String line, {
  bool allowPrefix = false,
  List<String>? prefixOut,
}) {
  final matches = _inlineChoice.allMatches(line).toList();
  if (matches.length < 2 || matches.first.group(2) != 'A') return null;
  if (!allowPrefix && matches.first.start > 1) return null;
  prefixOut?.add(line.substring(0, matches.first.start).trim());
  final out = <({String letter, String text, bool marked})>[];
  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final end = i + 1 < matches.length ? matches[i + 1].start : line.length;
    var text = line.substring(m.end, end).trim();
    var marked = m.group(1) != null;
    if (_correctMark.hasMatch(text)) {
      marked = true;
      text = text.replaceFirst(_correctMark, '');
    }
    out.add((letter: m.group(2)!, text: text, marked: marked));
  }
  return out;
}

List<ParsedExamItem> parseExamQuestions(String raw) {
  final items = <ParsedExamItem>[];
  ParsedExamItem? current;
  var inChoices = false;

  void addChoice(String letter, String text, bool marked) {
    final item = current!;
    if (_correctMark.hasMatch(text)) {
      marked = true;
      text = text.replaceFirst(_correctMark, '');
    }
    item.choices.add(text.trim());
    if (marked) item.answer = letter.toUpperCase();
    inChoices = true;
  }

  for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) continue;

    final ans = _answerLine.firstMatch(line);
    if (ans != null && current != null) {
      current.answer = ans.group(1)!.toUpperCase();
      inChoices = true;
      continue;
    }

    final q = _questionStart.firstMatch(line);
    if (q != null) {
      current = ParsedExamItem(question: q.group(2)!.trim());
      items.add(current);
      inChoices = false;
      final prefix = <String>[];
      final inline = _splitInline(current.question, allowPrefix: true, prefixOut: prefix);
      if (inline != null) {
        current.question = prefix.first;
        for (final c in inline) {
          addChoice(c.letter, c.text, c.marked);
        }
      }
      continue;
    }

    if (current != null) {
      final inline = _splitInline(line.trim());
      if (inline != null) {
        for (final c in inline) {
          addChoice(c.letter, c.text, c.marked);
        }
        continue;
      }
      final choice = _choiceLine.firstMatch(line);
      final expected = current.choices.length < examLetters.length
          ? examLetters[current.choices.length]
          : null;
      if (choice != null &&
          choice.group(2)!.toUpperCase() == expected) {
        addChoice(choice.group(2)!, choice.group(3)!, choice.group(1) != null);
        continue;
      }
    }

    // Plain text: continues the question, or starts an unnumbered one once
    // the previous item's choices are done.
    if (current == null || inChoices) {
      current = ParsedExamItem(question: line.trim());
      items.add(current);
      inChoices = false;
    } else {
      current.question = current.question.isEmpty
          ? line.trim()
          : '${current.question} ${line.trim()}';
    }
  }
  return items;
}

/// `"1.B 2-c 3) A"` or `"BCDA…"` (use `-`/`_`/`?` to skip) → `{1: 'B', …}`.
Map<int, String> parseAnswerKey(String raw, {int? maxItems}) {
  final text = raw.toUpperCase();
  final out = <int, String>{};
  final numbered = RegExp(r'(\d{1,3})\s*[\.\)\-:=]?\s*([A-D])\b').allMatches(text).toList();
  if (numbered.isNotEmpty) {
    for (final m in numbered) {
      final n = int.parse(m.group(1)!);
      if (n >= 1 && (maxItems == null || n <= maxItems)) out[n] = m.group(2)!;
    }
    return out;
  }
  var i = 1;
  for (final ch in text.split('')) {
    if (maxItems != null && i > maxItems) break;
    if (ch == '-' || ch == '_' || ch == '?') {
      i++;
    } else if (examLetters.contains(ch)) {
      out[i++] = ch;
    }
  }
  return out;
}
