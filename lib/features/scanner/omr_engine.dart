import 'dart:io';
import 'package:image/image.dart' as img;
import '../grading/models.dart';
import 'omr_imaging.dart';
import 'omr_models.dart';

/// On‑device OMR scanning engine.
///
/// Pipeline: load → QR → fiducials → warp → ID bubbles → answer bubbles → grade.
class OmrEngine {
  static const double fillThreshold = 128;
  static const double minFill = 0.28;
  static const double marginFill = 0.08;
  static const double goodFill = 0.42;

  static Future<OmrResult> processScan(
    String imagePath,
    BubbleTemplate template,
  ) async {
    final sw = Stopwatch()..start();

    final bytes = await File(imagePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image.');

    final layout = template.layoutMetadata;

    // Step 1 – QR for student ID
    String? studentId = await OmrImaging.decodeQR(imagePath);

    // Step 2 – Fiducial detect + warp
    final fiducials = OmrImaging.detectFiducials(image, layout);
    img.Image warped;
    double dpi;
    if (fiducials.length >= 4) {
      final sorted = OmrImaging.sortCorners(fiducials);
      final wf = OmrImaging.warp(sorted, image, layout);
      warped = wf.$1;
      dpi = wf.$2;
    } else {
      warped = image;
      dpi = warped.width / (((layout['page_width_pt'] as num?) ?? 595.28).toDouble() / 72.0);
    }

    // Step 3 – ID bubbles (fallback)
    studentId ??= OmrImaging.readIDBubbles(warped, layout, dpi);

    // Step 4 – Answer bubbles
    final readings = _readAnswers(warped, template, layout, dpi);

    final responses = <String, String>{};
    for (final r in readings) {
      if (r.detectedAnswer != '?') {
        responses[r.itemNumber.toString()] = r.detectedAnswer;
      }
    }

    // Step 5 – Grade
    final gr = _grade(responses, template.answerKey);

    sw.stop();

    final flagged = readings
        .where((r) => r.isAmbiguous)
        .map((r) => r.itemNumber)
        .toList();
    final reasons = <String>[];
    if (studentId == null || studentId.contains('?')) reasons.add('Student ID incomplete');
    if (flagged.isNotEmpty) {
      reasons.add('${flagged.length} ambiguous item(s)');
    }

    return OmrResult(
      studentIdentifier: studentId,
      responses: responses,
      readings: readings,
      correctCount: gr.$1,
      maxScore: gr.$2,
      scorePercent: gr.$3,
      isFlagged: flagged.isNotEmpty || studentId == null,
      flagReason: reasons.isEmpty ? null : reasons.join('; '),
      flaggedItems: flagged,
      processingTime: sw.elapsed,
    );
  }

  // ── Answer bubble reading ──────────────────────────────────────────────

  static List<BubbleReading> _readAnswers(
    img.Image warped,
    BubbleTemplate template,
    Map<String, dynamic> layout,
    double dpi,
  ) {
    final grid = layout['answer_grid'] as Map<String, dynamic>? ?? {};
    final bubbleRmm = (grid['bubble_r_mm'] as num?)?.toDouble() ?? 2.0;
    final bubbleR = (bubbleRmm * dpi / 25.4).round();

    final items = layout['items'] as Map<String, dynamic>? ?? {};
    final results = <BubbleReading>[];
    final choices = List.generate(template.numChoices, (i) => String.fromCharCode(65 + i));

    for (int i = 1; i <= template.totalItems; i++) {
      final item = items[i.toString()] as Map<String, dynamic>?;
      if (item == null) {
        results.add(BubbleReading(
          itemNumber: i,
          detectedAnswer: '?',
          fillRatio: 0,
          isAmbiguous: true,
          isConfirmed: false,
          confidenceNote: 'No layout data',
        ));
        continue;
      }

      double bestFill = 0;
      String bestChoice = '?';
      double secondFill = 0;

      for (final ch in choices) {
        final coord = item[ch] as Map<String, dynamic>?;
        if (coord == null) continue;

        final cxMm = (coord['cx_mm'] as num?)?.toDouble() ?? 0;
        final cyMm = (coord['cy_spec_mm'] as num?)?.toDouble() ?? 0;
        final cx = (cxMm * dpi / 25.4).round();
        final cy = (cyMm * dpi / 25.4).round();

        final fill = OmrImaging.sampleCircle(warped, cx, cy, bubbleR);
        if (fill > bestFill) {
          secondFill = bestFill;
          bestFill = fill;
          bestChoice = ch;
        } else if (fill > secondFill) {
          secondFill = fill;
        }
      }

      final isAmbiguous = bestFill < minFill || (bestFill - secondFill).abs() < marginFill;
      final isConfirmed = !isAmbiguous && bestFill >= goodFill;

      results.add(BubbleReading(
        itemNumber: i,
        detectedAnswer: isAmbiguous ? '?' : bestChoice,
        fillRatio: bestFill,
        secondFillRatio: secondFill,
        isAmbiguous: isAmbiguous,
        isConfirmed: isConfirmed,
        confidenceNote: isAmbiguous
            ? (bestFill < minFill ? 'Low fill ($bestFill)' : 'Too close ($bestFill vs $secondFill)')
            : (isConfirmed ? 'Confirmed ($bestFill)' : 'Acceptable ($bestFill)'),
      ));
    }

    return results;
  }

  // ── Grading ─────────────────────────────────────────────────────────────

  static (int, int, double) _grade(
    Map<String, String> responses,
    Map<String, String> answerKey,
  ) {
    if (answerKey.isEmpty) return (0, responses.length, 0);
    int correct = 0;
    int maxScore = answerKey.length;
    for (final entry in answerKey.entries) {
      if (responses[entry.key] == entry.value) correct++;
    }
    final pct = maxScore > 0 ? (correct / maxScore) * 100.0 : 0.0;
    return (correct, maxScore, pct);
  }
}
