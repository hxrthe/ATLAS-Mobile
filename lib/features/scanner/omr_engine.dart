import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../grading/models.dart';
import 'omr_imaging.dart';
import 'omr_models.dart';
import 'omr_contour_bubbles.dart';

/// Payload for background isolate OMR (no ML Kit — QR decoded on UI isolate).
class OmrIsolateArgs {
  final String imagePath;
  final Map<String, dynamic> layout;
  final Map<String, String> answerKey;
  final int totalItems;
  final int numChoices;
  final String? studentId;
  final String? assessmentId;
  final String? qrAssessmentId;

  const OmrIsolateArgs({
    required this.imagePath,
    required this.layout,
    required this.answerKey,
    required this.totalItems,
    required this.numChoices,
    this.studentId,
    this.assessmentId,
    this.qrAssessmentId,
  });
}

/// Top-level entry for [Isolate.run] / [compute].
Map<String, dynamic> omrProcessInIsolate(OmrIsolateArgs args) {
  final sw = Stopwatch()..start();
  final bytes = File(args.imagePath).readAsBytesSync();
  img.Image? image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Failed to decode image.');
  }
  image = img.bakeOrientation(image);

  final layout = args.layout;
  final resolvedAssessmentId = args.assessmentId ?? args.qrAssessmentId;

  final prepared = OmrImaging.prepareSheetForOmr(image, layout);
  final studentId = args.studentId ??
      OmrImaging.readIDBubbles(prepared.gray, layout, prepared.dpi);

  final hasItems =
      (layout['items'] is Map) && (layout['items'] as Map).isNotEmpty;

  final rowResults = hasItems
      ? OmrReferenceGrader.readAnswerBubblesFromTemplate(
          prepared.binary,
          prepared.gray,
          layout,
          prepared.dpi,
          args.numChoices,
        )
      : List.generate(
          args.totalItems,
          (i) => RowReadResult(
            itemNumber: i + 1,
            answer: '?',
            ambiguous: true,
          ),
        );

  final readings = OmrReferenceGrader.toBubbleReadings(
    rowResults,
    args.totalItems,
  );

  final responses = <String, String>{};
  for (final r in readings) {
    if (r.detectedAnswer != '?') {
      responses[r.itemNumber.toString()] = r.detectedAnswer;
    }
  }

  final gr = OmrEngine.grade(responses, args.answerKey, args.totalItems);
  sw.stop();

  // Encode bird's-eye JPEG for the post-capture result UI.
  img.Image display = prepared.color;
  const maxW = 900;
  if (display.width > maxW) {
    final nh = (display.height * maxW / display.width).round();
    display = img.copyResize(display, width: maxW, height: nh);
  }
  final alignedJpeg = Uint8List.fromList(img.encodeJpg(display, quality: 78));

  final markers = _buildScoredMarkers(
    layout: layout,
    answerKey: args.answerKey,
    responses: responses,
    dpi: prepared.dpi,
    imageWidth: prepared.gray.width,
    imageHeight: prepared.gray.height,
  );

  final flagged = readings
      .where((r) => r.isAmbiguous)
      .map((r) => r.itemNumber)
      .toList();
  final reasons = <String>[];
  if (prepared.lowConfidence) {
    reasons.add('Low-confidence alignment (${prepared.method})');
  }
  if (!hasItems) {
    reasons.add('Template missing bubble layout — regenerate PDF');
  }
  final idPartial = studentId != null && studentId.contains('?');
  if (studentId == null || idPartial) reasons.add('Student ID incomplete');
  if (flagged.isNotEmpty) {
    reasons.add('${flagged.length} ambiguous item(s)');
  }

  final flagReasonRaw = reasons.isEmpty ? null : reasons.join('; ');
  final flagReason = flagReasonRaw != null && flagReasonRaw.length > 255
      ? '${flagReasonRaw.substring(0, 254)}…'
      : flagReasonRaw;

  return {
    'student_identifier': studentId,
    'assessment_id': resolvedAssessmentId,
    'responses': responses,
    'readings': readings
        .map((r) => {
              'item_number': r.itemNumber,
              'detected_answer': r.detectedAnswer,
              'fill_ratio': r.fillRatio,
              'second_fill_ratio': r.secondFillRatio,
              'is_ambiguous': r.isAmbiguous,
              'is_confirmed': r.isConfirmed,
              'confidence_note': r.confidenceNote,
              'confidence_score': r.confidenceScore,
            })
        .toList(),
    'correct_count': gr.$1,
    'max_score': gr.$2,
    'score_percent': gr.$3,
    'is_flagged': reasons.isNotEmpty,
    'flag_reason': flagReason,
    'flagged_items': flagged,
    'processing_ms': sw.elapsedMilliseconds,
    'alignment': prepared.method,
    'low_confidence': prepared.lowConfidence,
    'aligned_jpeg': alignedJpeg,
    'scored_markers': markers,
  };
}

List<Map<String, dynamic>> _buildScoredMarkers({
  required Map<String, dynamic> layout,
  required Map<String, String> answerKey,
  required Map<String, String> responses,
  required double dpi,
  required int imageWidth,
  required int imageHeight,
}) {
  final items = layout['items'];
  if (items is! Map || imageWidth <= 0 || imageHeight <= 0) return [];

  final mmToPx = dpi / 25.4;
  final out = <Map<String, dynamic>>[];

  for (final entry in answerKey.entries) {
    final itemNum = entry.key;
    final correct = entry.value;
    final detected = responses[itemNum];
    final isCorrect = detected != null && detected == correct;

    final itemData = items[itemNum];
    if (itemData is! Map) continue;

    // Mark the bubble the student filled; if blank, mark the correct bubble.
    final markChoice = (detected != null && detected.isNotEmpty)
        ? detected
        : correct;
    final coord = itemData[markChoice] ?? itemData[correct];
    if (coord is! Map) continue;

    final cxMm = (coord['cx_mm'] as num?)?.toDouble() ?? 0;
    final cyMm = (coord['cy_spec_mm'] as num?)?.toDouble() ?? 0;
    final nx = ((cxMm * mmToPx) / imageWidth).clamp(0.0, 1.0);
    final ny = ((cyMm * mmToPx) / imageHeight).clamp(0.0, 1.0);

    out.add({
      'item_number': int.tryParse(itemNum) ?? 0,
      'nx': nx,
      'ny': ny,
      'is_correct': isCorrect,
    });
  }
  return out;
}

/// On-device OMR for ATLAS 3-column bubble sheets.
///
/// Align → student ID bubbles → answer bubbles → grade vs answer key.
/// Heavy pixel work runs in a background isolate to avoid ANR.
class OmrEngine {
  static Future<OmrResult> processScan(
    String imagePath,
    BubbleTemplate template, {
    String? studentId,
    String? assessmentId,
  }) async {
    final layout = template.layoutMetadata;
    if (!template.hasLayoutItems) {
      debugPrint(
        'OMR warning: template ${template.templateId} has no layout items — '
        'regenerate the PDF on the server.',
      );
    }

    // ML Kit must stay on the main/UI isolate.
    final qrRaw = await OmrImaging.decodeQR(imagePath);
    final qrAssessmentId = OmrImaging.parseAssessmentId(qrRaw);

    final map = await Isolate.run(
      () => omrProcessInIsolate(OmrIsolateArgs(
        imagePath: imagePath,
        layout: Map<String, dynamic>.from(layout),
        answerKey: Map<String, String>.from(template.answerKey),
        totalItems: template.totalItems,
        numChoices: template.numChoices,
        studentId: studentId,
        assessmentId: assessmentId,
        qrAssessmentId: qrAssessmentId,
      )),
    );

    return _resultFromMap(map);
  }

  static OmrResult _resultFromMap(Map<String, dynamic> map) {
    final readingsJson = map['readings'] as List<dynamic>? ?? [];
    final readings = readingsJson.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return BubbleReading(
        itemNumber: m['item_number'] as int? ?? 0,
        detectedAnswer: m['detected_answer'] as String? ?? '?',
        fillRatio: (m['fill_ratio'] as num?)?.toDouble() ?? 0,
        secondFillRatio: (m['second_fill_ratio'] as num?)?.toDouble(),
        isAmbiguous: m['is_ambiguous'] as bool? ?? false,
        isConfirmed: m['is_confirmed'] as bool? ?? false,
        confidenceNote: m['confidence_note'] as String?,
        confidenceScore: (m['confidence_score'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    final responses = <String, String>{};
    final raw = map['responses'] as Map? ?? {};
    raw.forEach((k, v) => responses[k.toString()] = v.toString());

    final flagged = (map['flagged_items'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [];

    debugPrint(
      'OMR alignment=${map['alignment']} '
      'answers=${responses.length} studentId=${map['student_identifier']}',
    );

    return OmrResult(
      studentIdentifier: map['student_identifier'] as String?,
      assessmentId: map['assessment_id'] as String?,
      responses: responses,
      readings: readings,
      correctCount: map['correct_count'] as int? ?? 0,
      maxScore: map['max_score'] as int? ?? 0,
      scorePercent: (map['score_percent'] as num?)?.toDouble() ?? 0,
      isFlagged: map['is_flagged'] as bool? ?? false,
      flagReason: map['flag_reason'] as String?,
      flaggedItems: flagged,
      processingTime: Duration(milliseconds: map['processing_ms'] as int? ?? 0),
      alignedImageBytes: map['aligned_jpeg'] is Uint8List
          ? map['aligned_jpeg'] as Uint8List
          : (map['aligned_jpeg'] is List
              ? Uint8List.fromList(List<int>.from(map['aligned_jpeg'] as List))
              : null),
      scoredMarkers: (map['scored_markers'] as List<dynamic>? ?? []).map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        return ScoredBubbleMarker(
          itemNumber: m['item_number'] as int? ?? 0,
          nx: (m['nx'] as num?)?.toDouble() ?? 0,
          ny: (m['ny'] as num?)?.toDouble() ?? 0,
          isCorrect: m['is_correct'] as bool? ?? false,
        );
      }).toList(),
      alignmentMethod: map['alignment']?.toString() ?? 'unknown',
      lowConfidenceAlignment: map['alignment']?.toString() == 'direct' ||
          (map['low_confidence'] as bool? ?? false),
    );
  }

  static (int, int, double) grade(
    Map<String, String> responses,
    Map<String, String> answerKey,
    int totalItems,
  ) {
    final maxScore = answerKey.isNotEmpty ? answerKey.length : totalItems;
    if (answerKey.isEmpty) {
      return (0, maxScore, 0.0);
    }
    var correct = 0;
    for (final entry in answerKey.entries) {
      if (responses[entry.key] == entry.value) correct++;
    }
    final pct = maxScore > 0 ? (correct / maxScore) * 100.0 : 0.0;
    return (correct, maxScore, pct);
  }
}
