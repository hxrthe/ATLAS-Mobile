import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;
import '../grading/models.dart';
import 'omr_imaging.dart';
import 'omr_models.dart';
import 'omr_classifier.dart';

/// On-device OMR engine — hybrid pipeline.
///
/// Inspired by ShreenidhiBodas/OMR + ATLAS template metadata:
///   1. Assessment QR decode
///   2. Contour-first page detection (fiducials as fallback)
///   3. Warp to full page canvas at fixed DPI
///   4. Otsu BINARY_INV on warped grayscale
///   5. Mask fill counting (primary) + local centre refinement
///   6. 7-feature classifier only for borderline / glare / erasure
///   7. Student ID + grade + flag
class OmrEngine {
  static const double minGap = 0.10;
  static const double minJump = 0.25;
  static const double marginFill = 0.08;
  static const double goodFill = 0.42;
  static const double hysteresisMargin = 0.06;

  /// Mask fill weight vs multi-feature score for hybrid decision.
  static const double maskWeight = 0.60;
  static const double featureWeight = 0.40;

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

    final layout = template.layoutMetadata;
    final targetDpi = (layout['dpi'] as num?)?.toDouble() ?? 150.0;

    // ── Step 0: Assessment QR (still image) ──────────────────────────────
    final qrRaw = await OmrImaging.decodeQR(imagePath);
    final qrAssessmentId = OmrImaging.parseAssessmentId(qrRaw);
    final resolvedAssessmentId = assessmentId ??
        qrAssessmentId ??
        template.assessmentId;

    // ── Step 1: Contour-first sheet alignment ────────────────────────────
    final detected = OmrImaging.detectSheetCorners(image, layout);
    img.Image warped;
    double dpi;
    bool alignmentOk = detected.corners.length >= 4;

    if (alignmentOk) {
      final wf = OmrImaging.warpToPage(
        detected.corners,
        image,
        layout,
        fromPageEdges: detected.fromPageEdges,
        targetDpi: targetDpi,
      );
      warped = wf.$1;
      dpi = wf.$2;
    } else {
      // Last resort: use image as-is with estimated DPI
      warped = image;
      dpi = warped.width /
          (((layout['page_width_pt'] as num?) ?? 612.0).toDouble() / 72.0);
    }

    // Light blur before Otsu (reference: GaussianBlur then THRESH_OTSU)
    final forBinary = OmrImaging.blurOnly(warped, kernel: 5);

    // ── Step 2: Otsu BINARY_INV ──────────────────────────────────────────
    final binary = OmrImaging.otsuBinarize(forBinary);

    // Mild grayscale prep for 7-feature borderline cases only
    final grayEnhanced = OmrImaging.preProcessForOcr(warped);

    // ── Step 3: Student ID (mask fill on binary) ─────────────────────────
    studentId ??= _readIDBubblesHybrid(binary, layout, dpi);

    // ── Step 4: Answer bubbles (mask-primary hybrid) ─────────────────────
    final readings = _readAnswersHybrid(
      binary,
      grayEnhanced,
      template,
      layout,
      dpi,
    );

    final responses = <String, String>{};
    for (final r in readings) {
      if (r.detectedAnswer != '?') {
        responses[r.itemNumber.toString()] = r.detectedAnswer;
      }
    }

    final gr = grade(responses, template.answerKey);
    sw.stop();

    final flagged = readings
        .where((r) => r.isAmbiguous)
        .map((r) => r.itemNumber)
        .toList();
    final reasons = <String>[];
    final idPartial = studentId != null && studentId.contains('?');
    if (!alignmentOk) reasons.add('Page alignment weak');
    if (studentId == null || idPartial) reasons.add('Student ID incomplete');
    if (flagged.isNotEmpty) {
      reasons.add('${flagged.length} ambiguous item(s)');
    }
    if (resolvedAssessmentId != null &&
        template.assessmentId != null &&
        resolvedAssessmentId != template.assessmentId) {
      reasons.add('Assessment QR mismatch');
    }

    return OmrResult(
      studentIdentifier: studentId,
      assessmentId: resolvedAssessmentId,
      responses: responses,
      readings: readings,
      correctCount: gr.$1,
      maxScore: gr.$2,
      scorePercent: gr.$3,
      isFlagged: reasons.isNotEmpty,
      flagReason: reasons.isEmpty ? null : reasons.join('; '),
      flaggedItems: flagged,
      processingTime: sw.elapsed,
    );
  }

  // ── ID bubbles (mask fill on Otsu binary) ──────────────────────────────

  static String? _readIDBubblesHybrid(
    img.Image binary,
    Map<String, dynamic> layout,
    double dpi,
  ) {
    final idc = layout['id_columns'] as Map<String, dynamic>?;
    if (idc == null) return null;

    final x0mm = (idc['x0_mm'] as num).toDouble();
    final yTopMm = (idc['y_top_spec_mm'] as num).toDouble();
    final cols = (idc['num_cols'] as num?)?.toInt() ?? 8;
    final colPitch = (idc['col_pitch_mm'] as num).toDouble();
    final rowPitch = (idc['row_pitch_mm'] as num).toDouble();
    final rMm = (idc['bubble_r_mm'] as num?)?.toDouble() ?? 1.5;
    final rPx = OmrImaging.mmToPx(rMm, dpi);
    // PDF draws first row at y_top + 2.5mm
    const firstRowOffsetMm = 2.5;
    final labels = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-'];

    final allColumnFills = <List<double>>[];
    for (int c = 0; c < cols; c++) {
      final cx = OmrImaging.mmToPx(x0mm + c * colPitch, dpi);
      final fills = <double>[];
      for (int r = 0; r < labels.length; r++) {
        final cy = OmrImaging.mmToPx(
          yTopMm + firstRowOffsetMm + r * rowPitch,
          dpi,
        );
        final refined = OmrImaging.refineBubbleCenter(binary, cx, cy, rPx);
        fills.add(OmrImaging.maskFillRatio(binary, refined.$1, refined.$2, rPx));
      }
      allColumnFills.add(fills);
    }

    final allFills = <double>[];
    for (final cf in allColumnFills) {
      allFills.addAll(cf);
    }
    final (globalThr, _) = _largestGapThreshold(allFills, 0.40);

    final buf = StringBuffer();
    for (final fills in allColumnFills) {
      final (localThr, _) = _largestGapThreshold(fills, globalThr);
      double bestFill = 0;
      int bestRow = -1;
      for (int r = 0; r < fills.length; r++) {
        if (fills[r] > bestFill) {
          bestFill = fills[r];
          bestRow = r;
        }
      }
      if (bestRow != -1 && bestFill >= localThr) {
        buf.write(labels[bestRow]);
      } else {
        buf.write('?');
      }
    }
    return buf.toString();
  }

  // ── Answer bubbles (mask-primary hybrid) ───────────────────────────────

  static List<BubbleReading> _readAnswersHybrid(
    img.Image binary,
    img.Image gray,
    BubbleTemplate template,
    Map<String, dynamic> layout,
    double dpi,
  ) {
    final grid = layout['answer_grid'] as Map<String, dynamic>? ?? {};
    final bubbleRmm = (grid['bubble_r_mm'] as num?)?.toDouble() ?? 2.0;
    final bubbleR = OmrImaging.mmToPx(bubbleRmm, dpi);
    // Slightly shrink sampling radius so ring outline is not counted as fill
    final sampleR = max(2, (bubbleR * 0.85).round());

    final items = layout['items'] as Map<String, dynamic>? ?? {};
    final choices =
        List.generate(template.numChoices, (i) => String.fromCharCode(65 + i));

    final rawResults = <_RawItem>[];
    final allMaskFills = <double>[];

    for (int i = 1; i <= template.totalItems; i++) {
      final item = items[i.toString()] as Map<String, dynamic>?;
      if (item == null) {
        rawResults.add(_RawItem.empty(i));
        continue;
      }

      double bestH = -1, secondH = -1;
      var bestChoice = '?';
      var bestMask = 0.0;
      var secondMask = 0.0;
      var bestFeature = 0.0;
      var secondFeature = 0.0;
      final perMask = <double>[];
      final perFeature = <double>[];
      final perFeatures = <int, BubbleFeatures>{};

      for (int ci = 0; ci < choices.length; ci++) {
        final ch = choices[ci];
        final coord = item[ch] as Map<String, dynamic>?;
        if (coord == null) {
          perMask.add(0);
          perFeature.add(0);
          continue;
        }

        final cxMm = (coord['cx_mm'] as num?)?.toDouble() ?? 0;
        final cyMm = (coord['cy_spec_mm'] as num?)?.toDouble() ?? 0;
        var cx = OmrImaging.mmToPx(cxMm, dpi);
        var cy = OmrImaging.mmToPx(cyMm, dpi);

        final refined = OmrImaging.refineBubbleCenter(binary, cx, cy, sampleR);
        cx = refined.$1;
        cy = refined.$2;

        final maskFill = OmrImaging.maskFillRatio(binary, cx, cy, sampleR);
        perMask.add(maskFill);
        allMaskFills.add(maskFill);

        final features = OmrImaging.sampleBubbleFeatures(gray, cx, cy, bubbleR);
        perFeatures[ci] = features;
        final featScore = OmrClassifier.computeFillScore(features);
        perFeature.add(featScore);

        final hybrid = maskWeight * maskFill + featureWeight * featScore;
        if (hybrid > bestH) {
          secondH = bestH;
          secondMask = bestMask;
          secondFeature = bestFeature;
          bestH = hybrid;
          bestMask = maskFill;
          bestFeature = featScore;
          bestChoice = ch;
        } else if (hybrid > secondH) {
          secondH = hybrid;
          secondMask = maskFill;
          secondFeature = featScore;
        }
      }

      rawResults.add(_RawItem(
        itemNumber: i,
        scores: List.generate(
          choices.length,
          (ci) => maskWeight * perMask[ci] + featureWeight * perFeature[ci],
        ),
        fillRatios: perMask,
        bestChoice: bestChoice,
        bestScore: bestH < 0 ? 0 : bestH,
        bestFill: bestMask,
        secondScore: secondH < 0 ? 0 : secondH,
        secondFill: secondMask,
        features: perFeatures,
        bestFeatureScore: bestFeature,
        secondFeatureScore: secondFeature,
      ));
    }

    final (maskThrLG, _) = _largestGapThreshold(allMaskFills, 0.35);
    final maskThrOtsu = OmrImaging.otsuThreshold(allMaskFills, 0.35);
    final scoreThr = max(maskThrLG, maskThrOtsu);

    final allStdDevs = <double>[];
    for (final raw in rawResults) {
      if (raw.scores.length >= 2) allStdDevs.add(_stdDev(raw.scores));
    }
    final (globalStdThr, _) = _largestGapThreshold(allStdDevs, 0.05);

    final results = <BubbleReading>[];
    for (final raw in rawResults) {
      if (raw.scores.isEmpty) {
        results.add(BubbleReading(
          itemNumber: raw.itemNumber,
          detectedAnswer: '?',
          fillRatio: 0,
          isAmbiguous: true,
          isConfirmed: false,
          confidenceNote: 'No layout data',
          confidenceScore: 0,
        ));
        continue;
      }

      final bestIdx = choices.indexOf(raw.bestChoice);
      final bestFeatures = (bestIdx >= 0 && raw.features != null)
          ? raw.features![bestIdx]
          : null;

      final localStdDev = _stdDev(raw.scores);
      final noOutliers = localStdDev < globalStdThr;
      final (localThr, maxGap) = _largestGapThreshold(raw.scores, scoreThr);

      final isGlare =
          bestFeatures != null && bestFeatures.glareProbability > 0.70;
      final isErasure =
          bestFeatures != null && bestFeatures.erasureProbability > 0.60;

      double effectiveThr;
      bool lowConfidence = false;
      String thresholdSource;

      if (maxGap < minGap) {
        effectiveThr = scoreThr;
        lowConfidence = true;
        thresholdSource = 'global';
      } else if (maxGap < minJump && !noOutliers) {
        effectiveThr = max(localThr, scoreThr - hysteresisMargin);
        lowConfidence = true;
        thresholdSource = 'hysteresis';
      } else if (noOutliers) {
        effectiveThr = scoreThr;
        lowConfidence = true;
        thresholdSource = 'global';
      } else {
        effectiveThr = max(localThr, scoreThr - hysteresisMargin);
        thresholdSource = 'local';
      }

      final aboveEffective = raw.bestScore >= effectiveThr;
      final aboveGlobal = raw.bestScore >= (scoreThr - hysteresisMargin);
      final passesHysteresis = (aboveEffective && aboveGlobal) && !isGlare;
      final erasureAmbiguous =
          isErasure && raw.bestScore < scoreThr + 0.10;

      final isAmbiguous = !passesHysteresis ||
          (raw.bestScore - raw.secondScore).abs() < marginFill ||
          lowConfidence ||
          erasureAmbiguous;
      final isConfirmed = !isAmbiguous && raw.bestFill >= goodFill;

      double confidence;
      if (isAmbiguous) {
        confidence = 0.3;
      } else if (isGlare) {
        confidence = 0.1;
      } else if (isErasure) {
        confidence = 0.4;
      } else {
        final margin = (raw.bestScore - effectiveThr).abs();
        confidence = 0.5 + (margin * 1.5).clamp(0.0, 0.5);
      }

      String note;
      if (isAmbiguous) {
        if (isGlare) {
          note =
              'Glare artifact (glare=${bestFeatures.glareProbability.toStringAsFixed(2)})';
        } else if (erasureAmbiguous) {
          note =
              'Possible erasure (erasure=${bestFeatures.erasureProbability.toStringAsFixed(2)})';
        } else if (noOutliers) {
          note =
              'No outliers (all scores ~${raw.bestScore.toStringAsFixed(2)})';
        } else if (!aboveEffective) {
          note =
              'Low fill (${raw.bestFill.toStringAsFixed(2)} hybrid ${raw.bestScore.toStringAsFixed(2)} vs ${effectiveThr.toStringAsFixed(2)})';
        } else if (!aboveGlobal) {
          note =
              'Below global thr (${(scoreThr - hysteresisMargin).toStringAsFixed(2)})';
        } else if (lowConfidence) {
          note =
              'Low confidence ($thresholdSource, gap ${maxGap.toStringAsFixed(2)})';
        } else {
          note =
              'Too close (${raw.bestScore.toStringAsFixed(2)} vs ${raw.secondScore.toStringAsFixed(2)})';
        }
      } else {
        final qual = isConfirmed ? 'Confirmed' : 'Acceptable';
        note =
            '$qual (mask=${raw.bestFill.toStringAsFixed(2)}, hybrid=${raw.bestScore.toStringAsFixed(2)}, $thresholdSource)';
      }

      results.add(BubbleReading(
        itemNumber: raw.itemNumber,
        detectedAnswer: isAmbiguous ? '?' : raw.bestChoice,
        fillRatio: raw.bestFill,
        secondFillRatio: raw.secondFill,
        isAmbiguous: isAmbiguous,
        isConfirmed: isConfirmed,
        confidenceNote: note,
        glareProbability: bestFeatures?.glareProbability ?? 0,
        erasureProbability: bestFeatures?.erasureProbability ?? 0,
        confidenceScore: confidence.clamp(0.0, 1.0),
        features: bestFeatures?.toJson(),
      ));
    }

    return results;
  }

  static (double, double) _largestGapThreshold(
    List<double> fills,
    double fallback,
  ) {
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
    final variance = values
            .map((f) => (f - mean) * (f - mean))
            .reduce((a, b) => a + b) /
        values.length;
    return variance > 0 ? sqrt(variance) : 0;
  }

  static (int, int, double) grade(
    Map<String, String> responses,
    Map<String, String> answerKey,
  ) {
    if (answerKey.isEmpty) return (0, 0, 0.0);
    int correct = 0;
    final maxScore = answerKey.length;
    for (final entry in answerKey.entries) {
      if (responses[entry.key] == entry.value) correct++;
    }
    final pct = maxScore > 0 ? (correct / maxScore) * 100.0 : 0.0;
    return (correct, maxScore, pct);
  }
}

class _RawItem {
  final int itemNumber;
  final List<double> scores;
  final List<double> fillRatios;
  final String bestChoice;
  final double bestScore;
  final double bestFill;
  final double secondScore;
  final double secondFill;
  final Map<int, BubbleFeatures>? features;
  final double bestFeatureScore;
  final double secondFeatureScore;

  _RawItem({
    required this.itemNumber,
    required this.scores,
    required this.fillRatios,
    required this.bestChoice,
    required this.bestScore,
    required this.bestFill,
    required this.secondScore,
    required this.secondFill,
    this.features,
    this.bestFeatureScore = 0,
    this.secondFeatureScore = 0,
  });

  factory _RawItem.empty(int itemNumber) => _RawItem(
        itemNumber: itemNumber,
        scores: const [],
        fillRatios: const [],
        bestChoice: '?',
        bestScore: 0,
        bestFill: 0,
        secondScore: 0,
        secondFill: 0,
      );
}
