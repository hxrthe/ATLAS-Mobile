class BubbleReading {
  final int itemNumber;
  final String detectedAnswer;
  final double fillRatio;
  final double? secondFillRatio;
  final bool isAmbiguous;
  final bool isConfirmed;
  final String? confidenceNote;

  BubbleReading({
    required this.itemNumber,
    required this.detectedAnswer,
    required this.fillRatio,
    this.secondFillRatio,
    required this.isAmbiguous,
    required this.isConfirmed,
    this.confidenceNote,
  });

  Map<String, dynamic> toJson() => {
        'item_number': itemNumber,
        'detected_answer': detectedAnswer,
        'fill_ratio': fillRatio,
        'second_fill_ratio': secondFillRatio,
        'is_ambiguous': isAmbiguous,
        'confidence_note': confidenceNote,
      };
}

class OmrResult {
  final String? studentIdentifier;
  final Map<String, String> responses;
  final List<BubbleReading> readings;
  final int correctCount;
  final int maxScore;
  final double scorePercent;
  final bool isFlagged;
  final String? flagReason;
  final List<int> flaggedItems;
  final Duration processingTime;

  OmrResult({
    this.studentIdentifier,
    required this.responses,
    required this.readings,
    required this.correctCount,
    required this.maxScore,
    required this.scorePercent,
    this.isFlagged = false,
    this.flagReason,
    this.flaggedItems = const [],
    this.processingTime = const Duration(),
  });

  double get scoreRaw => correctCount.toDouble();
}
