import '../quick_exam/quick_exam_models.dart';
import 'models.dart';

/// Distinguishes curriculum/web bubble exams from mobile Major Exams (quick API).
enum ExamSource { course, major }

/// Tagged id used in dropdowns/filters so both sources can share one list.
String majorExamFilterId(String examId) => 'qx:$examId';

bool isMajorExamFilterId(String? id) =>
    id != null && id.startsWith('qx:') && id.length > 3;

String? majorExamIdFromFilter(String? id) =>
    isMajorExamFilterId(id) ? id!.substring(3) : null;

/// Whether a quick/major subject label belongs to this course.
bool majorExamMatchesCourse(
  QuickExam exam, {
  required String courseCode,
  required String courseTitle,
}) {
  final name = exam.subjectName.trim().toLowerCase();
  final code = courseCode.trim().toLowerCase();
  final title = courseTitle.trim().toLowerCase();
  if (code.isEmpty) return false;
  if (name == code || name.startsWith('$code ') || name.startsWith('$code–') ||
      name.startsWith('$code-') || name.startsWith('$code –')) {
    return true;
  }
  if (title.isNotEmpty && name.contains(title)) return true;
  return name.contains(code);
}

/// One row for hub / pending / filter lists.
class UnifiedExamRef {
  final ExamSource source;
  final String id;
  final String title;
  final String subjectLabel;
  final String? courseId;
  final bool hasAnswerKey;
  final int totalItems;
  final int scanCount;
  final BubbleTemplate? template;
  final QuickExam? majorExam;

  const UnifiedExamRef({
    required this.source,
    required this.id,
    required this.title,
    required this.subjectLabel,
    this.courseId,
    this.hasAnswerKey = false,
    this.totalItems = 0,
    this.scanCount = 0,
    this.template,
    this.majorExam,
  });

  bool get isMajor => source == ExamSource.major;

  factory UnifiedExamRef.fromTemplate(BubbleTemplate t) => UnifiedExamRef(
        source: ExamSource.course,
        id: t.assessmentId ?? t.templateId,
        title: t.name,
        subjectLabel: t.courseId,
        courseId: t.courseId.isEmpty ? null : t.courseId,
        hasAnswerKey: t.hasAnswerKey || t.answerKey.isNotEmpty,
        totalItems: t.totalItems,
        template: t,
      );

  factory UnifiedExamRef.fromMajor(QuickExam e) => UnifiedExamRef(
        source: ExamSource.major,
        id: majorExamFilterId(e.examId),
        title: e.name,
        subjectLabel: e.subjectName,
        hasAnswerKey: e.hasAnyKey,
        totalItems: e.totalItems,
        scanCount: e.scanCount,
        majorExam: e,
      );
}
