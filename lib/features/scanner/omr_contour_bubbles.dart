import 'dart:math';
import 'package:image/image.dart' as img;
import 'omr_imaging.dart';
import 'omr_models.dart';

/// One bubble contour on an Otsu-thresholded sheet (ShreenidhiBodas/OMR style).
class DetectedBubble {
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
  final List<(int x, int y)> pixels;

  DetectedBubble({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.pixels,
  });

  double get cx =>
      pixels.isEmpty ? (minX + maxX) / 2.0 : pixels.map((p) => p.$1).reduce((a, b) => a + b) / pixels.length;

  double get cy =>
      pixels.isEmpty ? (minY + maxY) / 2.0 : pixels.map((p) => p.$2).reduce((a, b) => a + b) / pixels.length;

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;

  /// countNonZero inside contour mask on BINARY_INV image (reference: cv2.countNonZero).
  int countNonZero(img.Image binary) {
    var n = 0;
    for (final (x, y) in pixels) {
      if (x < 0 || y < 0 || x >= binary.width || y >= binary.height) continue;
      if (img.getLuminance(binary.getPixel(x, y)) > 128) n++;
    }
    return n;
  }
}

/// Result of reading one answer row via contour fill counts.
class RowReadResult {
  final int itemNumber;
  final String answer;
  final int bestFill;
  final int secondFill;
  final bool ambiguous;

  const RowReadResult({
    required this.itemNumber,
    required this.answer,
    this.bestFill = 0,
    this.secondFill = 0,
    this.ambiguous = false,
  });
}

/// ShreenidhiBodas/OMR pipeline adapted for ATLAS 3-column sheets:
///   Col 1 — assessment QR + student ID bubbles (left zone)
///   Col 2 — answer items (col_a, first half)
///   Col 3 — answer items (col_b, second half)
class OmrReferenceGrader {
  // Reference test_grader.py filters
  static const double minAspect = 0.9;
  static const double maxAspect = 1.1;
  static const int minAnswerBubblePx = 14;
  static const int minIdBubblePx = 10;

  // Match Django bubble_sheet_scanner thresholds.
  static const double _fillThreshold = 0.42;
  static const double _confidenceFloor = 0.28;
  static const double _marginFill = 0.08;

  // ── Template-coordinate reading (primary — uses layout items mm positions) ─

  static List<RowReadResult> readAnswerBubblesFromTemplate(
    img.Image binary,
    img.Image gray,
    Map<String, dynamic> layout,
    double dpi,
    int numChoices,
  ) {
    final items = layout['items'] as Map<String, dynamic>? ?? {};
    if (items.isEmpty) return [];

    final grid = layout['answer_grid'] as Map<String, dynamic>? ?? {};
    final bubbleRMm = (grid['bubble_r_mm'] as num?)?.toDouble() ??
        ((layout['bubble_radius_pt'] as num?) != null
            ? (layout['bubble_radius_pt'] as num).toDouble() * 25.4 / 72.0
            : 2.0);
    final rPx = max(3, (bubbleRMm * dpi / 25.4 * 0.90).round());
    final choices =
        List.generate(numChoices, (i) => String.fromCharCode(65 + i));

    final results = <RowReadResult>[];

    for (final entry in items.entries) {
      final itemNum = int.tryParse(entry.key) ?? 0;
      if (itemNum <= 0) continue;
      final itemData = entry.value as Map<String, dynamic>;

      final fills = <({String choice, double fill})>[];
      for (final ch in choices) {
        final coord = itemData[ch] as Map<String, dynamic>?;
        if (coord == null) continue;
        final cxMm = (coord['cx_mm'] as num?)?.toDouble() ?? 0;
        final cyMm = (coord['cy_spec_mm'] as num?)?.toDouble() ?? 0;
        final cx = OmrImaging.mmToPx(cxMm, dpi);
        final cy = OmrImaging.mmToPx(cyMm, dpi);

        // Grayscale only (Django-style) — no refine/offset that latch onto rings.
        final fill = OmrImaging.sampleCircle(gray, cx, cy, rPx);
        fills.add((choice: ch, fill: fill));
      }

      if (fills.isEmpty) {
        results.add(RowReadResult(
          itemNumber: itemNum,
          answer: '?',
          ambiguous: true,
        ));
        continue;
      }

      fills.sort((a, b) => b.fill.compareTo(a.fill));
      final top = fills.first;
      final secondFill = fills.length >= 2 ? fills[1].fill : 0.0;

      var ambiguous = false;
      if (top.fill < _confidenceFloor) {
        ambiguous = true;
      } else if (fills.length >= 2 && top.fill - secondFill < _marginFill) {
        ambiguous = true;
      }

      final answer = ambiguous
          ? '?'
          : (top.fill >= _fillThreshold ? top.choice : '?');

      results.add(RowReadResult(
        itemNumber: itemNum,
        answer: answer,
        bestFill: (top.fill * 500).round(),
        secondFill: (secondFill * 500).round(),
        ambiguous: ambiguous || answer == '?',
      ));
    }

    results.sort((a, b) => a.itemNumber.compareTo(b.itemNumber));
    return results;
  }

  // ── Step 4: find bubble contours on thresholded warped sheet ───────────

  static List<DetectedBubble> findBubbleContours(
    img.Image binary, {
    int minSize = minAnswerBubblePx,
  }) {
    final w = binary.width;
    final h = binary.height;
    final visited = List.generate(h, (_) => List.filled(w, false));
    final bubbles = <DetectedBubble>[];

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (visited[y][x]) continue;
        if (img.getLuminance(binary.getPixel(x, y)) <= 128) {
          visited[y][x] = true;
          continue;
        }

        var minX = x, maxX = x, minY = y, maxY = y;
        final pixels = <(int, int)>[];
        final q = <(int, int)>[(x, y)];
        visited[y][x] = true;

        while (q.isNotEmpty) {
          final (px, py) = q.removeAt(0);
          pixels.add((px, py));
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;

          for (final d in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nx = px + d.$1;
            final ny = py + d.$2;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (visited[ny][nx]) continue;
            visited[ny][nx] = true;
            if (img.getLuminance(binary.getPixel(nx, ny)) > 128) {
              q.add((nx, ny));
            }
          }
        }

        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        if (bw < minSize || bh < minSize) continue;
        final aspect = bw / bh;
        if (aspect < minAspect || aspect > maxAspect) continue;
        // Skip QR / large printed blocks
        if (bw > w * 0.12 || bh > h * 0.06) continue;

        bubbles.add(DetectedBubble(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          pixels: pixels,
        ));
      }
    }
    return bubbles;
  }

  // ── Sort contours (imutils.sort_contours) ──────────────────────────────

  static List<DetectedBubble> sortTopToBottom(List<DetectedBubble> bubbles) {
    final copy = List<DetectedBubble>.from(bubbles);
    copy.sort((a, b) {
      final dy = a.cy.compareTo(b.cy);
      return dy != 0 ? dy : a.cx.compareTo(b.cx);
    });
    return copy;
  }

  static List<DetectedBubble> sortLeftToRight(List<DetectedBubble> bubbles) {
    final copy = List<DetectedBubble>.from(bubbles);
    copy.sort((a, b) => a.cx.compareTo(b.cx));
    return copy;
  }

  /// Group sorted (top→bottom) bubbles into rows by vertical pitch.
  static List<List<DetectedBubble>> groupIntoRows(
    List<DetectedBubble> sortedTopToBottom,
    double rowPitchPx,
    int expectedChoices,
  ) {
    if (sortedTopToBottom.isEmpty) return [];

    final rows = <List<DetectedBubble>>[];
    var current = <DetectedBubble>[sortedTopToBottom.first];
    var rowCy = sortedTopToBottom.first.cy;

    for (var i = 1; i < sortedTopToBottom.length; i++) {
      final b = sortedTopToBottom[i];
      if ((b.cy - rowCy).abs() > rowPitchPx * 0.55) {
        rows.add(sortLeftToRight(current));
        current = [b];
        rowCy = b.cy;
      } else {
        current.add(b);
        rowCy = (rowCy * (current.length - 1) + b.cy) / current.length;
      }
    }
    if (current.isNotEmpty) rows.add(sortLeftToRight(current));

    // Reference: each row should have [expectedChoices] bubbles
    return rows;
  }

  // ── Step 5–6: pick marked bubble per row (highest countNonZero) ────────

  static RowReadResult readRow(
    List<DetectedBubble> row,
    img.Image binary,
    int itemNumber,
    List<String> choiceLabels,
  ) {
    if (row.isEmpty) {
      return RowReadResult(itemNumber: itemNumber, answer: '?', ambiguous: true);
    }

    // If extra noise bubbles, keep the [numChoices] with highest total fill
    var candidates = row;
    if (row.length > choiceLabels.length) {
      final scored = row
          .map((b) => (bubble: b, fill: b.countNonZero(binary)))
          .toList()
        ..sort((a, b) => b.fill.compareTo(a.fill));
      candidates = scored
          .take(choiceLabels.length)
          .map((e) => e.bubble)
          .toList();
      candidates = sortLeftToRight(candidates);
    }

    var bestIdx = 0;
    var bestFill = -1;
    var secondFill = -1;

    for (var j = 0; j < candidates.length; j++) {
      final fill = candidates[j].countNonZero(binary);
      if (fill > bestFill) {
        secondFill = bestFill;
        bestFill = fill;
        bestIdx = j;
      } else if (fill > secondFill) {
        secondFill = fill;
      }
    }

    if (bestFill <= 0 || bestIdx >= choiceLabels.length) {
      return RowReadResult(
        itemNumber: itemNumber,
        answer: '?',
        bestFill: max(0, bestFill),
        secondFill: max(0, secondFill),
        ambiguous: true,
      );
    }

    final ambiguous = candidates.length >= 2 &&
        secondFill >= 0 &&
        bestFill > 0 &&
        (bestFill - secondFill) < bestFill * 0.15;

    return RowReadResult(
      itemNumber: itemNumber,
      answer: ambiguous ? '?' : choiceLabels[bestIdx],
      bestFill: bestFill,
      secondFill: max(0, secondFill),
      ambiguous: ambiguous || candidates.length < choiceLabels.length,
    );
  }

  // ── Answer columns 2 & 3 (col_a / col_b) ─────────────────────────────

  static List<RowReadResult> readAnswerBubbles(
    img.Image binary,
    Map<String, dynamic> layout,
    double dpi,
    int totalItems,
    int numChoices,
  ) {
    final choices =
        List.generate(numChoices, (i) => String.fromCharCode(65 + i));
    final grid = layout['answer_grid'] as Map<String, dynamic>? ?? {};
    final rowPitchPx =
        OmrImaging.mmToPx((grid['row_pitch_mm'] as num?)?.toDouble() ?? 6.0, dpi)
            .toDouble();

    final all = findBubbleContours(binary, minSize: minAnswerBubblePx);
    final answerZone = _answerZonePx(layout, dpi);

    // Columns 2–3 only (answer region); col_a/col_b zones split horizontally.
    final answerBubbles = all.where((b) {
      return b.cx >= answerZone.left &&
          b.cx <= answerZone.right &&
          b.cy >= answerZone.top &&
          b.cy <= answerZone.bottom;
    }).toList();

    final colA = grid['col_a'] as Map<String, dynamic>?;
    final colB = grid['col_b'] as Map<String, dynamic>?;
    final results = <RowReadResult>[];

    if (colA != null) {
      final zoneA = _answerColumnZonePx(colA, grid, dpi, answerZone);
      final bubbles = answerBubbles.where((b) {
        return b.cx >= zoneA.left && b.cx <= zoneA.right;
      }).toList();
      results.addAll(_readColumn(
        binary,
        bubbles,
        colA,
        rowPitchPx,
        choices,
      ));
    }

    if (colB != null) {
      final zoneB = _answerColumnZonePx(colB, grid, dpi, answerZone);
      final bubbles = answerBubbles.where((b) {
        return b.cx >= zoneB.left && b.cx <= zoneB.right;
      }).toList();
      results.addAll(_readColumn(
        binary,
        bubbles,
        colB,
        rowPitchPx,
        choices,
      ));
    }

    if (colA == null && colB == null) {
      final sorted = sortTopToBottom(answerBubbles);
      final rows = groupIntoRows(sorted, rowPitchPx, numChoices);
      for (var ri = 0; ri < rows.length && ri < totalItems; ri++) {
        results.add(readRow(rows[ri], binary, ri + 1, choices));
      }
    }

    results.sort((a, b) => a.itemNumber.compareTo(b.itemNumber));
    return results;
  }

  static List<RowReadResult> _readColumn(
    img.Image binary,
    List<DetectedBubble> bubbles,
    Map<String, dynamic> colMeta,
    double rowPitchPx,
    List<String> choices,
  ) {
    final startItem = (colMeta['start_item'] as num?)?.toInt() ?? 1;
    final sorted = sortTopToBottom(bubbles);
    final rows = groupIntoRows(sorted, rowPitchPx, choices.length);
    final results = <RowReadResult>[];

    for (var ri = 0; ri < rows.length; ri++) {
      results.add(readRow(
        rows[ri],
        binary,
        startItem + ri,
        choices,
      ));
    }
    return results;
  }

  // ── Column 1: student ID bubble grid (below assessment QR) ─────────────

  static String? readStudentId(
    img.Image binary,
    Map<String, dynamic> layout,
    double dpi,
  ) {
    final idc = layout['id_columns'] as Map<String, dynamic>?;
    if (idc == null) return null;

    final leftZone = _leftZonePx(layout, dpi);
    final yTopMm = (idc['y_top_spec_mm'] as num).toDouble();
    final x0mm = (idc['x0_mm'] as num).toDouble();
    final cols = (idc['num_cols'] as num?)?.toInt() ?? 8;
    final colPitch = (idc['col_pitch_mm'] as num).toDouble();
    final rowPitch = (idc['row_pitch_mm'] as num).toDouble();
    const firstRowOffsetMm = 2.5;
    const labels = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-'];

    final x0px = OmrImaging.mmToPx(x0mm, dpi).toDouble();
    final y0px =
        OmrImaging.mmToPx(yTopMm + firstRowOffsetMm, dpi).toDouble();
    final x1px = OmrImaging.mmToPx(x0mm + cols * colPitch, dpi).toDouble();
    final y1px = OmrImaging.mmToPx(
      yTopMm + firstRowOffsetMm + labels.length * rowPitch,
      dpi,
    ).toDouble();
    final colPitchPx = OmrImaging.mmToPx(colPitch, dpi).toDouble();
    final rowPitchPx = OmrImaging.mmToPx(rowPitch, dpi).toDouble();

    final all = findBubbleContours(binary, minSize: minIdBubblePx);
    final idBubbles = all.where((b) {
      return b.cx >= leftZone.left &&
          b.cx <= leftZone.right &&
          b.cx >= x0px - colPitchPx * 0.4 &&
          b.cx <= x1px + colPitchPx * 0.4 &&
          b.cy >= y0px - rowPitchPx * 0.4 &&
          b.cy <= y1px + rowPitchPx * 0.4;
    }).toList();

    if (idBubbles.isEmpty) return null;

    // Cluster into columns by x
    final sortedByX = sortLeftToRight(idBubbles);
    final columns = <List<DetectedBubble>>[];
    List<DetectedBubble>? col;
    var colCx = 0.0;

    for (final b in sortedByX) {
      final cx = b.cx;
      if (col == null) {
        col = [b];
        colCx = cx;
      } else if ((cx - colCx).abs() > colPitchPx * 0.45) {
        columns.add(col);
        col = [b];
        colCx = cx;
      } else {
        col.add(b);
        colCx = (colCx + cx) / 2;
      }
    }
    if (col != null && col.isNotEmpty) columns.add(col);

    final buf = StringBuffer();
    for (final column in columns) {
      final sortedY = sortTopToBottom(column);
      final rows = groupIntoRows(sortedY, rowPitchPx, 1);
      if (rows.isEmpty || rows.first.isEmpty) {
        buf.write('?');
        continue;
      }
      final rowResult = readRow(rows.first, binary, 0, labels);
      buf.write(rowResult.answer);
    }

    final s = buf.toString();
    return s.isEmpty ? null : s;
  }

  // ── Convert row results → BubbleReading list ───────────────────────────

  static List<BubbleReading> toBubbleReadings(
    List<RowReadResult> rows,
    int totalItems,
  ) {
    final byItem = {for (final r in rows) r.itemNumber: r};
    return List.generate(totalItems, (i) {
      final itemNo = i + 1;
      final r = byItem[itemNo];
      if (r == null) {
        return BubbleReading(
          itemNumber: itemNo,
          detectedAnswer: '?',
          fillRatio: 0,
          isAmbiguous: true,
          isConfirmed: false,
          confidenceNote: 'Row not detected',
          confidenceScore: 0,
        );
      }
      final fillNorm = r.bestFill > 0 ? (r.bestFill / 500.0).clamp(0.0, 1.0) : 0.0;
      return BubbleReading(
        itemNumber: itemNo,
        detectedAnswer: r.answer,
        fillRatio: fillNorm,
        secondFillRatio: r.secondFill > 0 ? (r.secondFill / 500.0).clamp(0.0, 1.0) : null,
        isAmbiguous: r.ambiguous,
        isConfirmed: !r.ambiguous && r.answer != '?',
        confidenceNote: r.ambiguous
            ? 'Ambiguous row (fills ${r.bestFill} vs ${r.secondFill})'
            : 'Contour fill ${r.bestFill}',
        confidenceScore: r.ambiguous ? 0.35 : 0.85,
      );
    });
  }

  // ── Three-column zone helpers (mm → px on warped canvas) ───────────────

  /// Column 1: assessment QR + student ID (left zone).
  static ({double left, double top, double right, double bottom}) _leftZonePx(
    Map<String, dynamic> layout,
    double dpi,
  ) {
    final lz = layout['left_zone'] as Map<String, dynamic>?;
    if (lz != null) {
      final grid = layout['answer_grid'] as Map<String, dynamic>?;
      final colA = grid?['col_a'] as Map<String, dynamic>?;
      final bottomMm =
          (colA?['y_bottom_spec_mm'] as num?)?.toDouble() ?? 280.0;
      return (
        left: OmrImaging.mmToPx((lz['x0_mm'] as num).toDouble(), dpi).toDouble(),
        top: OmrImaging.mmToPx(
          ((lz['y_start_spec_mm'] as num?) ?? 80).toDouble(),
          dpi,
        ).toDouble(),
        right: OmrImaging.mmToPx((lz['x1_mm'] as num).toDouble(), dpi).toDouble(),
        bottom: OmrImaging.mmToPx(bottomMm, dpi).toDouble(),
      );
    }
    // Fallback for templates generated before left_zone metadata
    const x0 = 23.0;
    const x1 = 81.0;
    return (
      left: OmrImaging.mmToPx(x0, dpi).toDouble(),
      top: OmrImaging.mmToPx(80, dpi).toDouble(),
      right: OmrImaging.mmToPx(x1, dpi).toDouble(),
      bottom: OmrImaging.mmToPx(280, dpi).toDouble(),
    );
  }

  /// Columns 2+3 combined answer region (right zone).
  static ({double left, double top, double right, double bottom}) _answerZonePx(
    Map<String, dynamic> layout,
    double dpi,
  ) {
    final grid = layout['answer_grid'] as Map<String, dynamic>? ?? {};
    final yStart = (grid['y_start_spec_mm'] as num?)?.toDouble() ?? 80.0;

    var yEnd = yStart + 200.0;
    for (final key in ['col_a', 'col_b']) {
      final col = grid[key] as Map<String, dynamic>?;
      if (col != null) {
        final bot = (col['y_bottom_spec_mm'] as num?)?.toDouble();
        if (bot != null && bot > yEnd) yEnd = bot;
      }
    }

    final leftMm = (grid['answer_zone_x0_mm'] as num?)?.toDouble() ??
        (grid['col_a'] as Map?)?['x0_mm'] as num? ??
        83.0;
    final rightMm = (grid['answer_zone_x1_mm'] as num?)?.toDouble() ?? 193.0;

    return (
      left: OmrImaging.mmToPx(leftMm.toDouble(), dpi).toDouble(),
      top: OmrImaging.mmToPx(yStart, dpi).toDouble(),
      right: OmrImaging.mmToPx(rightMm.toDouble(), dpi).toDouble(),
      bottom: OmrImaging.mmToPx(yEnd, dpi).toDouble(),
    );
  }

  /// Column 2 (col_a) or column 3 (col_b) horizontal bounds.
  static ({double left, double top, double right, double bottom}) _answerColumnZonePx(
    Map<String, dynamic> colMeta,
    Map<String, dynamic> grid,
    double dpi,
    ({double left, double top, double right, double bottom}) answerZone,
  ) {
    final x0 = (colMeta['x0_mm'] as num).toDouble();
    final colW = (grid['col_width_mm'] as num?)?.toDouble() ??
        ((grid['col_b'] as Map?)?['x0_mm'] as num? ?? x0) -
            x0 -
            ((grid['col_gap_mm'] as num?)?.toDouble() ?? 1.5);

    return (
      left: OmrImaging.mmToPx(x0, dpi).toDouble(),
      top: answerZone.top,
      right: OmrImaging.mmToPx(x0 + colW, dpi).toDouble(),
      bottom: answerZone.bottom,
    );
  }
}
