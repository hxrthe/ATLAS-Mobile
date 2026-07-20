import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import '../grading/models.dart';
import 'omr_imaging.dart';
import 'dart:isolate';
import 'omr_models.dart';

/// On‑device OMR scanning engine.
///
/// Pipeline: load → fiducials (blob → edge fallback) → warp →
///           enhanced preprocessing (blur → normalize → truncate →
///           local contrast → gamma → normalize) → ID bubbles →
///           answer bubbles (global + local threshold with hysteresis) → grade.
class OmrEngine {
  // Thresholding parameters — tuned against OMRChecker + AndroidOMRHelper
  static const double minGap = 0.10;             // minimum gap for largest-gap detection
  static const double minJump = 0.25;            // confident surplus (OMRChecker's CONFIDENT_SURPLUS)
  static const double confidentSurplus = 0.05;   // extra margin for confident detection
  static const double marginFill = 0.05;         // best vs second-best gap for ambiguity
  static const double goodFill = 0.38;           // above this = confirmed (not just acceptable)
  static const double hysteresisMargin = 0.06;   // must exceed global threshold by this much

  static Future<OmrResult> processScan(
    String imagePath,
    BubbleTemplate template, {
    String? studentId,
  }) async {
    // Offload the heavy image processing to a background thread
    return await Isolate.run(() async {
      final sw = Stopwatch()..start();

      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image.');

      final layout = template.layoutMetadata;

      // FIX: Step 1 – Pre-process the image FIRST to normalize lighting and contrast
      final processed = OmrImaging.preProcessForOcr(image);

      // Step 2 – Detect fiducials on the clean, high-contrast image
      final fiducials = OmrImaging.detectFiducialsRobust(processed, layout);
      img.Image warped;
      double dpi;
      if (fiducials.length >= 4) {
        final sorted = OmrImaging.sortCorners(fiducials);
        final wf = OmrImaging.warp(sorted, processed, layout);
        warped = wf.$1;
        dpi = wf.$2;
      } else {
        warped = processed;
        dpi = warped.width / (((layout['page_width_pt'] as num?) ?? 595.28).toDouble() / 72.0);
      }

      // Step 3 – ID bubbles (primary student identification)
      studentId ??= OmrImaging.readIDBubbles(warped, layout, dpi);

      // Step 3 – Answer bubbles
      final readings = _readAnswers(warped, template, layout, dpi);

      final responses = <String, String>{};
      for (final r in readings) {
        if (r.detectedAnswer != '?') {
          responses[r.itemNumber.toString()] = r.detectedAnswer;
        }
      }

      // Step 4 – Grade
      final gr = grade(responses, template.answerKey);

      sw.stop();

      final flagged = readings
          .where((r) => r.isAmbiguous)
          .map((r) => r.itemNumber)
          .toList();
      final reasons = <String>[];
      final idPartial = studentId != null && studentId!.contains('?');
      if (studentId == null || idPartial) reasons.add('Student ID incomplete');
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
        isFlagged: flagged.isNotEmpty || studentId == null || idPartial,
        flagReason: reasons.isEmpty ? null : reasons.join('; '),
        flaggedItems: flagged,
        processingTime: sw.elapsed,
      );
    });
  }

  // ── Thresholding helpers ────────────────────────────────────────────────

  /// Find threshold at the largest gap between sorted fill values.
  /// Falls back to [fallback] if no gap exceeds [minGap].
  /// Returns (threshold, maxGap).
  static (double, double) _largestGapThreshold(List<double> fills, double fallback) {
    if (fills.length < 2) return (fallback, 0);
    final sorted = List<double>.from(fills)..sort();
    double maxGap = 0;
    double thr = fallback;

    for (int i = 1; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap > maxGap) {
        maxGap = gap;
        thr = sorted[i - 1] + gap / 2;
      }
    }

    return maxGap >= minGap ? (thr, maxGap) : (fallback, maxGap);
  }

  static double _stdDev(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((f) => (f - mean) * (f - mean)).reduce((a, b) => a + b) / values.length;
    return variance > 0 ? sqrt(variance) : 0;
  }

  static ({String detectedAnswer, bool isAmbiguous, bool isConfirmed, String note}) evaluateBubbleSelection({
    required String bestChoice,
    required double bestFill,
    required double secondFill,
    required double globalThr,
    required double effectiveThr,
    required double maxGap,
    required bool lowConfidence,
    required bool noOutliers,
    required bool aboveEffective,
    required bool aboveGlobal,
    required bool passesHysteresis,
    required double goodFill,
  }) {
    final gap = (bestFill - secondFill).abs();
    final strongSelection = bestFill >= 0.18 && gap >= 0.06;
    final isAmbiguous = !strongSelection &&
        (!passesHysteresis || gap < marginFill || (lowConfidence && bestFill < 0.16));
    final isConfirmed = !isAmbiguous && (bestFill >= goodFill || (bestFill >= 0.22 && gap >= 0.08));

    String note;
    if (isAmbiguous) {
      if (noOutliers) {
        note = 'No outliers (all fills ~${bestFill.toStringAsFixed(2)})';
      } else if (!aboveEffective) {
        note = 'Low fill ($bestFill vs thr $effectiveThr)';
      } else if (!aboveGlobal) {
        note = 'Below global thr (${(globalThr - hysteresisMargin).toStringAsFixed(2)})';
      } else if (lowConfidence) {
        note = 'Low confidence (gap ${maxGap.toStringAsFixed(2)})';
      } else {
        note = 'Too close ($bestFill vs $secondFill)';
      }
    } else {
      note = isConfirmed ? 'Confirmed ($bestFill, $effectiveThr)' : 'Acceptable ($bestFill, $effectiveThr)';
    }

    return (
      detectedAnswer: isAmbiguous ? '?' : bestChoice,
      isAmbiguous: isAmbiguous,
      isConfirmed: isConfirmed,
      note: note,
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
    final choices = List.generate(template.numChoices, (i) => String.fromCharCode(65 + i));

    // ── Phase 1: Sample all bubbles, compute per-item statistics ──────────
    final allStripFills = <List<double>>[];
    final rawResults = <_RawItem>[];

    for (int i = 1; i <= template.totalItems; i++) {
      final item = items[i.toString()] as Map<String, dynamic>?;
      if (item == null) {
        rawResults.add(_RawItem(itemNumber: i, fills: [], bestChoice: '?', bestFill: 0, secondFill: 0));
        allStripFills.add([]);
        continue;
      }

      double bestFill = 0;
      String bestChoice = '?';
      double secondFill = 0;
      final perItemFills = <double>[];

      for (final ch in choices) {
        final coord = item[ch] as Map<String, dynamic>?;
        if (coord == null) { perItemFills.add(0); continue; }

        final cxMm = (coord['cx_mm'] as num?)?.toDouble() ?? 0;
        final cyMm = (coord['cy_spec_mm'] as num?)?.toDouble() ?? 0;
        final cx = (cxMm * dpi / 25.4).round();
        final cy = (cyMm * dpi / 25.4).round();

        final fill = OmrImaging.sampleCircle(warped, cx, cy, bubbleR);
        perItemFills.add(fill);
        if (fill > bestFill) {
          secondFill = bestFill;
          bestFill = fill;
          bestChoice = ch;
        } else if (fill > secondFill) {
          secondFill = fill;
        }
      }

      rawResults.add(_RawItem(itemNumber: i, fills: perItemFills, bestChoice: bestChoice, bestFill: bestFill, secondFill: secondFill));
      allStripFills.add(perItemFills);
    }

    // ── Phase 2: Global threshold from ALL fill values ────────────────────
    final allFills = <double>[];
    for (final strip in allStripFills) {
      allFills.addAll(strip);
    }
    final (globalThr, _) = _largestGapThreshold(allFills, 0.40);

    // ── Phase 3: Global stddev threshold (outlier detection) ────────────
    final allStdDevs = <double>[];
    for (final strip in allStripFills) {
      if (strip.length >= 2) allStdDevs.add(_stdDev(strip));
    }
    final (globalStdThr, _) = _largestGapThreshold(allStdDevs, 0.05);

    // ── Phase 4: Per-item local thresholding with hysteresis ────────────
    final results = <BubbleReading>[];

    for (final raw in rawResults) {
      if (raw.fills.isEmpty) {
        results.add(BubbleReading(
          itemNumber: raw.itemNumber,
          detectedAnswer: '?',
          fillRatio: 0,
          isAmbiguous: true,
          isConfirmed: false,
          confidenceNote: 'No layout data',
        ));
        continue;
      }

      final localStdDev = _stdDev(raw.fills);
      final noOutliers = localStdDev < globalStdThr;

      // Find largest gap in this item's fills
      final (localThr, maxGap) = _largestGapThreshold(raw.fills, globalThr);

      // Determine which threshold to use — hysteresis from OMRChecker
      double effectiveThr;
      bool lowConfidence = false;
      String thresholdSource = '';

      if (maxGap < minGap) {
        // No meaningful gap — use global threshold
        effectiveThr = globalThr;
        lowConfidence = true;
        thresholdSource = 'global';
      } else if (maxGap < minJump && !noOutliers) {
        // Gap exists but not confident — hysteresis: must exceed BOTH thresholds
        effectiveThr = max(localThr, globalThr - hysteresisMargin);
        lowConfidence = true;
        thresholdSource = 'hysteresis';
      } else if (noOutliers) {
        // All fills nearly identical → force global (prevents phantom pick)
        effectiveThr = globalThr;
        lowConfidence = true;
        thresholdSource = 'global';
      } else {
        // Confident local gap — use local, but ensure it's not below global
        effectiveThr = max(localThr, globalThr - hysteresisMargin);
        thresholdSource = 'local';
      }

      // A bubble is "marked" when fill exceeds threshold (higher = darker)
      // Hysteresis: must exceed BOTH effective threshold AND global threshold
      final aboveEffective = raw.bestFill >= effectiveThr;
      final aboveGlobal = raw.bestFill >= (globalThr - hysteresisMargin);
      final passesHysteresis = aboveEffective && aboveGlobal;

      final selection = evaluateBubbleSelection(
        bestChoice: raw.bestChoice,
        bestFill: raw.bestFill,
        secondFill: raw.secondFill,
        globalThr: globalThr,
        effectiveThr: effectiveThr,
        maxGap: maxGap,
        lowConfidence: lowConfidence,
        noOutliers: noOutliers,
        aboveEffective: aboveEffective,
        aboveGlobal: aboveGlobal,
        passesHysteresis: passesHysteresis,
        goodFill: goodFill,
      );

      results.add(BubbleReading(
        itemNumber: raw.itemNumber,
        detectedAnswer: selection.detectedAnswer,
        fillRatio: raw.bestFill,
        secondFillRatio: raw.secondFill,
        isAmbiguous: selection.isAmbiguous,
        isConfirmed: selection.isConfirmed,
        confidenceNote: selection.note,
      ));
    }

    return results;
  }

  // ── Grading ─────────────────────────────────────────────────────────────

  static (int, int, double) grade(
    Map<String, String> responses,
    Map<String, String> answerKey,
  ) {
    if (answerKey.isEmpty) return (0, 0, 0.0);
    int correct = 0;
    int maxScore = answerKey.length;
    for (final entry in answerKey.entries) {
      if (responses[entry.key] == entry.value) correct++;
    }
    final pct = maxScore > 0 ? (correct / maxScore) * 100.0 : 0.0;
    return (correct, maxScore, pct);
  }
}

/// Temporary struct for per-item sampling results.
class _RawItem {
  final int itemNumber;
  final List<double> fills;
  final String bestChoice;
  final double bestFill;
  final double secondFill;
  _RawItem({
    required this.itemNumber,
    required this.fills,
    required this.bestChoice,
    required this.bestFill,
    required this.secondFill,
  });
}
