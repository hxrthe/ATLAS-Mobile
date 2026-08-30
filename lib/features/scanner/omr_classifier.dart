import 'dart:math';
import 'package:image/image.dart' as img;

/// Multi-feature bubble classification engine.
///
/// Inspired by ZipGrade's SVM-based approach, this engine extracts 7 features
/// per bubble region and computes a weighted fill-confidence score that is far
/// more robust than simple luminance thresholding. It also detects glare
/// artifacts and erasure marks — two of the most common sources of OMR errors.
///
/// Feature vector (7 dimensions):
///   F1 — Fill ratio: fraction of pixels below luminance threshold
///   F2 — Edge density: Sobel edge magnitude inside bubble, normalised 0–1
///   F3 — Mean intensity: average inverted luminance (0=white, 1=black)
///   F4 — Intensity variance: std-dev of luminance (texture / fill roughness)
///   F5 — Ring ratio: contrast between inner 60% and outer 40% ring
///   F6 — Background contrast: bubble interior vs surrounding band
///   F7 — Boundary gradient: edge strength at the bubble perimeter
class OmrClassifier {
  // ── Feature extraction weights (empirically derived, mirror SVM emphasis) ─
  // Higher weight = feature contributes more to the fill-confidence score.
  static const double _wFillRatio       = 0.30;
  static const double _wMeanIntensity   = 0.22;
  static const double _wEdgeDensity     = 0.15;
  static const double _wBoundaryGrad    = 0.12;
  static const double _wBackgroundCont  = 0.10;
  static const double _wRingRatio       = 0.06;
  static const double _wVariance        = 0.05;

  // ── Glare detection thresholds ──────────────────────────────────────────
  // Glare = bright specular highlights that look "filled" to simple threshold
  // but are actually reflections. Key indicator: HIGH mean intensity (bright)
  // despite high fill ratio (because luminance gets inverted).
  static const double _glareMeanIntensityMin = 0.65; // > 0.65 inverted = actually bright
  static const double _glareVarianceMin      = 0.12; // high variance = specular
  static const double _glareFillMin          = 0.40; // must also have decent fill to fool us

  // ── Erasure detection thresholds ────────────────────────────────────────
  // Erasure = pencil was filled then erased. Moderate fill + messy edges.
  static const double _erasureFillMin     = 0.12;
  static const double _erasureFillMax     = 0.35;
  static const double _erasureEdgeMin     = 0.30;
  static const double _erasureVarianceMin = 0.08;

  // ── Luminance thresholds ────────────────────────────────────────────────
  static const int _darkThreshold = 100;  // luminance below this = dark pixel
  static const int _glareBrightThreshold = 200; // luminance above this = bright/glare pixel

  /// Extract all 7 features for a bubble at (cx, cy) with radius [r] in [image].
  /// Returns a [BubbleFeatures] struct and a pre-computed glare probability.
  static BubbleFeatures extractFeatures(img.Image image, int cx, int cy, int r) {
    if (r < 3) return BubbleFeatures.zero();

    final w = image.width;
    final h = image.height;

    // ── Gather all pixels in the bubble circle ────────────────────────────
    final pixels = <int>[];   // luminance values
    int total = 0;
    int darkCount = 0;
    int brightCount = 0;

    // Also sample the surrounding band (r+2 to r+6) for background contrast
    final bgPixels = <int>[];
    final innerR = (r * 0.6).round(); // inner 60% for ring ratio
    final innerPixels = <int>[];
    final outerRingPixels = <int>[];

    for (int dy = -r - 6; dy <= r + 6; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= h) continue;

      for (int dx = -r - 6; dx <= r + 6; dx++) {
        final x = cx + dx;
        if (x < 0 || x >= w) continue;

        final dist = sqrt(dx * dx + dy * dy);
        final lum = img.getLuminance(image.getPixel(x, y)).toInt();

        if (dist <= r) {
          total++;
          pixels.add(lum);
          if (lum < _darkThreshold) darkCount++;
          if (lum > _glareBrightThreshold) brightCount++;

          if (dist <= innerR) {
            innerPixels.add(lum);
          } else {
            outerRingPixels.add(lum);
          }
        } else if (dist <= r + 6 && dist > r + 2) {
          bgPixels.add(lum);
        }
      }
    }

    if (total == 0) return BubbleFeatures.zero();

    // ── F1: Fill ratio ────────────────────────────────────────────────────
    final fillRatio = darkCount / total;

    // ── F2: Edge density inside bubble ────────────────────────────────────
    final edgeDensity = _computeEdgeDensity(image, cx, cy, r, pixels);

    // ── F3: Mean intensity (inverted: 0=white, 1=black) ───────────────────
    final meanLum = pixels.reduce((a, b) => a + b) / pixels.length;
    final meanIntensity = 1.0 - (meanLum / 255.0); // invert so dark=1.0

    // ── F4: Intensity variance (normalised 0-1) ───────────────────────────
    final variance = _computeVariance(pixels, meanLum) / (128.0 * 128.0); // normalise
    final varianceNorm = variance.clamp(0.0, 1.0);

    // ── F5: Ring ratio (inner vs outer contrast) ──────────────────────────
    final ringRatio = _computeRingRatio(innerPixels, outerRingPixels);

    // ── F6: Background contrast ───────────────────────────────────────────
    final bgContrast = _computeBgContrast(pixels, bgPixels);

    // ── F7: Boundary gradient ─────────────────────────────────────────────
    final boundaryGrad = _computeBoundaryGradient(image, cx, cy, r);

    // ── Glare probability ─────────────────────────────────────────────────
    final glareProb = _computeGlareProbability(
      fillRatio, meanIntensity, varianceNorm, brightCount, total);

    // ── Erasure probability ───────────────────────────────────────────────
    final erasureProb = _computeErasureProbability(
      fillRatio, edgeDensity, varianceNorm);

    return BubbleFeatures(
      fillRatio: fillRatio,
      edgeDensity: edgeDensity,
      meanIntensity: meanIntensity,
      variance: varianceNorm,
      ringRatio: ringRatio,
      backgroundContrast: bgContrast,
      boundaryGradient: boundaryGrad,
      glareProbability: glareProb,
      erasureProbability: erasureProb,
    );
  }

  /// Compute a weighted fill-confidence score (0.0–1.0) from all 7 features.
  /// Higher = more likely genuinely filled (not glare, not erasure, not noise).
  ///
  /// The score combines features with weights that mirror what an SVM would
  /// learn: fill ratio and mean intensity dominate, edges and boundary provide
  /// confirmation, ring ratio and variance penalise anomalies.
  static double computeFillScore(BubbleFeatures f) {
    // Start with weighted contribution from each feature
    double score = 0.0;

    // F1: Fill ratio — direct contribution
    score += _wFillRatio * f.fillRatio;

    // F2: Edge density — moderate edge density is good (pencil marks have texture)
    //     Too low = blank, too high = noise/glare
    final edgeScore = f.edgeDensity < 0.45
        ? f.edgeDensity / 0.45  // ramp up to 0.45
        : 1.0 - (f.edgeDensity - 0.45).clamp(0.0, 0.55) / 0.55; // ramp down after
    score += _wEdgeDensity * edgeScore;

    // F3: Mean intensity — direct (darker = more filled)
    score += _wMeanIntensity * f.meanIntensity;

    // F4: Variance — moderate variance is expected from pencil fill
    //     Too low = blank paper, too high = glare/erasure
    final varScore = f.variance < 0.20
        ? f.variance / 0.20
        : 1.0 - ((f.variance - 0.20) / 0.80).clamp(0.0, 1.0);
    score += _wVariance * varScore;

    // F5: Ring ratio — low ring ratio = solid fill, high = just an outline
    final ringScore = 1.0 - f.ringRatio.clamp(0.0, 1.0);
    score += _wRingRatio * ringScore;

    // F6: Background contrast — higher contrast = bubble is distinctly darker
    final bgScore = f.backgroundContrast.clamp(0.0, 1.0);
    score += _wBackgroundCont * bgScore;

    // F7: Boundary gradient — sharp boundary confirms real bubble
    final boundaryScore = f.boundaryGradient.clamp(0.0, 1.0);
    score += _wBoundaryGrad * boundaryScore;

    return score.clamp(0.0, 1.0);
  }

  /// Determine if a bubble is genuinely filled based on the fill score and
  /// glare/erasure probabilities.
  ///
  /// Returns a [ClassificationResult] with the decision reasoning.
  static ClassificationResult classify(BubbleFeatures f, {
    double fillScoreThreshold = 0.38,
  }) {
    final fillScore = computeFillScore(f);

    // Glare rejection: if glare probability is high, treat as NOT filled
    final isGlare = f.glareProbability > 0.70;

    // Erasure: flag but don't necessarily reject (let thresholding decide)
    final isErasure = f.erasureProbability > 0.60;

    // Determine fill status
    bool isFilled;
    String reason;

    if (isGlare && fillScore > fillScoreThreshold) {
      // Glare masquerading as fill — reject
      isFilled = false;
      reason = 'Glare artifact (glare=${f.glareProbability.toStringAsFixed(2)})';
    } else if (isErasure && fillScore < fillScoreThreshold + 0.10) {
      // Erasure with borderline score — reject
      isFilled = false;
      reason = 'Possible erasure (erasure=${f.erasureProbability.toStringAsFixed(2)})';
    } else if (fillScore >= fillScoreThreshold) {
      isFilled = true;
      if (isErasure) {
        reason = 'Filled (erasure present, score=${fillScore.toStringAsFixed(2)})';
      } else if (f.glareProbability > 0.30) {
        reason = 'Filled (minor glare, score=${fillScore.toStringAsFixed(2)})';
      } else {
        reason = 'Filled (score=${fillScore.toStringAsFixed(2)})';
      }
    } else {
      isFilled = false;
      reason = 'Empty (score=${fillScore.toStringAsFixed(2)} < $fillScoreThreshold)';
    }

    // Confidence: how certain we are in this classification
    // High confidence = score far from threshold, no glare/erasure ambiguity
    final margin = (fillScore - fillScoreThreshold).abs();
    double confidence = margin * 2.0; // map 0-0.5 margin to 0-1.0 confidence
    if (isGlare) confidence = min(confidence, 0.4); // glare always reduces confidence
    if (isErasure) confidence = min(confidence, 0.5); // erasure reduces confidence
    confidence = confidence.clamp(0.0, 1.0);

    return ClassificationResult(
      isFilled: isFilled,
      fillScore: fillScore,
      confidence: confidence,
      isGlare: isGlare,
      isErasure: isErasure,
      reason: reason,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Private feature extractors
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sobel edge density inside the bubble circle. Normalised 0–1.
  static double _computeEdgeDensity(img.Image image, int cx, int cy, int r,
      List<int> pixels) {
    // Use a lightweight Laplacian approximation at sampled points
    double edgeSum = 0;
    int samples = 0;
    final step = max(1, r ~/ 3);

    for (int dy = -r + 1; dy <= r - 1; dy += step) {
      for (int dx = -r + 1; dx <= r - 1; dx += step) {
        if (dx * dx + dy * dy > r * r) continue;
        final x = cx + dx;
        final y = cy + dy;
        if (x < 1 || y < 1 || x >= image.width - 1 || y >= image.height - 1) continue;

        final c = img.getLuminance(image.getPixel(x, y)).toInt();
        final l = img.getLuminance(image.getPixel(x - 1, y)).toInt();
        final ri = img.getLuminance(image.getPixel(x + 1, y)).toInt();
        final u = img.getLuminance(image.getPixel(x, y - 1)).toInt();
        final d = img.getLuminance(image.getPixel(x, y + 1)).toInt();

        // Laplacian magnitude
        final lap = (4 * c - l - ri - u - d).abs();
        edgeSum += lap;
        samples++;
      }
    }

    if (samples == 0) return 0;
    // Normalise: max possible Laplacian is ~1020 (4*255 - 4*0), practical max ~200
    return (edgeSum / samples / 200.0).clamp(0.0, 1.0);
  }

  static double _computeVariance(List<int> pixels, double mean) {
    if (pixels.length < 2) return 0;
    double sumSq = 0;
    for (final p in pixels) {
      final diff = p - mean;
      sumSq += diff * diff;
    }
    return sumSq / pixels.length;
  }

  /// Ring ratio: how much darker the outer ring is vs inner core.
  /// Low ratio (inner ≈ outer) = solid fill. High ratio (outer darker than inner) = ring/outline.
  static double _computeRingRatio(List<int> inner, List<int> outer) {
    if (inner.isEmpty || outer.isEmpty) return 0;
    final innerMean = inner.reduce((a, b) => a + b) / inner.length;
    final outerMean = outer.reduce((a, b) => a + b) / outer.length;
    // Positive when outer is darker than inner (ring effect)
    final diff = (innerMean - outerMean) / 255.0;
    return diff.clamp(0.0, 1.0);
  }

  /// Background contrast: how much darker the bubble interior is compared to
  /// the surrounding band. Higher = bubble stands out from paper.
  static double _computeBgContrast(List<int> bubblePixels, List<int> bgPixels) {
    if (bubblePixels.isEmpty || bgPixels.isEmpty) return 0;
    final bubbleMean = bubblePixels.reduce((a, b) => a + b) / bubblePixels.length;
    final bgMean = bgPixels.reduce((a, b) => a + b) / bgPixels.length;
    // Higher when bubble is darker than background
    final diff = (bgMean - bubbleMean) / 255.0;
    return diff.clamp(0.0, 1.0);
  }

  /// Boundary gradient: average edge strength at 8 sample points around the
  /// bubble perimeter. High boundary gradient = clear bubble edge.
  static double _computeBoundaryGradient(img.Image image, int cx, int cy, int r) {
    if (r < 3) return 0;
    double gradSum = 0;
    int samples = 0;

    // Sample 8 equally-spaced points around the perimeter
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final px = (cx + r * cos(angle)).round();
      final py = (cy + r * sin(angle)).round();
      if (px < 2 || py < 2 || px >= image.width - 2 || py >= image.height - 2) continue;

      // Compute radial gradient: difference between inner and outer point
      final innerX = (cx + (r - 2) * cos(angle)).round();
      final innerY = (cy + (r - 2) * sin(angle)).round();
      final outerX = (cx + (r + 2) * cos(angle)).round();
      final outerY = (cy + (r + 2) * sin(angle)).round();

      if (innerX < 0 || innerY < 0 || innerX >= image.width || innerY >= image.height) continue;
      if (outerX < 0 || outerY < 0 || outerX >= image.width || outerY >= image.height) continue;

      final innerLum = img.getLuminance(image.getPixel(innerX, innerY)).toInt();
      final outerLum = img.getLuminance(image.getPixel(outerX, outerY)).toInt();
      gradSum += (outerLum - innerLum).abs();
      samples++;
    }

    if (samples == 0) return 0;
    return (gradSum / samples / 255.0).clamp(0.0, 1.0);
  }

  /// Glare probability based on feature combination.
  /// Glare = high fill (dark pixels from threshold) BUT high mean intensity
  /// (actually bright pixels — contradiction means specular reflection).
  static double _computeGlareProbability(double fillRatio, double meanIntensity,
      double variance, int brightCount, int total) {
    if (total == 0) return 0;
    final brightRatio = brightCount / total;
    double prob = 0.0;

    // Factor 1: High fill but high mean intensity = glare contradiction
    if (fillRatio > _glareFillMin && meanIntensity > _glareMeanIntensityMin) {
      prob += 0.40;
    }

    // Factor 2: High variance = specular sparkle pattern
    if (variance > _glareVarianceMin) {
      prob += 0.30;
    }

    // Factor 3: Many bright pixels inside bubble
    if (brightRatio > 0.25) {
      prob += 0.30;
    }

    return prob.clamp(0.0, 1.0);
  }

  /// Erasure probability: moderate fill + messy edges = likely erasure.
  static double _computeErasureProbability(double fillRatio, double edgeDensity,
      double variance) {
    double prob = 0.0;

    // Factor 1: Fill in the erasure range
    if (fillRatio >= _erasureFillMin && fillRatio <= _erasureFillMax) {
      prob += 0.40;
    } else if (fillRatio > _erasureFillMax && fillRatio < 0.50) {
      prob += 0.20; // borderline
    }

    // Factor 2: High edge density from erased pencil residue
    if (edgeDensity > _erasureEdgeMin) {
      prob += 0.35;
    }

    // Factor 3: Moderate variance from uneven erasure
    if (variance > _erasureVarianceMin) {
      prob += 0.25;
    }

    return prob.clamp(0.0, 1.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Otsu's threshold method — for global threshold alternatives
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compute Otsu's threshold for a list of values.
  /// Returns the optimal threshold that minimises intra-class variance.
  /// Falls back to [fallback] if values are too uniform.
  static double otsuThreshold(List<double> values, double fallback) {
    if (values.length < 2) return fallback;

    // Bin values into 256 levels (0.0–1.0 mapped to 0–255)
    final hist = List<int>.filled(256, 0);
    for (final v in values) {
      final bin = (v * 255).round().clamp(0, 255);
      hist[bin]++;
    }

    final total = values.length;
    double sumAll = 0;
    for (int i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }

    double sumB = 0;
    int wB = 0;
    double maxVar = 0;
    double bestThr = fallback;

    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;

      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;

      final varBetween = wB * wF * (mB - mF) * (mB - mF);
      if (varBetween > maxVar) {
        maxVar = varBetween;
        bestThr = t / 255.0;
      }
    }

    return bestThr;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Data classes
// ═════════════════════════════════════════════════════════════════════════════

/// 7-feature vector extracted from a single bubble region.
class BubbleFeatures {
  final double fillRatio;        // F1: 0–1, fraction of dark pixels
  final double edgeDensity;      // F2: 0–1, normalised edge magnitude inside bubble
  final double meanIntensity;    // F3: 0–1, inverted mean luminance (1=black)
  final double variance;         // F4: 0–1, normalised intensity variance
  final double ringRatio;        // F5: 0–1, inner vs outer ring contrast
  final double backgroundContrast; // F6: 0–1, bubble vs surround contrast
  final double boundaryGradient; // F7: 0–1, edge strength at bubble perimeter
  final double glareProbability; // 0–1, likelihood this is a glare artifact
  final double erasureProbability; // 0–1, likelihood this is an erasure

  const BubbleFeatures({
    this.fillRatio = 0,
    this.edgeDensity = 0,
    this.meanIntensity = 0,
    this.variance = 0,
    this.ringRatio = 0,
    this.backgroundContrast = 0,
    this.boundaryGradient = 0,
    this.glareProbability = 0,
    this.erasureProbability = 0,
  });

  factory BubbleFeatures.zero() => const BubbleFeatures();

  Map<String, double> toJson() => {
    'fill_ratio': fillRatio,
    'edge_density': edgeDensity,
    'mean_intensity': meanIntensity,
    'variance': variance,
    'ring_ratio': ringRatio,
    'background_contrast': backgroundContrast,
    'boundary_gradient': boundaryGradient,
    'glare_probability': glareProbability,
    'erasure_probability': erasureProbability,
  };
}

/// Result of classifying a single bubble.
class ClassificationResult {
  final bool isFilled;
  final double fillScore;    // 0–1 weighted feature score
  final double confidence;   // 0–1 confidence in the classification
  final bool isGlare;
  final bool isErasure;
  final String reason;

  const ClassificationResult({
    required this.isFilled,
    required this.fillScore,
    required this.confidence,
    this.isGlare = false,
    this.isErasure = false,
    this.reason = '',
  });
}