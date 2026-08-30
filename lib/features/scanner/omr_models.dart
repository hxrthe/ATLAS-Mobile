import 'dart:ui';

class BubbleReading {
  final int itemNumber;
  final String detectedAnswer;
  final double fillRatio;
  final double? secondFillRatio;
  final bool isAmbiguous;
  final bool isConfirmed;
  final String? confidenceNote;

  // ── ZipGrade-inspired fields ──────────────────────────────────────────
  /// 0–1 probability this is a glare artifact (specular reflection).
  final double glareProbability;

  /// 0–1 probability this is an erasure mark.
  final double erasureProbability;

  /// 0–1 overall confidence in the classification.
  final double confidenceScore;

  /// Full 7-feature vector for debug/analysis.
  final Map<String, double>? features;

  BubbleReading({
    required this.itemNumber,
    required this.detectedAnswer,
    required this.fillRatio,
    this.secondFillRatio,
    required this.isAmbiguous,
    required this.isConfirmed,
    this.confidenceNote,
    this.glareProbability = 0,
    this.erasureProbability = 0,
    this.confidenceScore = 0,
    this.features,
  });

  Map<String, dynamic> toJson() => {
        'item_number': itemNumber,
        'detected_answer': detectedAnswer,
        'fill_ratio': fillRatio,
        'second_fill_ratio': secondFillRatio,
        'is_ambiguous': isAmbiguous,
        'confidence_note': confidenceNote,
        'glare_probability': glareProbability,
        'erasure_probability': erasureProbability,
        'confidence_score': confidenceScore,
        'features': features,
      };

  factory BubbleReading.fromJson(Map<String, dynamic> json) {
    return BubbleReading(
      itemNumber: json['item_number'] ?? 0,
      detectedAnswer: json['detected_answer'] ?? '?',
      fillRatio: (json['fill_ratio'] as num?)?.toDouble() ?? 0,
      secondFillRatio: (json['second_fill_ratio'] as num?)?.toDouble(),
      isAmbiguous: json['is_ambiguous'] ?? false,
      isConfirmed: false,
      confidenceNote: json['confidence_note'],
      glareProbability: (json['glare_probability'] as num?)?.toDouble() ?? 0,
      erasureProbability: (json['erasure_probability'] as num?)?.toDouble() ?? 0,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0,
      features: json['features'] != null
          ? Map<String, double>.from(json['features'])
          : null,
    );
  }
}

class OmrResult {
  final String? studentIdentifier;
  /// Assessment ID from QR (or template), when available.
  final String? assessmentId;
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
    this.assessmentId,
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

// ═══════════════════════════════════════════════════════════════════════════
// Real-time fiducial tracking for live viewfinder
// ═══════════════════════════════════════════════════════════════════════════

enum CornerId { topLeft, topRight, bottomLeft, bottomRight }

class CornerLock {
  final CornerId id;
  final bool detected;
  final bool locked;
  final int consecutiveFrames;
  final Offset? position; // normalised 0–1 within camera preview

  const CornerLock({
    required this.id,
    this.detected = false,
    this.locked = false,
    this.consecutiveFrames = 0,
    this.position,
  });

  CornerLock copyWith({
    bool? detected,
    bool? locked,
    int? consecutiveFrames,
    Offset? position,
  }) {
    return CornerLock(
      id: id,
      detected: detected ?? this.detected,
      locked: locked ?? this.locked,
      consecutiveFrames: consecutiveFrames ?? this.consecutiveFrames,
      position: position ?? this.position,
    );
  }
}

class FiducialLockState {
  final List<CornerLock> corners;
  final bool allLocked;
  final int lockDuration; // frames all 4 have been stable

  const FiducialLockState({
    required this.corners,
    this.allLocked = false,
    this.lockDuration = 0,
  });

  factory FiducialLockState.initial() {
    return FiducialLockState(
      corners: CornerId.values
          .map((id) => CornerLock(id: id))
          .toList(),
    );
  }

  FiducialLockState update({
    required bool tl, required bool tr, required bool bl, required bool br,
    Offset? tlPos, Offset? trPos, Offset? blPos, Offset? brPos,
    required int lockThresholdFrames,
  }) {
    final detections = [tl, tr, bl, br];
    final positions = [tlPos, trPos, blPos, brPos];
    final newCorners = <CornerLock>[];

    for (int i = 0; i < 4; i++) {
      final old = corners[i];
      int consec = old.consecutiveFrames;
      
      if (detections[i]) {
        // Boost detection strength quickly
        consec = (consec + 2).clamp(0, lockThresholdFrames * 2);
      } else {
        // Decay detection strength slowly (Grace period for flickers)
        consec = (consec - 1).clamp(0, lockThresholdFrames * 2);
      }
      
      final locked = consec >= lockThresholdFrames;

      newCorners.add(CornerLock(
        id: old.id,
        detected: detections[i],
        locked: locked,
        consecutiveFrames: consec,
        position: positions[i] ?? old.position,
      ));
    }

    final allLockedNow = newCorners.every((c) => c.locked);
    final newDuration = allLockedNow ? lockDuration + 1 : 0;

    return FiducialLockState(
      corners: newCorners,
      allLocked: allLockedNow,
      lockDuration: newDuration,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Environmental diagnostics for the status bar
// ═══════════════════════════════════════════════════════════════════════════

enum DiagnosticLevel { ok, warning, error, info }

class BubbleOverlayData {
  final Offset position; // Normalized 0-1
  final Color color;
  final String label;

  const BubbleOverlayData({
    required this.position,
    required this.color,
    this.label = '',
  });
}

class ScannerDiagnostics {
  final double glareScore;     // 0–1, higher = more glare
  final double sharpnessScore; // 0–1, higher = sharper
  final bool isBlurry;
  final bool hasGlare;
  final DiagnosticLevel level;
  final String message;

  const ScannerDiagnostics({
    this.glareScore = 0,
    this.sharpnessScore = 1,
    this.isBlurry = false,
    this.hasGlare = false,
    this.level = DiagnosticLevel.ok,
    this.message = '',
  });

  factory ScannerDiagnostics.ok() {
    return const ScannerDiagnostics(
      message: '',
      level: DiagnosticLevel.ok,
    );
  }

  factory ScannerDiagnostics.fromScores({
    required double glare,
    required double sharpness,
    int lockedCorners = 0,
  }) {
    final hasGlare = glare > 0.45;
    final isBlurry = sharpness < 0.30;
    final level = (hasGlare || isBlurry)
        ? DiagnosticLevel.warning
        : DiagnosticLevel.ok;

    String message;
    if (isBlurry) {
      message = 'Waiting for Autofocus';
    } else if (hasGlare) {
      message = 'Bright Light Detected';
    } else if (lockedCorners == 0) {
      message = 'Point at sheet (QR + page edges)';
    } else if (lockedCorners < 4) {
      message = 'Corners optional — capture when ready';
    } else {
      message = '';
    }

    return ScannerDiagnostics(
      glareScore: glare,
      sharpnessScore: sharpness,
      isBlurry: isBlurry,
      hasGlare: hasGlare,
      level: level,
      message: message,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Scan record for local history (review screen)
// ═══════════════════════════════════════════════════════════════════════════

class ScanRecord {
  final String id;
  final String templateId;
  final String templateName;
  final String studentIdentifier;
  final Map<String, String> responses;
  final double? scorePercent;
  final double? scoreRaw;
  final double? maxScore;
  final bool isFlagged;
  final String? flagReason;
  final List<int> flaggedItems;
  final String? imagePath;
  final DateTime createdAt;
  final String? serverScanId; // set after successful upload

  ScanRecord({
    required this.id,
    required this.templateId,
    required this.templateName,
    required this.studentIdentifier,
    required this.responses,
    this.scorePercent,
    this.scoreRaw,
    this.maxScore,
    this.isFlagged = false,
    this.flagReason,
    this.flaggedItems = const [],
    this.imagePath,
    required this.createdAt,
    this.serverScanId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'template_id': templateId,
        'template_name': templateName,
        'student_identifier': studentIdentifier,
        'responses': responses,
        'score_percent': scorePercent,
        'score_raw': scoreRaw,
        'max_score': maxScore,
        'is_flagged': isFlagged,
        'flag_reason': flagReason,
        'flagged_items': flaggedItems,
        'image_path': imagePath,
        'created_at': createdAt.toIso8601String(),
        'server_scan_id': serverScanId,
      };

  factory ScanRecord.fromJson(Map<String, dynamic> json) {
    return ScanRecord(
      id: json['id'] ?? '',
      templateId: json['template_id'] ?? '',
      templateName: json['template_name'] ?? '',
      studentIdentifier: json['student_identifier'] ?? 'Unknown',
      responses: Map<String, String>.from(json['responses'] ?? {}),
      scorePercent: (json['score_percent'] as num?)?.toDouble(),
      scoreRaw: (json['score_raw'] as num?)?.toDouble(),
      maxScore: (json['max_score'] as num?)?.toDouble(),
      isFlagged: json['is_flagged'] ?? false,
      flagReason: json['flag_reason'],
      flaggedItems: List<int>.from(json['flagged_items'] ?? []),
      imagePath: json['image_path'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      serverScanId: json['server_scan_id'],
    );
  }

  ScanRecord copyWith({
    Map<String, String>? responses,
    double? scorePercent,
    double? scoreRaw,
    double? maxScore,
    bool? isFlagged,
    String? flagReason,
    List<int>? flaggedItems,
    String? serverScanId,
  }) {
    return ScanRecord(
      id: id,
      templateId: templateId,
      templateName: templateName,
      studentIdentifier: studentIdentifier,
      responses: responses ?? this.responses,
      scorePercent: scorePercent ?? this.scorePercent,
      scoreRaw: scoreRaw ?? this.scoreRaw,
      maxScore: maxScore ?? this.maxScore,
      isFlagged: isFlagged ?? this.isFlagged,
      flagReason: flagReason ?? this.flagReason,
      flaggedItems: flaggedItems ?? this.flaggedItems,
      imagePath: imagePath,
      createdAt: createdAt,
      serverScanId: serverScanId ?? this.serverScanId,
    );
  }
}
