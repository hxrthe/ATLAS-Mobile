import '../grading/models.dart';

/// QR payload prefix printed on quick-exam sheets (`QX:<exam_id>`).
const String quickExamQrPrefix = 'QX:';

String? quickExamIdFromQr(String? qr) {
  final raw = (qr ?? '').trim();
  if (!raw.toUpperCase().startsWith(quickExamQrPrefix)) return null;
  final id = raw.substring(quickExamQrPrefix.length).trim();
  return id.isEmpty ? null : id;
}

double? _toDouble(dynamic v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

class QuickSubject {
  final String subjectId;
  final String name;
  final int examCount;

  const QuickSubject({
    required this.subjectId,
    required this.name,
    this.examCount = 0,
  });

  factory QuickSubject.fromJson(Map<String, dynamic> j) => QuickSubject(
        subjectId: (j['subject_id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        examCount: (j['exam_count'] as num?)?.toInt() ?? 0,
      );
}

/// One of the faculty's assigned courses, offered as a quick-exam subject.
class QuickCourseOption {
  final String courseId;
  final String name;
  final String? subjectId;

  const QuickCourseOption({
    required this.courseId,
    required this.name,
    this.subjectId,
  });

  factory QuickCourseOption.fromJson(Map<String, dynamic> j) => QuickCourseOption(
        courseId: (j['course_id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        subjectId: j['subject_id']?.toString(),
      );
}

/// A pasted question for one item; quick exams without pasted questions have none.
class QuickQuestion {
  final int itemNumber;
  final String text;
  final List<String> choices;

  const QuickQuestion({
    required this.itemNumber,
    required this.text,
    this.choices = const [],
  });

  factory QuickQuestion.fromJson(Map<String, dynamic> j) => QuickQuestion(
        itemNumber: (j['item_number'] as num?)?.toInt() ?? 0,
        text: (j['question_text'] ?? '').toString(),
        choices: (j['choices'] as List<dynamic>? ?? [])
            .map((c) => c.toString())
            .where((c) => c.trim().isNotEmpty)
            .toList(),
      );
}

class QuickExam {
  final String examId;
  final String qrPayload;
  final String subjectId;
  final String subjectName;
  final String name;
  final int totalItems;
  final int numChoices;
  final int numIdColumns;
  final List<BubblePart> parts;
  final double? passingScore;
  final int keyedItems;
  final Map<String, String> answerKey;
  final Map<String, dynamic> layoutMetadata;
  final bool hasQuestions;
  final List<QuickQuestion> questions;
  final int scanCount;
  final double? averagePercent;
  final int flaggedCount;
  final DateTime? createdAt;

  const QuickExam({
    required this.examId,
    required this.qrPayload,
    required this.subjectId,
    required this.subjectName,
    required this.name,
    required this.totalItems,
    required this.numChoices,
    required this.numIdColumns,
    required this.parts,
    this.passingScore,
    this.keyedItems = 0,
    this.answerKey = const {},
    this.layoutMetadata = const {},
    this.hasQuestions = false,
    this.questions = const [],
    this.scanCount = 0,
    this.averagePercent,
    this.flaggedCount = 0,
    this.createdAt,
  });

  bool get hasFullKey => keyedItems >= totalItems;
  bool get hasAnyKey => keyedItems > 0;
  /// Half-page sheet printed two per long-bond page.
  bool get isCompact => layoutMetadata['sheet_style'] == 'compact';
  double get passingPercent => passingScore ?? 50;
  String get choiceRange => 'A–${'ABCD'[numChoices - 1]}';

  factory QuickExam.fromJson(Map<String, dynamic> j) {
    final key = <String, String>{};
    if (j['answer_key'] is Map) {
      (j['answer_key'] as Map).forEach((k, v) {
        key[k.toString()] = v.toString().toUpperCase();
      });
    }
    return QuickExam(
      examId: (j['exam_id'] ?? '').toString(),
      qrPayload: (j['qr_payload'] ?? '$quickExamQrPrefix${j['exam_id']}').toString(),
      subjectId: (j['subject_id'] ?? '').toString(),
      subjectName: (j['subject_name'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      totalItems: (j['total_items'] as num?)?.toInt() ?? 0,
      numChoices: (j['num_choices'] as num?)?.toInt() ?? 4,
      numIdColumns: (j['num_id_columns'] as num?)?.toInt() ?? 8,
      parts: (j['parts'] as List<dynamic>? ?? [])
          .map((p) => BubblePart.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      passingScore: _toDouble(j['passing_score']),
      keyedItems: (j['keyed_items'] as num?)?.toInt() ?? key.length,
      answerKey: key,
      layoutMetadata: j['layout_metadata'] is Map
          ? Map<String, dynamic>.from(j['layout_metadata'] as Map)
          : const {},
      hasQuestions: j['has_questions'] == true || j['questions'] is List,
      questions: (j['questions'] as List<dynamic>? ?? [])
          .map((q) => QuickQuestion.fromJson(Map<String, dynamic>.from(q as Map)))
          .toList(),
      scanCount: (j['scan_count'] as num?)?.toInt() ?? 0,
      averagePercent: _toDouble(j['average_percent']),
      flaggedCount: (j['flagged_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
    );
  }

  /// Scanner-facing template. `courseId` stays empty: quick exams belong to no course.
  BubbleTemplate toTemplate() => BubbleTemplate(
        templateId: examId,
        courseId: '',
        name: name,
        totalItems: totalItems,
        numChoices: numChoices,
        parts: parts,
        hasEssay: false,
        essayLines: 0,
        hasAnswerKey: answerKey.isNotEmpty,
        answerKey: answerKey,
        passingScore: passingPercent,
        layoutMetadata: layoutMetadata,
        isQuickExam: true,
      );
}

class QuickScan {
  final String scanId;
  final String examId;
  final String examName;
  final String subjectId;
  final String subjectName;
  final String? studentIdentifier;
  final String? studentName;
  final Map<String, String> responses;
  final double? scoreRaw;
  final double? scorePercent;
  final double? maxScore;
  final bool passed;
  final bool isFlagged;
  final String? flagReason;
  final DateTime? createdAt;

  const QuickScan({
    required this.scanId,
    required this.examId,
    required this.examName,
    required this.subjectId,
    required this.subjectName,
    this.studentIdentifier,
    this.studentName,
    this.responses = const {},
    this.scoreRaw,
    this.scorePercent,
    this.maxScore,
    this.passed = false,
    this.isFlagged = false,
    this.flagReason,
    this.createdAt,
  });

  String get studentLabel =>
      (studentIdentifier ?? '').isNotEmpty ? studentIdentifier! : 'Unknown ID';

  factory QuickScan.fromJson(Map<String, dynamic> j) => QuickScan(
        scanId: (j['scan_id'] ?? '').toString(),
        examId: (j['exam_id'] ?? '').toString(),
        examName: (j['exam_name'] ?? '').toString(),
        subjectId: (j['subject_id'] ?? '').toString(),
        subjectName: (j['subject_name'] ?? '').toString(),
        studentIdentifier: j['student_identifier']?.toString(),
        studentName: j['student_name']?.toString(),
        responses: (j['responses'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const {},
        scoreRaw: _toDouble(j['score_raw']),
        scorePercent: _toDouble(j['score_percent']),
        maxScore: _toDouble(j['max_score']),
        passed: j['passed'] == true,
        isFlagged: j['is_flagged'] == true,
        flagReason: j['flag_reason']?.toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

class QuickItemStat {
  final int item;
  final String? correctAnswer;
  final int correct;
  final int answered;
  final int blank;
  final double? percentCorrect;
  final Map<String, int> choiceCounts;

  const QuickItemStat({
    required this.item,
    this.correctAnswer,
    this.correct = 0,
    this.answered = 0,
    this.blank = 0,
    this.percentCorrect,
    this.choiceCounts = const {},
  });

  factory QuickItemStat.fromJson(Map<String, dynamic> j) => QuickItemStat(
        item: (j['item'] as num?)?.toInt() ?? 0,
        correctAnswer: j['correct_answer']?.toString(),
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        blank: (j['blank'] as num?)?.toInt() ?? 0,
        percentCorrect: _toDouble(j['percent_correct']),
        choiceCounts: (j['choice_counts'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            ) ??
            const {},
      );
}

class QuickExamRecords {
  final int scanCount;
  final double? averagePercent;
  final double? highestPercent;
  final double? lowestPercent;
  final int passedCount;
  final int flaggedCount;
  final List<QuickScan> scans;
  final List<QuickItemStat> items;

  const QuickExamRecords({
    this.scanCount = 0,
    this.averagePercent,
    this.highestPercent,
    this.lowestPercent,
    this.passedCount = 0,
    this.flaggedCount = 0,
    this.scans = const [],
    this.items = const [],
  });

  factory QuickExamRecords.fromJson(Map<String, dynamic> j) {
    final s = Map<String, dynamic>.from(j['summary'] as Map? ?? {});
    return QuickExamRecords(
      scanCount: (s['scan_count'] as num?)?.toInt() ?? 0,
      averagePercent: _toDouble(s['average_percent']),
      highestPercent: _toDouble(s['highest_percent']),
      lowestPercent: _toDouble(s['lowest_percent']),
      passedCount: (s['passed_count'] as num?)?.toInt() ?? 0,
      flaggedCount: (s['flagged_count'] as num?)?.toInt() ?? 0,
      scans: (j['scans'] as List<dynamic>? ?? [])
          .map((e) => QuickScan.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      items: (j['item_analysis'] as List<dynamic>? ?? [])
          .map((e) => QuickItemStat.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
