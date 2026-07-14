class BubbleSheetTemplate {
  final String templateId;
  final String courseId;
  final String name;
  final int totalItems;
  final int numChoices;
  final bool hasEssay;
  final Map<String, dynamic> answerKey;
  final Map<String, dynamic> layoutMetadata;

  BubbleSheetTemplate({
    required this.templateId,
    required this.courseId,
    required this.name,
    required this.totalItems,
    required this.numChoices,
    required this.hasEssay,
    required this.answerKey,
    required this.layoutMetadata,
  });

  factory BubbleSheetTemplate.fromJson(Map<String, dynamic> json) {
    return BubbleSheetTemplate(
      templateId: json['template_id'] ?? '',
      courseId: json['course_id'] ?? '',
      name: json['name'] ?? 'Untitled Template',
      totalItems: json['total_items'] ?? 30,
      numChoices: json['num_choices'] ?? 4,
      hasEssay: json['has_essay'] ?? false,
      answerKey: json['answer_key'] ?? {},
      layoutMetadata: json['layout_metadata'] ?? {},
    );
  }
}

class BubbleSheetScanResult {
  final String scanId;
  final String studentIdentifier;
  final double? scoreRaw;
  final double? scorePercent;
  final bool isFlagged;
  final String? flagReason;
  final Map<String, dynamic> responses;

  BubbleSheetScanResult({
    required this.scanId,
    required this.studentIdentifier,
    this.scoreRaw,
    this.scorePercent,
    required this.isFlagged,
    this.flagReason,
    required this.responses,
  });

  factory BubbleSheetScanResult.fromJson(Map<String, dynamic> json) {
    return BubbleSheetScanResult(
      scanId: json['scan_id'] ?? '',
      studentIdentifier: json['student_identifier'] ?? 'Unknown',
      scoreRaw: json['score_raw'] != null ? double.parse(json['score_raw'].toString()) : null,
      scorePercent: json['score_percent'] != null ? double.parse(json['score_percent'].toString()) : null,
      isFlagged: json['is_flagged'] ?? false,
      flagReason: json['flag_reason'],
      responses: json['responses'] ?? {},
    );
  }
}