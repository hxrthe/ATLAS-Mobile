import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../grading/models.dart';
import 'omr_imaging.dart';
import 'omr_models.dart';
import 'omr_contour_bubbles.dart';

/// On-device OMR for ATLAS 3-column bubble sheets.
///
/// Alignment: page contour → fiducial corners → direct full-frame (backend-style).
/// Reading: template mm coordinates from layout_metadata.items (primary).
class OmrEngine {
  static Future<OmrResult> processScan(
    String imagePath,
    BubbleTemplate template, {
    String? studentId,
    String? assessmentId,
  }) async {
    final sw = Stopwatch()..start();

    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image.');

    // Camera JPEGs often carry EXIF rotation — bake it before any geometry.
    image = img.bakeOrientation(image);

    final layout = template.layoutMetadata;
    if (!template.hasLayoutItems) {
      debugPrint(
        'OMR warning: template ${template.templateId} has no layout items — '
        'regenerate the PDF on the server.',
      );
    }

    final qrRaw = await OmrImaging.decodeQR(imagePath);
    final qrAssessmentId = OmrImaging.parseAssessmentId(qrRaw);
    final resolvedAssessmentId = assessmentId ??
        qrAssessmentId ??
        template.assessmentId;

    final prepared = OmrImaging.prepareSheetForOmr(image, layout);
    debugPrint(
      'OMR alignment=${prepared.method} dpi=${prepared.dpi.toStringAsFixed(1)} '
      'size=${prepared.gray.width}x${prepared.gray.height} '
      'items=${(layout['items'] as Map?)?.length ?? 0}',
    );

    final calibration = OmrReferenceGrader.estimateCalibrationOffset(
      prepared.binary,
      layout,
      prepared.dpi,
    );
    debugPrint(
      'OMR calibration offset dx=${calibration.$1.toStringAsFixed(1)} '
      'dy=${calibration.$2.toStringAsFixed(1)}',
    );

    studentId ??= OmrImaging.readIDBubbles(prepared.gray, layout, prepared.dpi);

    var rowResults = template.hasLayoutItems
        ? OmrReferenceGrader.readAnswerBubblesFromTemplate(
            prepared.binary,
            prepared.gray,
            layout,
            prepared.dpi,
            template.numChoices,
            offsetDx: calibration.$1,
            offsetDy: calibration.$2,
          )
        : <RowReadResult>[];

    final confirmed =
        rowResults.where((r) => r.answer != '?' && !r.ambiguous).length;
    if (confirmed < (template.totalItems * 0.10).ceil()) {
      final contourResults = OmrReferenceGrader.readAnswerBubbles(
        prepared.binary,
        layout,
        prepared.dpi,
        template.totalItems,
        template.numChoices,
      );
      final contourConfirmed = contourResults
          .where((r) => r.answer != '?' && !r.ambiguous)
          .length;
      if (contourConfirmed > confirmed) {
        rowResults = contourResults;
      }
    }

    if (rowResults.isEmpty && template.totalItems > 0) {
      rowResults = List.generate(
        template.totalItems,
        (i) => RowReadResult(
          itemNumber: i + 1,
          answer: '?',
          ambiguous: true,
        ),
      );
    }

    final readings = OmrReferenceGrader.toBubbleReadings(
      rowResults,
      template.totalItems,
    );

    final responses = <String, String>{};
    for (final r in readings) {
      if (r.detectedAnswer != '?') {
        responses[r.itemNumber.toString()] = r.detectedAnswer;
      }
    }

    debugPrint(
      'OMR result: ${responses.length}/${template.totalItems} answers, '
      'studentId=$studentId',
    );

    final gr = grade(responses, template.answerKey, template.totalItems);
    sw.stop();

    final flagged = readings
        .where((r) => r.isAmbiguous)
        .map((r) => r.itemNumber)
        .toList();
    final reasons = <String>[];
    if (prepared.lowConfidence) {
      reasons.add('Low-confidence alignment (${prepared.method})');
    }
    if (!template.hasLayoutItems) {
      reasons.add('Template missing bubble layout — regenerate PDF');
    }
    final idPartial = studentId != null && studentId.contains('?');
    if (studentId == null || idPartial) reasons.add('Student ID incomplete');
    if (flagged.isNotEmpty) {
      reasons.add('${flagged.length} ambiguous item(s)');
    }
    if (resolvedAssessmentId != null &&
        template.assessmentId != null &&
        resolvedAssessmentId != template.assessmentId) {
      reasons.add('Assessment QR mismatch');
    }

    final flagReasonRaw = reasons.isEmpty ? null : reasons.join('; ');
    final flagReason = flagReasonRaw != null && flagReasonRaw.length > 255
        ? '${flagReasonRaw.substring(0, 254)}…'
        : flagReasonRaw;

    return OmrResult(
      studentIdentifier: studentId,
      assessmentId: resolvedAssessmentId,
      responses: responses,
      readings: readings,
      correctCount: gr.$1,
      maxScore: gr.$2,
      scorePercent: gr.$3,
      isFlagged: reasons.isNotEmpty,
      flagReason: flagReason,
      flaggedItems: flagged,
      processingTime: sw.elapsed,
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
