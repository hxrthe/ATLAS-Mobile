class BubbleTemplate {
  final String templateId;
  final String courseId;
  final String? assessmentId;
  final String name;
  final int totalItems;
  final int numChoices;
  final List<BubblePart> parts;
  final bool hasEssay;
  final int essayLines;
  final bool hasAnswerKey;
  final Map<String, String> answerKey;
  final double? passingScore;
  final Map<String, dynamic> layoutMetadata;

  /// Mobile-only quick exam: saved through the quick-exam API, no course or section.
  final bool isQuickExam;

  BubbleTemplate({
    required this.templateId,
    required this.courseId,
    this.assessmentId,
    required this.name,
    required this.totalItems,
    required this.numChoices,
    required this.parts,
    required this.hasEssay,
    required this.essayLines,
    required this.hasAnswerKey,
    required this.answerKey,
    this.passingScore,
    required this.layoutMetadata,
    this.isQuickExam = false,
  });

  /// Returns true when bubble positions are available for template-based OMR.
  bool get hasLayoutItems {
    final items = layoutMetadata['items'];
    return items is Map && items.isNotEmpty;
  }

  /// Student ID boxes printed on the sheet.
  int get idDigits {
    final explicit = layoutMetadata['num_id_columns'];
    if (explicit is num) return explicit.toInt();
    final cols = layoutMetadata['id_columns'];
    if (cols is Map && cols['num_cols'] is num) return (cols['num_cols'] as num).toInt();
    return 8;
  }

  factory BubbleTemplate.fromJson(Map<String, dynamic> json) {
    return BubbleTemplate(
      templateId: json['template_id'] ?? '',
      courseId: json['course_id'] ?? '',
      assessmentId: json['assessment_id'],
      name: json['name'] ?? '',
      totalItems: json['total_items'] ?? 0,
      numChoices: json['num_choices'] ?? 4,
      parts: (json['parts'] as List<dynamic>?)
              ?.map((p) => BubblePart.fromJson(p))
              .toList() ??
          [],
      hasEssay: json['has_essay'] ?? false,
      essayLines: json['essay_lines'] ?? 10,
      hasAnswerKey: json['has_answer_key'] ?? false,
      answerKey: _parseAnswerKey(json['answer_key']),
      passingScore: (json['passing_score'] as num?)?.toDouble(),
      layoutMetadata: json['layout_metadata'] ?? {},
      isQuickExam: json['is_quick_exam'] == true,
    );
  }

  static Map<String, String> _parseAnswerKey(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final key = k.toString().trim();
      final val = v.toString().trim().toUpperCase();
      if (key.isEmpty || val.isEmpty) return;
      out[key] = val;
      // Also index bare item numbers (strip leading zeros).
      final asInt = int.tryParse(key);
      if (asInt != null) out[asInt.toString()] = val;
    });
    return out;
  }
}

class BubblePart {
  final String label;
  final int startItem;
  final int endItem;

  BubblePart({
    required this.label,
    required this.startItem,
    required this.endItem,
  });

  factory BubblePart.fromJson(Map<String, dynamic> json) {
    return BubblePart(
      label: json['label'] ?? '',
      startItem: json['start_item'] ?? 1,
      endItem: json['end_item'] ?? 1,
    );
  }
}

/// A row of the `blocks` roster: which grade level + section a student ID belongs to.
class StudentBlock {
  final String studentId;
  final String gradeLevel;
  final String? sectionId;
  final String section;

  const StudentBlock({
    required this.studentId,
    required this.gradeLevel,
    this.sectionId,
    required this.section,
  });

  factory StudentBlock.fromJson(Map<String, dynamic> json) {
    return StudentBlock(
      studentId: (json['student_id'] ?? '').toString(),
      gradeLevel: (json['grade_level'] ?? '').toString(),
      sectionId: json['section_id']?.toString(),
      section: (json['section'] ?? '').toString(),
    );
  }
}

/// A row of the `sections` table the faculty can assign students to.
class SectionOption {
  final String sectionId;
  final String name;
  final List<String> courseIds;

  const SectionOption({
    required this.sectionId,
    required this.name,
    required this.courseIds,
  });

  factory SectionOption.fromJson(Map<String, dynamic> json) {
    return SectionOption(
      sectionId: (json['section_id'] ?? '').toString(),
      name: (json['section_name'] ?? '').toString(),
      courseIds: (json['course_ids'] as List<dynamic>? ?? [])
          .map((c) => c.toString())
          .toList(),
    );
  }
}

/// Thrown when the server refuses a scan because the student ID is not on any section.
class StudentNotInSectionException implements Exception {
  final String? studentId;
  final String message;

  StudentNotInSectionException(this.studentId, this.message);

  @override
  String toString() => message;
}

/// Thrown when adding a student who already belongs to a different section.
class StudentInOtherSectionException implements Exception {
  final StudentBlock existing;
  final String message;

  StudentInOtherSectionException(this.existing, this.message);

  @override
  String toString() => message;
}

class BubbleScan {
  final String scanId;
  final String templateId;
  final String studentIdentifier;
  final Map<String, String> responses;
  final double? scoreRaw;
  final double? scorePercent;
  final double? maxScore;
  final bool isFlagged;
  final String? flagReason;
  final String createdAt;

  BubbleScan({
    required this.scanId,
    required this.templateId,
    required this.studentIdentifier,
    required this.responses,
    this.scoreRaw,
    this.scorePercent,
    this.maxScore,
    required this.isFlagged,
    this.flagReason,
    required this.createdAt,
  });

  factory BubbleScan.fromJson(Map<String, dynamic> json) {
    return BubbleScan(
      scanId: json['scan_id'] ?? '',
      templateId: json['template_id'] ?? '',
      studentIdentifier: json['student_identifier'] ?? '',
      responses: Map<String, String>.from(json['responses'] ?? {}),
      scoreRaw: (json['score_raw'] as num?)?.toDouble(),
      scorePercent: (json['score_percent'] as num?)?.toDouble(),
      maxScore: (json['max_score'] as num?)?.toDouble(),
      isFlagged: json['is_flagged'] ?? false,
      flagReason: json['flag_reason'],
      createdAt: json['created_at'] ?? '',
    );
  }
}
