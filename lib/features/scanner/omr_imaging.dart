import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'omr_models.dart';
import 'omr_classifier.dart';

/// Low‑level pixel operations for fiducial detection, perspective warp,
/// bubble sampling, ID‑bubble decoding, and real-time frame analysis.
// ignore_for_file: library_private_types_in_public_api, curly_braces_in_flow_control_structures

class OmrImaging {
  // ── QR decode ──────────────────────────────────────────────────────────

  static BarcodeScanner? _barcodeScanner;

  static BarcodeScanner _getScanner() {
    _barcodeScanner ??= BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    return _barcodeScanner!;
  }

  static void disposeScanner() {
    _barcodeScanner?.close();
    _barcodeScanner = null;
  }

  static Future<String?> decodeQR(String path) async {
    try {
      final scanner = _getScanner();
      final input = InputImage.fromFilePath(path);
      final barcodes = await scanner.processImage(input);
      return barcodes.isNotEmpty ? barcodes.first.rawValue : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> decodeQRFromFrame(CameraImage frame) async {
    try {
      final scanner = _getScanner();

      // Optimize: Efficiently concatenate planes into a single Uint8List
      final totalLen = frame.planes.fold<int>(0, (sum, p) => sum + p.bytes.length);
      final bytes = Uint8List(totalLen);
      int offset = 0;
      for (final plane in frame.planes) {
        bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }

      final Size imageSize = Size(frame.width.toDouble(), frame.height.toDouble());
      final InputImageRotation imageRotation = InputImageRotation.rotation90deg;

      final InputImageFormat inputImageFormat = defaultTargetPlatform == TargetPlatform.iOS
          ? InputImageFormat.bgra8888
          : InputImageFormat.nv21;

      final plane = frame.planes[0];

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: plane.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );

      final barcodes = await scanner.processImage(inputImage);
      return barcodes.isNotEmpty ? barcodes.first.rawValue : null;
    } catch (_) {
      return null;
    }
  }

  // ── Fiducial detection ─────────────────────────────────────────────────

  /// Find 4 corner fiducials in a binary image.
  static List<_FPoint> detectFiducials(img.Image src, Map<String, dynamic> layout) {
    final gray = img.grayscale(src);

    // Simple threshold
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final lum = img.getLuminance(gray.getPixel(x, y));
        gray.setPixel(x, y, lum < 64
            ? img.ColorInt32.rgba(0, 0, 0, 255)
            : img.ColorInt32.rgba(255, 255, 255, 255));
      }
    }

    final visited = List.generate(gray.height, (_) => List.filled(gray.width, false));
    final blobs = <_Blob>[];

    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        if (visited[y][x]) continue;
        final lum = img.getLuminance(gray.getPixel(x, y));
        if (lum > 128) { visited[y][x] = true; continue; }

        final rec = _flood(gray, visited, x, y);
        final bw = rec['maxX']! - rec['minX']! + 1;
        final bh = rec['maxY']! - rec['minY']! + 1;
        if (bw >= 8 && bh >= 8 &&
            bw <= src.width ~/ 3 && bh <= src.height ~/ 3) {
          final asp = bw / bh;
          if (asp >= 0.5 && asp <= 2.0) {
            blobs.add(_Blob(
              cx: (rec['minX']! + rec['maxX']!) / 2.0,
              cy: (rec['minY']! + rec['maxY']!) / 2.0,
            ));
          }
        }
      }
    }

    if (blobs.length < 4) return [];
    return _assignBlobsToCorners(blobs, src.width, src.height);
  }

  /// One-to-one greedy assignment: each blob maps to at most one corner.
  static List<_FPoint> _assignBlobsToCorners(
    List<_Blob> blobs,
    int width,
    int height,
  ) {
    final corners = [
      _FPoint(0, 0),
      _FPoint(width.toDouble(), 0),
      _FPoint(0, height.toDouble()),
      _FPoint(width.toDouble(), height.toDouble()),
    ];

    final pairs = <({int bi, int ci, double d})>[];
    for (int bi = 0; bi < blobs.length; bi++) {
      for (int ci = 0; ci < 4; ci++) {
        final dx = blobs[bi].cx - corners[ci].x;
        final dy = blobs[bi].cy - corners[ci].y;
        final d = sqrt(dx * dx + dy * dy);
        if (d < width * 0.5) pairs.add((bi: bi, ci: ci, d: d));
      }
    }
    pairs.sort((a, b) => a.d.compareTo(b.d));

    final usedBlobs = <int>{};
    final usedCorners = <int>{};
    final assigned = List<_FPoint?>.filled(4, null);

    for (final p in pairs) {
      if (usedBlobs.contains(p.bi) || usedCorners.contains(p.ci)) continue;
      usedBlobs.add(p.bi);
      usedCorners.add(p.ci);
      assigned[p.ci] = _FPoint(blobs[p.bi].cx, blobs[p.bi].cy);
      if (usedCorners.length == 4) break;
    }

    if (usedCorners.length < 4) return [];
    return assigned.cast<_FPoint>();
  }

  static Map<String, int> _flood(img.Image bin, List<List<bool>> visited, int sx, int sy) {
    final q = <_FPoint>[_FPoint(sx.toDouble(), sy.toDouble())];
    visited[sy][sx] = true;
    int minX = sx, maxX = sx, minY = sy, maxY = sy, cnt = 0;

    while (q.isNotEmpty) {
      final p = q.removeAt(0);
      final x = p.x.toInt(), y = p.y.toInt();
      cnt++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      for (final d in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + d.$1, ny = y + d.$2;
        if (nx < 0 || ny < 0 || nx >= bin.width || ny >= bin.height) continue;
        if (visited[ny][nx]) continue;
        if (img.getLuminance(bin.getPixel(nx, ny)) > 128) {
          visited[ny][nx] = true;
          continue;
        }
        visited[ny][nx] = true;
        q.add(_FPoint(nx.toDouble(), ny.toDouble()));
      }
    }
    return {'minX': minX, 'maxX': maxX, 'minY': minY, 'maxY': maxY, 'cnt': cnt};
  }

  // ── Fiducial ordering ──────────────────────────────────────────────────

  static List<_FPoint> sortCorners(List<_FPoint> pts) {
    final sorted = List<_FPoint>.from(pts)
      ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = sorted.first;
    final br = sorted.last;
    final mid = [sorted[1], sorted[2]]..sort((a, b) => a.x.compareTo(b.x));
    return [tl, mid[1], mid[0], br]; // TL, TR, BL, BR
  }

  // ── Perspective warp ──────────────────────────────────────────────────

  static (img.Image, double) warp(
    List<_FPoint> detected,
    img.Image src,
    Map<String, dynamic> layout,
  ) {
    final fiducials = layout['fiducials'] as List<dynamic>? ?? [];
    if (fiducials.length < 4) {
      final w = src.width;
      final pageW = ((layout['page_width_pt'] as num?) ?? 595.28).toDouble();
      final dpi = w / (pageW / 72.0);
      return (src, dpi);
    }

    // Expected positions in mm → pixels (using source image DPI guess)
    final pageWmm = ((layout['page_width_pt'] as num?) ?? 595.28).toDouble() / 72.0 * 25.4;
    final roughDpi = src.width / pageWmm * 25.4;

    final expected = <_FPoint>[];
    for (final f in fiducials) {
      final xmm = (f['x_mm'] as num).toDouble();
      final ymm = (f['y_spec_mm'] as num).toDouble();
      expected.add(_FPoint(xmm * roughDpi / 25.4, ymm * roughDpi / 25.4));
    }

    final mat = _computeHomography(detected, expected);
    if (mat == null) return (src, roughDpi);

    // Determine output dimensions from expected fiducial spread
    double minX = double.infinity, maxX = 0, minY = double.infinity, maxY = 0;
    for (final e in expected) {
      if (e.x < minX) minX = e.x;
      if (e.x > maxX) maxX = e.x;
      if (e.y < minY) minY = e.y;
      if (e.y > maxY) maxY = e.y;
    }
    final ow = (maxX - minX + 40).round();
    final oh = (maxY - minY + 40).round();

    final out = img.Image(width: ow, height: oh);
    final inv = _invert3x3(mat);

    for (int y = 0; y < oh; y++) {
      for (int x = 0; x < ow; x++) {
        final srcXY = _applyHomography(inv, x + minX - 20, y + minY - 20);
        final sx = srcXY.x.round();
        final sy = srcXY.y.round();
        if (sx >= 0 && sy >= 0 && sx < src.width && sy < src.height) {
          out.setPixel(x, y, src.getPixel(sx, sy));
        } else {
          out.setPixel(x, y, img.ColorInt32.rgba(255, 255, 255, 255));
        }
      }
    }

    final dpi = roughDpi; // approximate
    return (out, dpi);
  }

  // ── ID bubble reading (comb fields) ────────────────────────────────────

  static String? readIDBubbles(
    img.Image warped,
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

    final rPx = (rMm * dpi / 25.4).round();
    final labels = ['0','1','2','3','4','5','6','7','8','9','-'];

    // Phase 1: Sample all columns, collect all fills for global threshold
    final allColumnFills = <List<double>>[];
    // PDF draws first ID row at y_top + 2.5mm (see bubble_sheet_generator).
    const firstRowOffsetMm = 2.5;
    for (int c = 0; c < cols; c++) {
      final cx = ((x0mm + c * colPitch) * dpi / 25.4).round();
      final fills = <double>[];
      for (int r = 0; r < labels.length; r++) {
        final cy =
            ((yTopMm + firstRowOffsetMm + r * rowPitch) * dpi / 25.4).round();
        fills.add(sampleCircle(warped, cx, cy, rPx));
      }
      allColumnFills.add(fills);
    }

    // Phase 2: Global threshold from ALL ID bubble fills
    final allFills = <double>[];
    for (final cf in allColumnFills) { allFills.addAll(cf); }
    final globalThr = _largestGap(allFills, 0.40);

    // Phase 3: Per-column largest-gap with global fallback
    final buf = StringBuffer();
    for (final fills in allColumnFills) {
      final localThr = _largestGap(fills, globalThr);

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

  /// Largest-gap thresholding: find the largest gap between sorted values.
  /// Returns `(threshold, maxGap)`. Falls back when maxGap < 0.10.
  static (double threshold, double maxGap) largestGapThreshold(
    List<double> values,
    double fallback,
  ) {
    if (values.length < 2) return (fallback, 0);
    final sorted = List<double>.from(values)..sort();
    var maxGap = 0.0;
    var thr = fallback;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap > maxGap) {
        maxGap = gap;
        thr = sorted[i - 1] + gap / 2;
      }
    }
    return maxGap >= 0.10 ? (thr, maxGap) : (fallback, maxGap);
  }

  static double _largestGap(List<double> values, double fallback) =>
      largestGapThreshold(values, fallback).$1;

  // ── Circle sampling ────────────────────────────────────────────────────

  /// Fraction of pixels below threshold inside circle radius r at (cx,cy).
  /// Lowered threshold (100) to catch lighter pencil marks and gray shading.
  static double sampleCircle(img.Image image, int cx, int cy, int r) {
    if (r < 1) return 0;
    int total = 0, filled = 0;

    for (int dy = -r; dy <= r; dy++) {
      final xSpan = sqrt(r * r - dy * dy).round();
      final y = cy + dy;
      if (y < 0 || y >= image.height) continue;

      for (int dx = -xSpan; dx <= xSpan; dx++) {
        final x = cx + dx;
        if (x < 0 || x >= image.width) continue;
        total++;
        final lum = img.getLuminance(image.getPixel(x, y));
        if (lum < 100) filled++;
      }
    }
    return total > 0 ? filled / total : 0;
  }

  /// Extract full 7-feature vector from a bubble region.
  /// Uses [OmrClassifier.extractFeatures] which mirrors ZipGrade's SVM feature
  /// extraction: fill ratio, edge density, mean intensity, variance,
  /// ring ratio, background contrast, boundary gradient.
  static BubbleFeatures sampleBubbleFeatures(img.Image image, int cx, int cy, int r) {
    return OmrClassifier.extractFeatures(image, cx, cy, r);
  }

  /// Compute Otsu's threshold for a list of fill values.
  /// Provides an alternative global threshold that minimises intra-class variance,
  /// useful when the largest-gap method fails on low-contrast sheets.
  static double otsuThreshold(List<double> values, double fallback) {
    return OmrClassifier.otsuThreshold(values, fallback);
  }

  // ── Enhanced preprocessing pipeline ────────────────────────────────────

  /// Simple box blur for Otsu preprocessing (reference GaussianBlur step).
  static img.Image blurOnly(img.Image src, {int kernel = 5}) {
    return _blurImage(src, kernel);
  }

  /// Full OMR preprocessing chain mimicking AndroidOMRHelper's 6-stage pipeline.
  /// 1. Gaussian blur (noise reduction)
  /// 2. Min-max normalize (stretch to full range)
  /// 3. Truncation threshold (clamp bright pixels to suppress glare)
  /// 4. Local contrast enhancement (tile-based CLAHE-lite)
  /// 5. Gamma correction (darken midtones for faint marks)
  /// 6. Final normalize (stretch to full range)
  static img.Image preProcessForOcr(img.Image src, {
    int blurKernel = 3,
    int truncThreshold = 150,
    int tileSize = 32,
    double gamma = 0.7,
  }) {
    var img = _blurImage(src, blurKernel);
    img = _normalizeImage(img);
    img = _truncateThreshold(img, truncThreshold);
    img = _localContrastEnhance(img, tileSize);
    img = _adjustGamma(img, gamma);
    img = _normalizeImage(img);
    return img;
  }

  /// Truncation threshold: clamp pixels above [threshold] to [threshold],
  /// then stretch remaining range to 0-255. Suppresses glare / bright spots.
  /// Mirrors AndroidOMRHelper's THRESH_TRUNC step.
  static img.Image _truncateThreshold(img.Image src, int threshold) {
    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final lum = img.getLuminance(src.getPixel(x, y)).toInt();
        final clamped = lum > threshold ? threshold : lum;
        out.setPixel(x, y, img.ColorInt8.rgb(clamped, clamped, clamped));
      }
    }
    return out;
  }

  /// Simple tile-based local contrast enhancement (CLAHE-lite).
  /// Divides image into [tileSize]×[tileSize] tiles, stretches each tile
  /// independently, then bilinearly interpolates between neighboring tiles.
  /// Mimics CLAHE behavior from both reference projects.
  static img.Image _localContrastEnhance(img.Image src, int tileSize) {
    final w = src.width;
    final h = src.height;
    if (w < tileSize * 2 || h < tileSize * 2) return src;

    final tilesX = w ~/ tileSize;
    final tilesY = h ~/ tileSize;

    // Build tile LUTs: (min, max) per tile
    final tileMins = List.generate(tilesY, (_) => List.filled(tilesX, 255));
    final tileMaxs = List.generate(tilesY, (_) => List.filled(tilesX, 0));

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        int tmin = 255, tmax = 0;
        for (int y = ty * tileSize; y < (ty + 1) * tileSize; y++) {
          for (int x = tx * tileSize; x < (tx + 1) * tileSize; x++) {
            final lum = img.getLuminance(src.getPixel(x, y)).toInt();
            if (lum < tmin) tmin = lum;
            if (lum > tmax) tmax = lum;
          }
        }
        tileMins[ty][tx] = tmin;
        tileMaxs[ty][tx] = tmax > tmin ? tmax : tmin + 1;
      }
    }

    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Determine tile and interpolation weights
        final txF = (x / tileSize) - 0.5;
        final tyF = (y / tileSize) - 0.5;

        final tx0 = txF.floor().clamp(0, tilesX - 1);
        final tx1 = (tx0 + 1).clamp(0, tilesX - 1);
        final ty0 = tyF.floor().clamp(0, tilesY - 1);
        final ty1 = (ty0 + 1).clamp(0, tilesY - 1);

        final wx = (txF - tx0).clamp(0.0, 1.0);
        final wy = (tyF - ty0).clamp(0.0, 1.0);

        // Bilinear interpolation of tile min/max
        final lo00 = tileMins[ty0][tx0];
        final hi00 = tileMaxs[ty0][tx0];
        final lo10 = tileMins[ty0][tx1];
        final hi10 = tileMaxs[ty0][tx1];
        final lo01 = tileMins[ty1][tx0];
        final hi01 = tileMaxs[ty1][tx0];
        final lo11 = tileMins[ty1][tx1];
        final hi11 = tileMaxs[ty1][tx1];

        final lo = (lo00 * (1 - wx) + lo10 * wx) * (1 - wy) +
                  (lo01 * (1 - wx) + lo11 * wx) * wy;
        final hi = (hi00 * (1 - wx) + hi10 * wx) * (1 - wy) +
                  (hi01 * (1 - wx) + hi11 * wx) * wy;

        final lum = img.getLuminance(src.getPixel(x, y)).toInt();
        final range = hi - lo;
        final v = range > 1 ? ((lum - lo) * 255 / range).round().clamp(0, 255) : lum;
        out.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }
    return out;
  }

  /// Gaussian blur approximation using separable 1D kernels.
  static img.Image _blurImage(img.Image src, int kernelSize) {
    if (kernelSize <= 1) return src;
    // Box blur approximation (3 passes approximates Gaussian)
    var img = src;
    for (int pass = 0; pass < 3; pass++) {
      img = _boxBlur(img, kernelSize);
    }
    return img;
  }

  static img.Image _boxBlur(img.Image src, int r) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);

    // Horizontal pass
    for (int y = 0; y < h; y++) {
      int sum = 0;
      for (int x = 0; x < w; x++) {
        sum += img.getLuminance(src.getPixel(x, y)).toInt();
        if (x >= r * 2 + 1) {
          sum -= img.getLuminance(src.getPixel(x - r * 2 - 1, y)).toInt();
        }
        final v = (sum / (r * 2 + 1).clamp(1, x + 1)).round().clamp(0, 255);
        out.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }

    // Vertical pass
    final out2 = img.Image(width: w, height: h);
    for (int x = 0; x < w; x++) {
      int sum = 0;
      for (int y = 0; y < h; y++) {
        sum += img.getLuminance(out.getPixel(x, y)).toInt();
        if (y >= r * 2 + 1) {
          sum -= img.getLuminance(out.getPixel(x, y - r * 2 - 1)).toInt();
        }
        final v = (sum / (r * 2 + 1).clamp(1, y + 1)).round().clamp(0, 255);
        out2.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }
    return out2;
  }

  /// Min-max normalize: stretch to full 0-255 range.
  static img.Image _normalizeImage(img.Image src) {
    int minVal = 255, maxVal = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final lum = img.getLuminance(src.getPixel(x, y)).toInt();
        if (lum < minVal) minVal = lum;
        if (lum > maxVal) maxVal = lum;
      }
    }
    if (maxVal <= minVal) return src;

    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final lum = img.getLuminance(src.getPixel(x, y)).toInt();
        final v = ((lum - minVal) * 255 / (maxVal - minVal)).round().clamp(0, 255);
        out.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }
    return out;
  }

  /// Gamma correction via LUT. Gamma < 1 darkens midtones.
  static img.Image _adjustGamma(img.Image src, double gamma) {
    final invGamma = 1.0 / gamma;
    final lut = List<int>.generate(256, (i) => (pow(i / 255.0, invGamma) * 255).round());
    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final lum = img.getLuminance(src.getPixel(x, y)).toInt();
        out.setPixel(x, y, img.ColorInt8.rgb(lut[lum], lut[lum], lut[lum]));
      }
    }
    return out;
  }

  // ── Sobel edge detection (for page boundary fallback) ──────────────────

  /// Compute gradient magnitude using Sobel operators.
  /// Returns edge intensity 0-255.
  static img.Image sobelEdges(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width;
    final h = gray.height;
    final out = img.Image(width: w, height: h);

    // Sobel kernels
    const sobelX = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
    const sobelY = [-1, -2, -1, 0, 0, 0, 1, 2, 1];

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int gx = 0, gy = 0;
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final lum = img.getLuminance(gray.getPixel(x + kx, y + ky)).toInt();
            final idx = (ky + 1) * 3 + (kx + 1);
            gx += lum * sobelX[idx];
            gy += lum * sobelY[idx];
          }
        }
        final mag = sqrt(gx * gx + gy * gy).round().clamp(0, 255);
        out.setPixel(x, y, img.ColorInt8.rgb(mag, mag, mag));
      }
    }
    return out;
  }

  // ── Canny edge detection (ShreenidhiBodas/OMR: 75 / 200) ───────────────

  /// Canny edges on grayscale — reference repo uses (75, 200).
  static img.Image cannyEdges(
    img.Image src, {
    int lowThreshold = 75,
    int highThreshold = 200,
  }) {
    final gray = img.grayscale(src);
    final blurred = _blurImage(gray, 5);
    final w = blurred.width;
    final h = blurred.height;

    const sobelX = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
    const sobelY = [-1, -2, -1, 0, 0, 0, 1, 2, 1];

    final mag = List.generate(h, (_) => List.filled(w, 0.0));
    final angle = List.generate(h, (_) => List.filled(w, 0));

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int gx = 0, gy = 0;
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final lum = img.getLuminance(blurred.getPixel(x + kx, y + ky)).toInt();
            final idx = (ky + 1) * 3 + (kx + 1);
            gx += lum * sobelX[idx];
            gy += lum * sobelY[idx];
          }
        }
        final m = sqrt(gx * gx + gy * gy);
        mag[y][x] = m;
        if (gx.abs() > gy.abs() * 3) {
          angle[y][x] = 0;
        } else if (gy.abs() > gx.abs() * 3) {
          angle[y][x] = 2;
        } else {
          angle[y][x] = gx * gy >= 0 ? 1 : 3;
        }
      }
    }

    // Non-maximum suppression
    final suppressed = List.generate(h, (_) => List.filled(w, 0.0));
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final m = mag[y][x];
        if (m < lowThreshold) continue;
        bool isMax = true;
        switch (angle[y][x]) {
          case 0:
            isMax = m >= mag[y][x - 1] && m >= mag[y][x + 1];
          case 1:
            isMax = m >= mag[y - 1][x + 1] && m >= mag[y + 1][x - 1];
          case 2:
            isMax = m >= mag[y - 1][x] && m >= mag[y + 1][x];
          default:
            isMax = m >= mag[y - 1][x - 1] && m >= mag[y + 1][x + 1];
        }
        if (isMax) suppressed[y][x] = m;
      }
    }

    // Double threshold + hysteresis (8-connected)
    final strong = List.generate(h, (_) => List.filled(w, false));
    final weak = List.generate(h, (_) => List.filled(w, false));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (suppressed[y][x] >= highThreshold) {
          strong[y][x] = true;
        } else if (suppressed[y][x] >= lowThreshold) {
          weak[y][x] = true;
        }
      }
    }

    final q = <_Pix>[];
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (strong[y][x]) q.add(_Pix(x, y));
      }
    }

    while (q.isNotEmpty) {
      final p = q.removeAt(0);
      for (final d in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]) {
        final nx = p.x + d.$1;
        final ny = p.y + d.$2;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        if (weak[ny][nx] && !strong[ny][nx]) {
          strong[ny][nx] = true;
          q.add(_Pix(nx, ny));
        }
      }
    }

    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = strong[y][x] ? 0 : 255;
        out.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }
    return out;
  }

  // ── Edge-based page detection (contour-first alignment) ────────────────

  /// Detect the OMR sheet boundary — ShreenidhiBodas/OMR pipeline:
  /// GaussianBlur → Canny(75,200) → findContours(RETR_EXTERNAL) → approxPolyDP 2%.
  /// Returns 4 corner points (TL, TR, BL, BR), or null.
  static List<_FPoint>? detectPageEdges(img.Image src) {
    final w = src.width;
    final h = src.height;

    // Reference: Canny on blurred grayscale — no morph close
    final edges = cannyEdges(src);
    final components = _findEdgeComponents(edges);
    if (components.isEmpty) return null;

    // Reference: sort by contour area (descending), first 4-point approx wins
    components.sort((a, b) => _bboxArea(b).compareTo(_bboxArea(a)));

    for (final component in components.take(10)) {
      if (component.length < 20) continue;
      final hull = _convexHull(component);
      if (hull.length < 4) continue;
      final quad = _approxQuadrilateral(hull, w, h);
      if (quad == null) continue;
      final area = _polygonArea(quad);
      final ratio = area / (w * h);
      if (ratio >= 0.10 && ratio <= 0.98 && _maxCosine(quad) < 0.40) {
        return _orderPoints(quad);
      }
    }

    return null;
  }

  static double _bboxArea(List<_FPoint> pts) {
    if (pts.isEmpty) return 0;
    var minX = pts.first.x, maxX = pts.first.x;
    var minY = pts.first.y, maxY = pts.first.y;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return (maxX - minX) * (maxY - minY);
  }

  /// Connected edge-pixel components (RETR_EXTERNAL style on Canny output).
  static List<List<_FPoint>> _findEdgeComponents(img.Image edges) {
    final w = edges.width;
    final h = edges.height;
    final visited = List.generate(h, (_) => List.filled(w, false));
    final components = <List<_FPoint>>[];

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (visited[y][x]) continue;
        if (img.getLuminance(edges.getPixel(x, y)) >= 128) {
          visited[y][x] = true;
          continue;
        }
        final component = <_FPoint>[];
        final q = <_Pix>[_Pix(x, y)];
        visited[y][x] = true;
        while (q.isNotEmpty) {
          final p = q.removeAt(0);
          component.add(_FPoint(p.x.toDouble(), p.y.toDouble()));
          for (final d in [
            (1, 0), (-1, 0), (0, 1), (0, -1),
            (1, 1), (1, -1), (-1, 1), (-1, -1),
          ]) {
            final nx = p.x + d.$1;
            final ny = p.y + d.$2;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (visited[ny][nx]) continue;
            visited[ny][nx] = true;
            if (img.getLuminance(edges.getPixel(nx, ny)) < 128) {
              q.add(_Pix(nx, ny));
            }
          }
        }
        if (component.length >= 30) components.add(component);
      }
    }
    return components;
  }

  /// Andrew's monotone chain convex hull (ordered boundary for approxPolyDP).
  static List<_FPoint> _convexHull(List<_FPoint> points) {
    if (points.length < 3) return List.from(points);
    final pts = List<_FPoint>.from(points)
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

    double cross(_FPoint o, _FPoint a, _FPoint b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

    final lower = <_FPoint>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <_FPoint>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// Approximate a contour to a 4-point polygon (Douglas-Peucker).
  static List<_FPoint>? _approxQuadrilateral(List<_FPoint> contour, int w, int h) {
    if (contour.length < 4) return null;
    final perimeter = _arcLength(contour);
    // Match ShreenidhiBodas/OMR: approxPolyDP at ~2% of perimeter
    final epsilon = 0.02 * perimeter;

    // Simplified Douglas-Peucker
    final simplified = _douglasPeucker(contour, epsilon);

    if (simplified.length == 4) {
      return simplified;
    }
    // If more than 4 points, try to find the best 4
    if (simplified.length > 4) {
      // Sort by distance from center (extreme points)
      final cx = simplified.map((p) => p.x).reduce((a, b) => a + b) / simplified.length;
      final cy = simplified.map((p) => p.y).reduce((a, b) => a + b) / simplified.length;
      final withDist = simplified.map((p) {
        final d = (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy);
        return _PointDist(p, d);
      }).toList();
      withDist.sort((a, b) => b.dist.compareTo(a.dist));

      // Take 4 most extreme points
      final best4 = withDist.take(4).map((pd) => pd.point).toList();
      return best4.length == 4 ? best4 : null;
    }
    return null;
  }

  static double _arcLength(List<_FPoint> pts) {
    double len = 0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      len += sqrt((pts[i].x - pts[j].x) * (pts[i].x - pts[j].x) +
                  (pts[i].y - pts[j].y) * (pts[i].y - pts[j].y));
    }
    return len;
  }

  static List<_FPoint> _douglasPeucker(List<_FPoint> pts, double epsilon) {
    if (pts.length < 3) return List.from(pts);

    double maxDist = 0;
    int maxIdx = 0;
    final first = pts.first;
    final last = pts.last;

    for (int i = 1; i < pts.length - 1; i++) {
      final dist = _pointToLineDist(pts[i], first, last);
      if (dist > maxDist) {
        maxDist = dist;
        maxIdx = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _douglasPeucker(pts.sublist(0, maxIdx + 1), epsilon);
      final right = _douglasPeucker(pts.sublist(maxIdx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [first, last];
  }

  static double _pointToLineDist(_FPoint p, _FPoint a, _FPoint b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final denom = dx * dx + dy * dy;
    if (denom == 0) return sqrt((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y));
    final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / denom;
    final px = a.x + t * dx;
    final py = a.y + t * dy;
    return sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py));
  }

  static double _polygonArea(List<_FPoint> pts) {
    double area = 0;
    for (int i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      area += pts[i].x * pts[j].y - pts[j].x * pts[i].y;
    }
    return area.abs() / 2;
  }

  static double _maxCosine(List<_FPoint> pts) {
    double maxCos = 0;
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final c = pts[(i + 2) % pts.length];
      final ab = sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
      final bc = sqrt((b.x - c.x) * (b.x - c.x) + (b.y - c.y) * (b.y - c.y));
      final ca = sqrt((c.x - a.x) * (c.x - a.x) + (c.y - a.y) * (c.y - a.y));
      final cosVal = (ab * ab + bc * bc - ca * ca) / (2 * ab * bc);
      if (cosVal.abs() > maxCos) maxCos = cosVal.abs();
    }
    return maxCos;
  }

  /// Order 4 points as TL, TR, BL, BR.
  static List<_FPoint> _orderPoints(List<_FPoint> pts) {
    final sorted = List<_FPoint>.from(pts)
      ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = sorted.first;
    final br = sorted.last;
    final mid = [sorted[1], sorted[2]]..sort((a, b) => a.x.compareTo(b.x));
    return [tl, mid[1], mid[0], br]; // TL, TR, BL, BR
  }

  /// Find connected components (contours) in a binary image.
  static List<List<_FPoint>> _findContours(img.Image bin) {
    final w = bin.width;
    final h = bin.height;
    final visited = List.generate(h, (_) => List.filled(w, false));
    final contours = <List<_FPoint>>[];

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (visited[y][x]) continue;
        final lum = img.getLuminance(bin.getPixel(x, y)).toInt();
        if (lum >= 128) { visited[y][x] = true; continue; }

        // BFS to trace contour
        final contour = <_FPoint>[];
        final q = <_Pix>[_Pix(x, y)];
        visited[y][x] = true;

        while (q.isNotEmpty) {
          final p = q.removeAt(0);
          contour.add(_FPoint(p.x.toDouble(), p.y.toDouble()));

          for (final d in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]) {
            final nx = p.x + d.$1;
            final ny = p.y + d.$2;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (visited[ny][nx]) continue;
            visited[ny][nx] = true;
            if (img.getLuminance(bin.getPixel(nx, ny)).toInt() < 128) {
              q.add(_Pix(nx, ny));
            }
          }
        }

        // Only keep significant contours
        if (contour.length >= 20) {
          contours.add(contour);
        }
      }
    }
    return contours;
  }

  /// Morphological close: dilate then erode.
  static img.Image _morphClose(img.Image bin, int kernelSize) {
    var result = bin;
    result = _morphDilate(result, kernelSize);
    result = _morphErode(result, kernelSize);
    return result;
  }

  static img.Image _morphDilate(img.Image bin, int k) {
    final w = bin.width;
    final h = bin.height;
    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool hasDark = false;
        for (int ky = -k; ky <= k && !hasDark; ky++) {
          for (int kx = -k; kx <= k && !hasDark; kx++) {
            final nx = x + kx;
            final ny = y + ky;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (img.getLuminance(bin.getPixel(nx, ny)).toInt() < 128) {
              hasDark = true;
            }
          }
        }
        final v = hasDark ? 0 : 255;
        out.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }
    return out;
  }

  static img.Image _morphErode(img.Image bin, int k) {
    final w = bin.width;
    final h = bin.height;
    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool hasBright = false;
        for (int ky = -k; ky <= k && !hasBright; ky++) {
          for (int kx = -k; kx <= k && !hasBright; kx++) {
            final nx = x + kx;
            final ny = y + ky;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (img.getLuminance(bin.getPixel(nx, ny)).toInt() > 128) {
              hasBright = true;
            }
          }
        }
        final v = hasBright ? 255 : 0;
        out.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }
    return out;
  }

  // ── Robust sheet alignment (contour-first hybrid) ─────────────────────

  /// Page alignment — reference repo only (Canny contour quadrilateral).
  /// Tries full resolution, then resize-to-700 like test_grader.py.
  static ({List<_FPoint> corners, bool fromPageEdges}) detectSheetCorners(
    img.Image src,
    Map<String, dynamic> layout,
  ) {
    final corners = _detectPageWithResizeFallback(src);
    if (corners != null && corners.length == 4) {
      return (corners: corners, fromPageEdges: true);
    }
    return (corners: const [], fromPageEdges: true);
  }

  /// Reference repo resizes to width 700 before contour detection.
  static List<_FPoint>? _detectPageWithResizeFallback(img.Image src) {
    var corners = detectPageEdges(src);
    if (corners != null) return corners;

    const targetW = 700;
    final scale = targetW / src.width;
    final rh = max(40, (src.height * scale).round());
    final resized = img.copyResize(src, width: targetW, height: rh);
    corners = detectPageEdges(resized);
    if (corners == null) return null;

    final inv = src.width / targetW;
    return corners.map((p) => _FPoint(p.x * inv, p.y * inv)).toList();
  }

  /// Legacy API: contour-first, then fiducial blobs.
  static List<_FPoint> detectFiducialsRobust(img.Image src, Map<String, dynamic> layout) {
    final page = _detectPageWithResizeFallback(src);
    if (page != null && page.length == 4) return page;
    return detectFiducials(src, layout);
  }

  /// Align sheet: page contour → fiducials → direct full-frame (no scoring).
  static ({
    img.Image color,
    img.Image gray,
    img.Image binary,
    double dpi,
    String method,
    bool lowConfidence,
  }) prepareSheetForOmr(
    img.Image src,
    Map<String, dynamic> layout,
  ) {
    final targetDpi = (layout['dpi'] as num?)?.toDouble() ?? 150.0;
    final pageWpt = ((layout['page_width_pt'] as num?) ?? 612.0).toDouble();
    final pageHpt = ((layout['page_height_pt'] as num?) ?? 936.0).toDouble();

    final pageCorners = _detectPageWithResizeFallback(src);
    if (pageCorners != null && pageCorners.length == 4) {
      final wf = warpToPage(
        pageCorners,
        src,
        layout,
        fromPageEdges: true,
        targetDpi: targetDpi,
      );
      final gray = img.grayscale(wf.$1);
      return (
        color: wf.$1,
        gray: gray,
        binary: otsuBinarize(blurOnly(gray, kernel: 5)),
        dpi: wf.$2,
        method: 'page_contour',
        lowConfidence: false,
      );
    }

    final fids = detectFiducials(src, layout);
    if (fids.length >= 4) {
      final wf = warpToPage(
        fids,
        src,
        layout,
        fromPageEdges: false,
        targetDpi: targetDpi,
      );
      final gray = img.grayscale(wf.$1);
      return (
        color: wf.$1,
        gray: gray,
        binary: otsuBinarize(blurOnly(gray, kernel: 5)),
        dpi: wf.$2,
        method: 'fiducial',
        lowConfidence: false,
      );
    }

    final dpiX = src.width * 72.0 / pageWpt;
    final dpiY = src.height * 72.0 / pageHpt;
    final dpi = (dpiX + dpiY) / 2;
    final gray = img.grayscale(src);
    return (
      color: src,
      gray: gray,
      binary: otsuBinarize(blurOnly(gray, kernel: 5)),
      dpi: dpi,
      method: 'direct',
      lowConfidence: true,
    );
  }

  /// Warp the sheet onto a full page canvas at fixed [targetDpi].
  /// When [fromPageEdges] is true, [corners] map to the page rectangle.
  /// When false, [corners] are treated as fiducial centres mapped to layout mm.
  /// Bubble mm→px is then simply `mm * dpi / 25.4` with no crop offset.
  static (img.Image, double) warpToPage(
    List<_FPoint> corners,
    img.Image src,
    Map<String, dynamic> layout, {
    bool fromPageEdges = true,
    double targetDpi = 150,
  }) {
    final pageWmm =
        ((layout['page_width_pt'] as num?) ?? 612.0).toDouble() / 72.0 * 25.4;
    final pageHmm =
        ((layout['page_height_pt'] as num?) ?? 936.0).toDouble() / 72.0 * 25.4;
    final ow = (pageWmm * targetDpi / 25.4).round().clamp(200, 4000);
    final oh = (pageHmm * targetDpi / 25.4).round().clamp(200, 6000);

    if (corners.length < 4) {
      return (src, targetDpi);
    }

    final ordered = sortCorners(corners); // TL, TR, BL, BR
    late final List<_FPoint> dst;
    if (fromPageEdges) {
      dst = [
        _FPoint(0, 0),
        _FPoint((ow - 1).toDouble(), 0),
        _FPoint((ow - 1).toDouble(), (oh - 1).toDouble()),
        _FPoint(0, (oh - 1).toDouble()),
      ];
    } else {
      final fids = layout['fiducials'] as List<dynamic>? ?? [];
      if (fids.length < 4) {
        dst = [
          _FPoint(0, 0),
          _FPoint((ow - 1).toDouble(), 0),
          _FPoint((ow - 1).toDouble(), (oh - 1).toDouble()),
          _FPoint(0, (oh - 1).toDouble()),
        ];
      } else {
        final centres = <_FPoint>[];
        for (final f in fids) {
          final xmm = (f['x_mm'] as num).toDouble();
          final ymm = (f['y_spec_mm'] as num).toDouble();
          final wmm = (f['w_mm'] as num?)?.toDouble() ?? 10.0;
          final hmm = (f['h_mm'] as num?)?.toDouble() ?? 10.0;
          centres.add(_FPoint(
            (xmm + wmm / 2) * targetDpi / 25.4,
            (ymm + hmm / 2) * targetDpi / 25.4,
          ));
        }
        final sortedCentres = sortCorners(centres);
        dst = [
          sortedCentres[0],
          sortedCentres[1],
          sortedCentres[3], // BR
          sortedCentres[2], // BL
        ];
      }
    }

    // Homography src/dst order: TL, TR, BR, BL
    final srcPts = [ordered[0], ordered[1], ordered[3], ordered[2]];
    final mat = _computeHomography(srcPts, dst);
    if (mat == null) return (src, targetDpi);

    final out = img.Image(width: ow, height: oh);
    for (int y = 0; y < oh; y++) {
      for (int x = 0; x < ow; x++) {
        out.setPixel(x, y, img.ColorInt32.rgba(255, 255, 255, 255));
      }
    }

    final inv = _invert3x3(mat);
    for (int y = 0; y < oh; y++) {
      for (int x = 0; x < ow; x++) {
        final srcXY = _applyHomography(inv, x.toDouble(), y.toDouble());
        final sx = srcXY.x.round();
        final sy = srcXY.y.round();
        if (sx >= 0 && sy >= 0 && sx < src.width && sy < src.height) {
          out.setPixel(x, y, src.getPixel(sx, sy));
        }
      }
    }

    return (out, targetDpi);
  }

  /// Otsu binarization. BINARY_INV style: filled marks = 255, paper = 0.
  static img.Image otsuBinarize(img.Image src) {
    final hist = List<int>.filled(256, 0);
    final w = src.width;
    final h = src.height;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final lum = img.getLuminance(src.getPixel(x, y)).toInt().clamp(0, 255);
        hist[lum]++;
      }
    }

    final total = w * h;
    double sumAll = 0;
    for (int i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }

    double sumB = 0;
    int wB = 0;
    double maxVar = -1;
    int thr = 128;

    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;
      final varBetween = wB.toDouble() * wF * (mB - mF) * (mB - mF);
      if (varBetween > maxVar) {
        maxVar = varBetween;
        thr = t;
      }
    }

    final out = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final lum = img.getLuminance(src.getPixel(x, y)).toInt();
        final v = lum < thr ? 255 : 0;
        out.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }
    return out;
  }

  /// Fraction of filled (non-zero) pixels inside a circular mask on a binary image.
  static double maskFillRatio(img.Image binary, int cx, int cy, int r) {
    if (r < 1) return 0;
    int total = 0, filled = 0;
    final r2 = r * r;
    for (int dy = -r; dy <= r; dy++) {
      final y = cy + dy;
      if (y < 0 || y >= binary.height) continue;
      for (int dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy > r2) continue;
        final x = cx + dx;
        if (x < 0 || x >= binary.width) continue;
        total++;
        if (img.getLuminance(binary.getPixel(x, y)) > 128) filled++;
      }
    }
    return total > 0 ? filled / total : 0;
  }

  /// Refine a bubble centre by searching for the densest dark region nearby.
  /// Skips refinement when the template position looks empty, so the search
  /// does not latch onto the printed ring outline.
  static (int, int) refineBubbleCenter(
    img.Image binary,
    int cx,
    int cy,
    int r, {
    int searchRadius = 6,
  }) {
    final probeR = max(2, (r * 0.7).round());
    final base = maskFillRatio(binary, cx, cy, probeR);
    if (base < 0.12) return (cx, cy);

    double bestScore = base;
    int bestX = cx, bestY = cy;
    for (int dy = -searchRadius; dy <= searchRadius; dy++) {
      for (int dx = -searchRadius; dx <= searchRadius; dx++) {
        if (dx == 0 && dy == 0) continue;
        final score = maskFillRatio(binary, cx + dx, cy + dy, probeR);
        if (score > bestScore) {
          bestScore = score;
          bestX = cx + dx;
          bestY = cy + dy;
        }
      }
    }
    if (bestScore > base + 0.05) return (bestX, bestY);
    return (cx, cy);
  }

  static int mmToPx(double mm, double dpi) => (mm * dpi / 25.4).round();

  /// Parse assessment ID from QR payload (`id` or `id|...`).
  static String? parseAssessmentId(String? qrRaw) {
    if (qrRaw == null || qrRaw.trim().isEmpty) return null;
    return qrRaw.split('|').first.trim();
  }

  // ── Homography helpers ─────────────────────────────────────────────────

  static List<double>? _computeHomography(List<_FPoint> src, List<_FPoint> dst) {
    if (src.length < 4 || dst.length < 4) return null;
    final a = <double>[];
    final b = <double>[];

    for (int i = 0; i < 4; i++) {
      final x = src[i].x, y = src[i].y;
      final u = dst[i].x, v = dst[i].y;
      a.addAll([x, y, 1, 0, 0, 0, -u * x, -u * y]);
      b.add(u);
      a.addAll([0, 0, 0, x, y, 1, -v * x, -v * y]);
      b.add(v);
    }

    final h = _solveLinear8x8(a, b);
    if (h == null) return null;
    h.add(1.0);
    return h;
  }

  static List<double>? _solveLinear8x8(List<double> a, List<double> b) {
    final n = 8;
    final aug = List.generate(n, (i) {
      final row = <double>[];
      for (int j = 0; j < n; j++) row.add(a[i * n + j]);
      row.add(b[i]);
      return row;
    });

    for (int col = 0; col < n; col++) {
      int maxRow = col;
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > aug[maxRow][col].abs()) { maxRow = row; }
      }
      final tmp = aug[col];
      aug[col] = aug[maxRow];
      aug[maxRow] = tmp;

      if (aug[col][col].abs() < 1e-12) return null;

      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / aug[col][col];
        for (int j = col; j <= n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    final x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double sum = 0;
      for (int j = i + 1; j < n; j++) { sum += aug[i][j] * x[j]; }
      x[i] = (aug[i][n] - sum) / aug[i][i];
    }
    return List<double>.from(x); // growable — caller may append
  }

  static List<double> _invert3x3(List<double> m) {
    final det = m[0] * (m[4] * m[8] - m[5] * m[7]) -
               m[1] * (m[3] * m[8] - m[5] * m[6]) +
               m[2] * (m[3] * m[7] - m[4] * m[6]);
    if (det.abs() < 1e-12) return m;

    final invDet = 1.0 / det;
    return [
      (m[4] * m[8] - m[5] * m[7]) * invDet,
      (m[2] * m[7] - m[1] * m[8]) * invDet,
      (m[1] * m[5] - m[2] * m[4]) * invDet,
      (m[5] * m[6] - m[3] * m[8]) * invDet,
      (m[0] * m[8] - m[2] * m[6]) * invDet,
      (m[2] * m[3] - m[0] * m[5]) * invDet,
      (m[3] * m[7] - m[4] * m[6]) * invDet,
      (m[1] * m[6] - m[0] * m[7]) * invDet,
      (m[0] * m[4] - m[1] * m[3]) * invDet,
    ];
  }

  static _FPoint _applyHomography(List<double> h, double x, double y) {
    final w = h[6] * x + h[7] * y + h[8];
    final nx = (h[0] * x + h[1] * y + h[2]) / w;
    final ny = (h[3] * x + h[4] * y + h[5]) / w;
    return _FPoint(nx, ny);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Real‑time frame analysis for live viewfinder
  // ═══════════════════════════════════════════════════════════════════════

  /// Convert a CameraImage (NV21/YUV420) to a grayscale img.Image.
  /// Supports NV21 (Android) and BGRA8888 (iOS) formats.
  static img.Image convertCameraImage(CameraImage frame) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _convertBGRA8888(frame);
    }
    // Default: NV21 / YUV420
    return _convertYUV420(frame);
  }

  static img.Image _convertBGRA8888(CameraImage frame) {
    final planes = frame.planes;
    final bytes = planes[0].bytes;
    final w = frame.width;
    final h = frame.height;
    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * planes[0].bytesPerRow + x * 4;
        if (idx + 2 >= bytes.length) continue;
        final b = bytes[idx];
        final g = bytes[idx + 1];
        final r = bytes[idx + 2];
        final gray = ((r + g + b) ~/ 3).clamp(0, 255);
        out.setPixel(x, y, img.ColorInt8.rgb(gray, gray, gray));
      }
    }
    return out;
  }

  static img.Image _convertYUV420(CameraImage frame) {
    final w = frame.width;
    final h = frame.height;
    final yPlane = frame.planes[0];
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;

    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * yRowStride + x * yPixelStride;
        if (idx >= yPlane.bytes.length) continue;
        final lum = yPlane.bytes[idx];
        out.setPixel(x, y, img.ColorInt8.rgb(lum, lum, lum));
      }
    }
    return out;
  }

  /// Live page detection — Canny sheet boundary + optional bird's-eye preview.
  /// Corner positions are portrait-UI normalised (0–1).
  static ({
    bool tl,
    bool tr,
    bool bl,
    bool br,
    double? tlx,
    double? tly,
    double? trx,
    double? tryv,
    double? blx,
    double? bly,
    double? brx,
    double? bry,
    Uint8List? alignedPreview,
  }) detectPageCornersFast(
    CameraImage frame, {
    int targetWidth = 400,
    bool buildAlignedPreview = false,
  }) {
    const fail = (
      tl: false,
      tr: false,
      bl: false,
      br: false,
      tlx: null,
      tly: null,
      trx: null,
      tryv: null,
      blx: null,
      bly: null,
      brx: null,
      bry: null,
      alignedPreview: null,
    );

    try {
      final gray = convertCameraImage(frame);
      final scale = targetWidth / gray.width;
      final rh = max(40, (gray.height * scale).round());
      final small = img.copyResize(gray, width: targetWidth, height: rh);

      final corners = detectPageEdges(small);
      if (corners == null || corners.length < 4) return fail;

      final ordered = _orderPoints(corners); // TL, TR, BL, BR in small-image space
      final sw = small.width.toDouble();
      final sh = small.height.toDouble();
      final landscape = sw > sh;

      Offset toUi(_FPoint p) {
        final sx = p.x / sw;
        final sy = p.y / sh;
        if (landscape) {
          return Offset(sy, 1.0 - sx);
        }
        return Offset(sx, sy);
      }

      final tlUi = toUi(ordered[0]);
      final trUi = toUi(ordered[1]);
      final blUi = toUi(ordered[2]);
      final brUi = toUi(ordered[3]);

      Uint8List? preview;
      if (buildAlignedPreview) {
        // Bird's-eye at low res for live PiP (long-bond aspect ~8.5:13).
        const outW = 140;
        final outH = (outW * 13.0 / 8.5).round();
        final dst = [
          _FPoint(0, 0),
          _FPoint((outW - 1).toDouble(), 0),
          _FPoint((outW - 1).toDouble(), (outH - 1).toDouble()),
          _FPoint(0, (outH - 1).toDouble()),
        ];
        // Homography src order: TL, TR, BR, BL
        final srcPts = [ordered[0], ordered[1], ordered[3], ordered[2]];
        final dstPts = [dst[0], dst[1], dst[3], dst[2]];
        final mat = _computeHomography(srcPts, dstPts);
        if (mat != null) {
          final inv = _invert3x3(mat);
          final out = img.Image(width: outW, height: outH);
          for (var y = 0; y < outH; y++) {
            for (var x = 0; x < outW; x++) {
              final srcXY = _applyHomography(inv, x.toDouble(), y.toDouble());
              final sx = srcXY.x.round();
              final sy = srcXY.y.round();
              if (sx >= 0 && sy >= 0 && sx < small.width && sy < small.height) {
                out.setPixel(x, y, small.getPixel(sx, sy));
              } else {
                out.setPixel(x, y, img.ColorInt8.rgb(255, 255, 255));
              }
            }
          }
          preview = Uint8List.fromList(img.encodeJpg(out, quality: 55));
        }
      }

      return (
        tl: true,
        tlx: tlUi.dx,
        tly: tlUi.dy,
        tr: true,
        trx: trUi.dx,
        tryv: trUi.dy,
        bl: true,
        blx: blUi.dx,
        bly: blUi.dy,
        br: true,
        brx: brUi.dx,
        bry: brUi.dy,
        alignedPreview: preview,
      );
    } catch (_) {
      return fail;
    }
  }

  /// Live fiducial tracking — finds dark square markers in the four corner
  /// regions of the camera frame (fast Y-plane downsample). Falls back to
  /// page-contour detection when blobs are missing.
  static ({
    bool tl,
    bool tr,
    bool bl,
    bool br,
    double? tlx,
    double? tly,
    double? trx,
    double? tryv,
    double? blx,
    double? bly,
    double? brx,
    double? bry,
    Uint8List? alignedPreview,
  }) detectFiducialsLive(
    CameraImage frame, {
    bool buildAlignedPreview = false,
  }) {
    const fail = (
      tl: false,
      tr: false,
      bl: false,
      br: false,
      tlx: null,
      tly: null,
      trx: null,
      tryv: null,
      blx: null,
      bly: null,
      brx: null,
      bry: null,
      alignedPreview: null,
    );

    try {
      final yPlane = frame.planes[0];
      final fw = frame.width;
      final fh = frame.height;
      final stride = yPlane.bytesPerRow;
      final pixStride = yPlane.bytesPerPixel ?? 1;
      const scale = 4;
      final w = max(40, fw ~/ scale);
      final h = max(40, fh ~/ scale);

      // Downsampled luminance grid
      final grid = List.generate(h, (yy) {
        return List<int>.generate(w, (xx) {
          final sx = (xx * scale).clamp(0, fw - 1);
          final sy = (yy * scale).clamp(0, fh - 1);
          final idx = sy * stride + sx * pixStride;
          if (idx < 0 || idx >= yPlane.bytes.length) return 255;
          return yPlane.bytes[idx];
        });
      });

      final landscape = w > h;
      Offset toUi(double ix, double iy) {
        final sx = ix / w;
        final sy = iy / h;
        if (landscape) return Offset(sy, 1.0 - sx);
        return Offset(sx, sy);
      }

      Offset fromUi(Offset ui) {
        if (landscape) {
          // Inverse of toUi: ui=(sy, 1-sx)
          return Offset((1.0 - ui.dy) * w, ui.dx * h);
        }
        return Offset(ui.dx * w, ui.dy * h);
      }

      // ── 1) Predict fiducials inside the PAPER, not screen corners ──
      // Page contour → inset fiducial UV from printed layout mm.
      // Fallback: same ghost-guide positions used by the overlay painter.
      final page = detectPageCornersFast(
        frame,
        targetWidth: 260,
        buildAlignedPreview: false,
      );

      late final List<Offset> predictedUi;
      late final Rect paperBoundsUi;

      if (page.tl &&
          page.tr &&
          page.bl &&
          page.br &&
          page.tlx != null &&
          page.tly != null &&
          page.trx != null &&
          page.tryv != null &&
          page.blx != null &&
          page.bly != null &&
          page.brx != null &&
          page.bry != null) {
        final tl = Offset(page.tlx!, page.tly!);
        final tr = Offset(page.trx!, page.tryv!);
        final bl = Offset(page.blx!, page.bly!);
        final br = Offset(page.brx!, page.bry!);
        paperBoundsUi = Rect.fromPoints(tl, br)
            .expandToInclude(Rect.fromPoints(tr, bl))
            .inflate(0.02);

        // Printed fiducial centres (mm) → UV on long-bond page.
        const pageWmm = 215.9;
        const pageHmm = 330.2;
        const fidInset = 8.0;
        const fidW = 10.0;
        const headerMm = 50.8;
        const contentBotMm = 294.8;
        final uvs = <Offset>[
          Offset((fidInset + fidW / 2) / pageWmm,
              (headerMm + fidW / 2) / pageHmm),
          Offset((pageWmm - fidInset - fidW / 2) / pageWmm,
              (headerMm + fidW / 2) / pageHmm),
          Offset((fidInset + fidW / 2) / pageWmm,
              (contentBotMm + fidW / 2) / pageHmm),
          Offset((pageWmm - fidInset - fidW / 2) / pageWmm,
              (contentBotMm + fidW / 2) / pageHmm),
        ];
        Offset bilinear(Offset uv) {
          final u = uv.dx, v = uv.dy;
          return Offset(
            (1 - u) * (1 - v) * tl.dx +
                u * (1 - v) * tr.dx +
                (1 - u) * v * bl.dx +
                u * v * br.dx,
            (1 - u) * (1 - v) * tl.dy +
                u * (1 - v) * tr.dy +
                (1 - u) * v * bl.dy +
                u * v * br.dy,
          );
        }

        predictedUi = uvs.map(bilinear).toList();
      } else {
        // Paper not found — search near the on-screen alignment ghosts.
        predictedUi = _expectedFiducialUiNorm();
        paperBoundsUi = _paperGuideUiNorm();
      }

      // ── 2) Small local search around each prediction (image space) ──
      final searchR = (min(w, h) * 0.08).round().clamp(10, 28);
      final found = <Offset?>[];
      for (final pred in predictedUi) {
        final img = fromUi(pred);
        final cx = img.dx.round().clamp(0, w - 1);
        final cy = img.dy.round().clamp(0, h - 1);
        final region = _CornerRegion(
          rx: (cx - searchR).clamp(0, w - 1),
          ry: (cy - searchR).clamp(0, h - 1),
          rw: (searchR * 2).clamp(1, w),
          rh: (searchR * 2).clamp(1, h),
          ax: cx,
          ay: cy,
        );
        // Clip rw/rh to stay in bounds
        final rw = min(region.rw, w - region.rx);
        final rh = min(region.rh, h - region.ry);
        final clipped = _CornerRegion(
          rx: region.rx,
          ry: region.ry,
          rw: rw,
          rh: rh,
          ax: cx,
          ay: cy,
        );
        final blob = _findDarkBlobInRegion(grid, w, h, clipped);
        if (!blob.detected) {
          found.add(null);
          continue;
        }
        final ui = toUi(blob.x, blob.y);
        // Must stay on the paper / inside the alignment frame — never floor.
        if (!paperBoundsUi.inflate(0.04).contains(ui)) {
          found.add(null);
          continue;
        }
        // Stay near the prediction (reject random dark spots).
        if ((ui - pred).distance > 0.14) {
          found.add(null);
          continue;
        }
        found.add(ui);
      }

      var uiTl = found.isNotEmpty ? found[0] : null;
      var uiTr = found.length > 1 ? found[1] : null;
      var uiBl = found.length > 2 ? found[2] : null;
      var uiBr = found.length > 3 ? found[3] : null;

      // Complete one missing corner from the other three (parallelogram).
      Offset? completeFourth(Offset? a, Offset? b, Offset? c) {
        if (a == null || b == null || c == null) return null;
        final p = Offset(a.dx + c.dx - b.dx, a.dy + c.dy - b.dy);
        if (!paperBoundsUi.inflate(0.06).contains(p)) {
          return null;
        }
        return p;
      }

      final hits = [uiTl, uiTr, uiBl, uiBr].whereType<Offset>().length;
      if (hits == 3) {
        final oTl = uiTl, oTr = uiTr, oBl = uiBl, oBr = uiBr;
        if (oTl == null) {
          uiTl = completeFourth(oTr, oBr, oBl);
        } else if (oTr == null) {
          uiTr = completeFourth(oTl, oBl, oBr);
        } else if (oBl == null) {
          uiBl = completeFourth(oTl, oTr, oBr);
        } else if (oBr == null) {
          uiBr = completeFourth(oTr, oTl, oBl);
        }
      }

      final tl = uiTl != null;
      final tr = uiTr != null;
      final bl = uiBl != null;
      final br = uiBr != null;

      Uint8List? preview;
      if (buildAlignedPreview && tl && tr && bl && br) {
        final aligned = detectPageCornersFast(
          frame,
          targetWidth: 280,
          buildAlignedPreview: true,
        );
        preview = aligned.alignedPreview;
      }

      return (
        tl: tl,
        tr: tr,
        bl: bl,
        br: br,
        tlx: uiTl?.dx,
        tly: uiTl?.dy,
        trx: uiTr?.dx,
        tryv: uiTr?.dy,
        blx: uiBl?.dx,
        bly: uiBl?.dy,
        brx: uiBr?.dx,
        bry: uiBr?.dy,
        alignedPreview: preview,
      );
    } catch (e) {
      debugPrint('detectFiducialsLive error: $e');
      return fail;
    }
  }

  /// Paper guide rectangle in normalised preview coords (matches overlay).
  static Rect _paperGuideUiNorm() {
    const topMargin = 0.03;
    const bottomMargin = 0.03;
    const paperAspectHw = 13.0 / 8.5; // height / width of long bond
    const previewAspectWh = 9.0 / 16.0; // typical portrait preview width/height
    final availableH = 1.0 - topMargin - bottomMargin;
    var clearW = 0.94;
    // height_norm = clearW * previewAspectWh * paperAspectHw
    // because clearW_px = 0.94*W, clearH_px = clearW_px * paperAspectHw,
    // clearH_norm = clearH_px/H = 0.94*(W/H)*paperAspectHw
    var clearH = clearW * previewAspectWh * paperAspectHw;
    if (clearH > availableH) {
      clearH = availableH;
      clearW = clearH / (previewAspectWh * paperAspectHw);
    }
    final centerY = topMargin + availableH / 2;
    return Rect.fromCenter(
      center: Offset(0.5, centerY),
      width: clearW,
      height: clearH,
    );
  }

  /// Ghost fiducial centres in normalised UI — same mm layout as the painter.
  static List<Offset> _expectedFiducialUiNorm() {
    const pageWmm = 215.9;
    const pageHmm = 330.2;
    const fidInset = 8.0;
    const fidW = 10.0;
    const headerMm = 50.8;
    const contentBotMm = 294.8;
    final guide = _paperGuideUiNorm();
    Offset at(double xMm, double yMm) => Offset(
          guide.left + (xMm / pageWmm) * guide.width,
          guide.top + (yMm / pageHmm) * guide.height,
        );
    return [
      at(fidInset + fidW / 2, headerMm + fidW / 2),
      at(pageWmm - fidInset - fidW / 2, headerMm + fidW / 2),
      at(fidInset + fidW / 2, contentBotMm + fidW / 2),
      at(pageWmm - fidInset - fidW / 2, contentBotMm + fidW / 2),
    ];
  }

  /// @deprecated Use [detectFiducialsLive].
  static ({
    bool tl,
    bool tr,
    bool bl,
    bool br,
    double? tlx,
    double? tly,
    double? trx,
    double? tryv,
    double? blx,
    double? bly,
    double? brx,
    double? bry,
    Uint8List? alignedPreview,
  }) detectFiducialsFast(
    CameraImage frame, {
    int scaleDown = 4,
    Rect? roi,
  }) =>
      detectFiducialsLive(frame);

  /// Finds a solid black square fiducial in a corner band.
  /// Prefers dark, dense, roughly-square blobs near the outer corner —
  /// rejects filled answer-bubble clusters farther inward.
  static ({bool detected, double x, double y}) _findDarkBlobInRegion(
    List<List<int>> grid,
    int w,
    int h,
    _CornerRegion region,
  ) {
    final visited = <int>{};

    final rx = region.rx.clamp(0, w - 1);
    final ry = region.ry.clamp(0, h - 1);
    final rw = region.rw.clamp(1, w - rx);
    final rh = region.rh.clamp(1, h - ry);

    // Adaptive threshold from local luminance (helps wrinkled / shadowed bottoms).
    var sum = 0;
    var count = 0;
    var minL = 255;
    for (int y = ry; y < ry + rh; y += 2) {
      for (int x = rx; x < rx + rw; x += 2) {
        final v = grid[y][x];
        sum += v;
        count++;
        if (v < minL) minL = v;
      }
    }
    final localMean = count > 0 ? sum / count : 180.0;
    // Fiducials are much darker than paper; keep threshold near true black.
    final darkThreshold =
        ((localMean * 0.45) + (minL * 0.55)).round().clamp(40, 100);

    // Fiducial ≈ 10mm on ~216mm page → ~4–6% of framed width.
    final minDim = (w * 0.012).round().clamp(3, 10);
    final maxDim = (w * 0.09).round().clamp(10, 36);
    final regionDiag =
        sqrt(rw * rw + rh * rh).clamp(1.0, double.infinity);

    double bestScore = -1;
    int bestCx = 0, bestCy = 0;

    for (int y = ry; y < ry + rh; y++) {
      for (int x = rx; x < rx + rw; x++) {
        final key = y * w + x;
        if (visited.contains(key)) continue;
        if (grid[y][x] > darkThreshold) continue;

        final q = <_Pix>[_Pix(x, y)];
        visited.add(key);
        int blobSize = 0;
        int sumX = 0, sumY = 0, sumLum = 0;
        int minX = x, maxX = x, minY = y, maxY = y;

        while (q.isNotEmpty) {
          final p = q.removeAt(0);
          blobSize++;
          final lum = grid[p.y][p.x];
          final darkness = (darkThreshold - lum).clamp(1, darkThreshold);
          sumX += p.x * darkness;
          sumY += p.y * darkness;
          sumLum += lum;
          if (p.x < minX) minX = p.x;
          if (p.x > maxX) maxX = p.x;
          if (p.y < minY) minY = p.y;
          if (p.y > maxY) maxY = p.y;

          for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nx = p.x + d.$1;
            final ny = p.y + d.$2;
            if (nx < rx || ny < ry || nx >= rx + rw || ny >= ry + rh) continue;
            final nKey = ny * w + nx;
            if (visited.contains(nKey)) continue;
            visited.add(nKey);
            if (grid[ny][nx] <= darkThreshold) {
              q.add(_Pix(nx, ny));
            }
          }
        }

        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        if (bw < minDim ||
            bh < minDim ||
            bw > maxDim ||
            bh > maxDim ||
            blobSize < 6) {
          continue;
        }

        final aspect = bw / bh;
        if (aspect < 0.6 || aspect > 1.65) continue;

        final bboxArea = bw * bh;
        final fillRatio = blobSize / bboxArea;
        // Solid printed square ≈ high fill; bubble clusters are sparser.
        if (fillRatio < 0.50) continue;

        final meanLum = sumLum / blobSize;
        if (meanLum > 75) continue;

        final darknessW = max(1.0, (darkThreshold - meanLum) * blobSize);
        final wcx = sumX / darknessW;
        final wcy = sumY / darknessW;

        final dist = sqrt(
            (wcx - region.ax) * (wcx - region.ax) +
                (wcy - region.ay) * (wcy - region.ay));
        // Reject blobs sitting too far inward (answer grid / ID bubbles).
        if (dist > regionDiag * 0.72) continue;
        final cornerBias = 1.0 / (1.0 + dist / regionDiag);

        // Score: dark + solid + near outer corner. Size secondary.
        final score = (90 - meanLum) *
            fillRatio *
            fillRatio *
            cornerBias *
            (1.0 + blobSize / 80.0);

        if (score > bestScore) {
          bestScore = score;
          bestCx = wcx.round().clamp(minX, maxX);
          bestCy = wcy.round().clamp(minY, maxY);
        }
      }
    }

    if (bestScore > 0) {
      return (detected: true, x: bestCx.toDouble(), y: bestCy.toDouble());
    }
    return (detected: false, x: 0.0, y: 0.0);
  }

  /// Estimate glare level from the Y plane of a CameraImage.
  /// Samples centre strip; returns 0–1 where >0.45 means significant glare.
  static double estimateGlare(CameraImage frame) {
    final yPlane = frame.planes[0];
    final yRowStride = yPlane.bytesPerRow;
    final w = frame.width;
    final h = frame.height;

    int brightCount = 0;
    int totalSamples = 0;
    final step = 8;

    // Sample a horizontal band across the middle third
    final startY = h ~/ 3;
    final endY = (h * 2) ~/ 3;

    for (int y = startY; y < endY; y += step) {
      for (int x = 0; x < w; x += step) {
        final idx = y * yRowStride + x;
        if (idx >= yPlane.bytes.length) continue;
        totalSamples++;
        if (yPlane.bytes[idx] > 215) brightCount++;
      }
    }

    return totalSamples > 0 ? brightCount / totalSamples : 0;
  }

  /// Estimate sharpness via Laplacian variance on the Y plane.
  /// Returns 0–1 where <0.30 means blurry.
  static double estimateSharpness(CameraImage frame) {
    final yPlane = frame.planes[0];
    final yRowStride = yPlane.bytesPerRow;
    final w = frame.width;
    final h = frame.height;

    double sumLap = 0;
    int count = 0;
    final step = 6;

    for (int y = step; y < h - step; y += step) {
      for (int x = step; x < w - step; x += step) {
        final idx = y * yRowStride + x;
        final idxL = y * yRowStride + (x - step);
        final idxR = y * yRowStride + (x + step);
        final idxU = (y - step) * yRowStride + x;
        final idxD = (y + step) * yRowStride + x;

        if (idxR >= yPlane.bytes.length || idxD * yRowStride >= yPlane.bytes.length) continue;

        final c = yPlane.bytes[idx].toDouble();
        final l = yPlane.bytes[idxL.clamp(0, yPlane.bytes.length - 1)].toDouble();
        final r = yPlane.bytes[idxR.clamp(0, yPlane.bytes.length - 1)].toDouble();
        final u = yPlane.bytes[idxU.clamp(0, yPlane.bytes.length - 1)].toDouble();
        final d = yPlane.bytes[idxD.clamp(0, yPlane.bytes.length - 1)].toDouble();

        // Laplacian: 4*center - left - right - up - down
        final lap = (4 * c - l - r - u - d).abs();
        sumLap += lap;
        count++;
      }
    }

    if (count == 0) return 0;
    final avg = sumLap / count;
    // Normalise: typical sharp images have LapVar ~30–100, blurry <10
    return (avg / 50.0).clamp(0.0, 1.0);
  }

  /// Full OMR analysis on a single frame for live overlays.
  static List<BubbleOverlayData> sampleBubblesLive(
    CameraImage frame,
    FiducialLockState lockState,
    Map<String, dynamic> layout,
    Map<String, String> answerKey,
    int numChoices,
  ) {
    if (!lockState.allLocked) return [];

    // 1. Setup coordinate transform
    final detected = lockState.corners.map((c) {
      // Scale normalized 0-1 to pixel coordinates in frame
      return _FPoint(c.position!.dx * frame.width, c.position!.dy * frame.height);
    }).toList();

    // Map: detected corners -> expected template corners (mm)
    final fiducials = layout['fiducials'] as List<dynamic>? ?? [];
    if (fiducials.length < 4) return [];

    final expected = fiducials.map((f) => _FPoint((f['x_mm'] as num).toDouble(), (f['y_spec_mm'] as num).toDouble())).toList();
    final mat = _computeHomography(detected, expected);
    if (mat == null) return [];
    
    final inv = _invert3x3(mat);

    // 2. Sample bubbles
    final items = layout['items'] as Map<String, dynamic>? ?? {};
    final overlayData = <BubbleOverlayData>[];
    final choices = List.generate(numChoices, (i) => String.fromCharCode(65 + i));

    final yPlane = frame.planes[0];
    final yRowStride = yPlane.bytesPerRow;

    for (final entry in items.entries) {
      final itemNum = entry.key;
      final itemData = entry.value as Map<String, dynamic>;
      final correct = answerKey[itemNum];

      double bestFill = 0;
      String bestChoice = '?';
      double secondFill = 0;

      final perItemFills = <double>[];
      for (final ch in choices) {
        final coord = itemData[ch] as Map<String, dynamic>?;
        if (coord == null) { perItemFills.add(0); continue; }

        final cxMm = (coord['cx_mm'] as num?)?.toDouble() ?? 0;
        final cyMm = (coord['cy_spec_mm'] as num?)?.toDouble() ?? 0;

        // Map template mm to frame pixels
        final px = _applyHomography(inv, cxMm, cyMm);

        final fill = _sampleLuminanceCircle(yPlane.bytes, yRowStride, frame.width, frame.height, px.x.toInt(), px.y.toInt(), 6);
        perItemFills.add(fill);
        
        if (fill > bestFill) {
          secondFill = bestFill;
          bestFill = fill;
          bestChoice = ch;
        } else if (fill > secondFill) {
          secondFill = fill;
        }
      }

      // Largest-gap thresholding per item
      final liveThr = _largestGap(perItemFills, 0.40);

      // 3. Determine color
      final isAmbiguous = bestFill < liveThr || (bestFill - secondFill).abs() < 0.08;
      Color color;
      if (isAmbiguous || correct == null) {
        color = const Color(0xFFFFD600); // Yellow
      } else if (bestChoice == correct) {
        color = const Color(0xFF00E676); // Green
      } else {
        color = const Color(0xFFFF1744); // Red
      }

      // Use the chosen bubble position for overlay
      final chosenChoice = (bestChoice != '?' && choices.contains(bestChoice)) ? bestChoice : choices.first;
      final chosenCoord = itemData[chosenChoice] as Map<String, dynamic>?;
      if (chosenCoord != null) {
        final cxMm = (chosenCoord['cx_mm'] as num?)?.toDouble() ?? 0;
        final cyMm = (chosenCoord['cy_spec_mm'] as num?)?.toDouble() ?? 0;
        final px = _applyHomography(inv, cxMm, cyMm);

        overlayData.add(BubbleOverlayData(
          position: Offset(px.x / frame.width, px.y / frame.height),
          color: color,
        ));
      }
    }

    return overlayData;
  }

  static double _sampleLuminanceCircle(Uint8List bytes, int stride, int w, int h, int cx, int cy, int r) {
    int total = 0, filled = 0;
    for (int dy = -r; dy <= r; dy++) {
      final xSpan = sqrt(r * r - dy * dy).round();
      final y = cy + dy;
      if (y < 0 || y >= h) continue;
      for (int dx = -xSpan; dx <= xSpan; dx++) {
        final x = cx + dx;
        if (x < 0 || x >= w) continue;
        total++;
        if (bytes[y * stride + x] < 100) filled++;
      }
    }
    return total > 0 ? filled / total : 0;
  }

  /// Run a full diagnostic sweep on a camera frame.
  static ScannerDiagnostics runDiagnostics(CameraImage frame, {int lockedCorners = 0}) {
    final glare = estimateGlare(frame);
    final sharpness = estimateSharpness(frame);
    return ScannerDiagnostics.fromScores(
      glare: glare,
      sharpness: sharpness,
      lockedCorners: lockedCorners,
    );
  }
}

// Internal types
class _FPoint { final double x, y; _FPoint(this.x, this.y); }
class _Blob { final double cx, cy; _Blob({required this.cx, required this.cy}); }
class _CornerRegion {
  final int rx, ry, rw, rh;
  /// Outer corner tip this ROI belongs to (image coords) — used for scoring.
  final int ax, ay;
  _CornerRegion({
    required this.rx,
    required this.ry,
    required this.rw,
    required this.rh,
    required this.ax,
    required this.ay,
  });
}
class _Pix { final int x, y; _Pix(this.x, this.y); }
class _PointDist { final _FPoint point; final double dist; _PointDist(this.point, this.dist); }
