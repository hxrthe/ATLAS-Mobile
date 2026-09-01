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
  });

  /// Returns true when bubble positions are available for template-based OMR.
  bool get hasLayoutItems {
    final items = layoutMetadata['items'];
    return items is Map && items.isNotEmpty;
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
      answerKey: Map<String, String>.from(json['answer_key'] ?? {}),
      passingScore: (json['passing_score'] as num?)?.toDouble(),
      layoutMetadata: json['layout_metadata'] ?? {},
    );
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
