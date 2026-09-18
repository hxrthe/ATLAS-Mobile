/// Shared OMR constants — keep in sync with
/// `atlas-dev/backend/apps/grading/services/omr_core.py`.
class OmrConstants {
  /// Layout / PDF authoring DPI (bubble mm metadata assumes this).
  static const double targetDpi = 300;

  /// On-device grading warp DPI — 200 matches research speed/accuracy sweet spot.
  static const double gradingDpi = 200;

  static const double fidInsetMm = 5.0;
  static const double fidSizeMm = 15.0;
  static const double headerMm = 50.8;
  static const double fidSpanMm = 254.0;
  static const double contentBotMm = headerMm + fidSpanMm - fidSizeMm; // 289.8
  static const double pageWmm = 215.9;
  static const double pageHmm = 330.2;

  /// Margin beyond each ArUco square so the full marker stays in frame.
  static const double cropPadMm = 3.0;

  static double get fidCenterInsetMm => fidInsetMm + fidSizeMm / 2;
  static double get fidCenterTopMm => headerMm + fidSizeMm / 2;
  static double get fidCenterBotMm => contentBotMm + fidSizeMm / 2;
  static double get cropEdgeToCenterMm => fidSizeMm / 2 + cropPadMm;
  static double get cropOriginXmm => fidCenterInsetMm - cropEdgeToCenterMm;
  static double get cropOriginYmm => fidCenterTopMm - cropEdgeToCenterMm;
  static double get cropWmm =>
      (pageWmm - 2 * fidCenterInsetMm) + 2 * cropEdgeToCenterMm;
  static double get cropHmm =>
      (fidCenterBotMm - fidCenterTopMm) + 2 * cropEdgeToCenterMm;
  static double get cropAspect => cropWmm / cropHmm;

  /// Map a full-page normalized point onto the ArUco-padded crop.
  static (double, double) pageNormToCropNorm(double nx, double ny) {
    final xMm = nx * pageWmm;
    final yMm = ny * pageHmm;
    return (
      ((xMm - cropOriginXmm) / cropWmm).clamp(0.0, 1.0),
      ((yMm - cropOriginYmm) / cropHmm).clamp(0.0, 1.0),
    );
  }

  static const double innerFillRatio = 0.62;
  static const double markFloor = 0.18;
  static const double blankCeiling = 0.12;
  static const double zScoreMark = 1.2;
  static const double gapMark = 0.10;
  static const double doubleGap = 0.08;
  static const double matchTemplateMin = 0.55;
  static const double searchWindowMm = 6.0;

  /// DICT_4X4_50 inner 4×4 bits (1 = white, 0 = black). IDs 0–3.
  static const Map<int, List<List<int>>> arucoInner = {
    0: [
      [1, 0, 1, 1],
      [0, 1, 0, 1],
      [0, 0, 1, 1],
      [0, 0, 1, 0],
    ],
    1: [
      [0, 0, 0, 0],
      [1, 1, 1, 1],
      [1, 0, 0, 1],
      [1, 0, 1, 0],
    ],
    2: [
      [0, 0, 1, 1],
      [0, 0, 1, 1],
      [0, 0, 1, 0],
      [1, 1, 0, 1],
    ],
    3: [
      [1, 0, 0, 1],
      [1, 0, 0, 1],
      [0, 1, 0, 0],
      [0, 1, 1, 0],
    ],
  };

  static const Map<int, String> arucoIdToCorner = {
    0: 'TL',
    1: 'TR',
    2: 'BR',
    3: 'BL',
  };
}
