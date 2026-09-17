/// Shared OMR constants — keep in sync with
/// `atlas-dev/backend/apps/grading/services/omr_core.py`.
class OmrConstants {
  static const double targetDpi = 300;
  static const double fidInsetMm = 5.0;
  static const double fidSizeMm = 15.0;
  static const double headerMm = 50.8;
  static const double fidSpanMm = 254.0;
  static const double contentBotMm = headerMm + fidSpanMm - fidSizeMm; // 289.8
  static const double pageWmm = 215.9;
  static const double pageHmm = 330.2;

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
