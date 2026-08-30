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

    // Assign to corners by proximity
    final corners = [
      _FPoint(0, 0),
      _FPoint(src.width.toDouble(), 0),
      _FPoint(0, src.height.toDouble()),
      _FPoint(src.width.toDouble(), src.height.toDouble()),
    ];

    final best = List<_FPoint?>.filled(4, null);
    final bestDist = List.filled(4, double.infinity);

    for (final b in blobs) {
      for (int i = 0; i < 4; i++) {
        final dx = b.cx - corners[i].x;
        final dy = b.cy - corners[i].y;
        final d = sqrt(dx * dx + dy * dy);
        if (d < bestDist[i] && d < src.width * 0.5) {
          bestDist[i] = d;
          best[i] = _FPoint(b.cx, b.cy);
        }
      }
    }

    return best.whereType<_FPoint>().toList();
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
  /// Falls back to [fallback] if no gap ≥ 0.10.
  static double _largestGap(List<double> values, double fallback) {
    if (values.length < 2) return fallback;
    final sorted = List<double>.from(values)..sort();
    double maxGap = 0;
    double thr = fallback;
    for (int i = 1; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      if (gap > maxGap) {
        maxGap = gap;
        thr = sorted[i - 1] + gap / 2;
      }
    }
    return maxGap >= 0.10 ? thr : fallback;
  }

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

  // ── Edge-based page detection (fallback when fiducials fail) ────────────

  /// Detect the OMR sheet boundary using edge detection + contour analysis.
  /// Mirrors AndroidOMRHelper's `findPage()` and OMRChecker's `CropPage`.
  /// Returns 4 corner points (TL, TR, BL, BR) of the detected page, or null.
  static List<_FPoint>? detectPageEdges(img.Image src) {
    final w = src.width;
    final h = src.height;

    // Step 1: Preprocess for edge detection
    var processed = _blurImage(src, 3);
    processed = _normalizeImage(processed);
    processed = _truncateThreshold(processed, 200);
    processed = _normalizeImage(processed);

    // Step 2: Sobel edge detection
    final edges = sobelEdges(processed);

    // Step 3: Binary threshold on edges (keep strong edges)
    final bin = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final lum = img.getLuminance(edges.getPixel(x, y)).toInt();
        final v = lum > 55 ? 0 : 255; // inverted: dark edges = 0, rest = 255
        bin.setPixel(x, y, img.ColorInt8.rgb(v, v, v));
      }
    }

    // Step 4: Morphological close to connect broken edges
    final closed = _morphClose(bin, 5);

    // Step 5: Find contours - extract connected components
    final contours = _findContours(closed);
    if (contours.isEmpty) return null;

    // Step 6: Sort contours by area (descending), take top 5
    contours.sort((a, b) => b.length.compareTo(a.length));
    final topContours = contours.take(5);

    // Step 7: Find best quadrilateral
    for (final contour in topContours) {
      if (contour.length < 4) continue;
      final quad = _approxQuadrilateral(contour, w, h);
      if (quad != null) {
        // Validate: area must be 15%-95% of total
        final area = _polygonArea(quad);
        final ratio = area / (w * h);
        if (ratio >= 0.15 && ratio <= 0.95) {
          // Validate: roughly rectangular (max cosine < 0.35)
          if (_maxCosine(quad) < 0.35) {
            return _orderPoints(quad);
          }
        }
      }
    }

    return null;
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

  /// Contour-first sheet alignment (ShreenidhiBodas/OMR style).
  /// Prefers full-page edge quadrilateral; falls back to corner fiducial blobs.
  /// Returns corners ordered TL, TR, BL, BR.
  static ({List<_FPoint> corners, bool fromPageEdges}) detectSheetCorners(
    img.Image src,
    Map<String, dynamic> layout,
  ) {
    final pageCorners = detectPageEdges(src);
    if (pageCorners != null && pageCorners.length == 4) {
      return (corners: pageCorners, fromPageEdges: true);
    }

    final fiducials = detectFiducials(src, layout);
    if (fiducials.length >= 4) {
      return (corners: sortCorners(fiducials), fromPageEdges: false);
    }

    return (corners: fiducials, fromPageEdges: false);
  }

  /// Legacy API: contour-first, then fiducial blobs.
  static List<_FPoint> detectFiducialsRobust(img.Image src, Map<String, dynamic> layout) {
    return detectSheetCorners(src, layout).corners;
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

  /// Fast fiducial detection on a live camera frame.
  /// Returns whether each of the 4 corners is detected and their normalised positions.
  /// `scaleDown` reduces the image for speed (e.g. 4 = quarter resolution).
  /// `roi` is an optional normalized Region of Interest (0..1) to focus detection.
  static ({bool tl, bool tr, bool bl, bool br,
           double? tlx, double? tly,
           double? trx, double? tryv,
           double? blx, double? bly,
           double? brx, double? bry}) detectFiducialsFast(
    CameraImage frame, {
    int scaleDown = 4,
    Rect? roi,
  }) {
    final w = frame.width ~/ scaleDown;
    final h = frame.height ~/ scaleDown;
    if (w < 40 || h < 40) {
      return (tl: false, tr: false, bl: false, br: false,
          tlx: null, tly: null, trx: null, tryv: null,
          blx: null, bly: null, brx: null, bry: null);
    }

    // Sample Y plane at reduced resolution into a small grid
    final yPlane = frame.planes[0];
    final yRowStride = yPlane.bytesPerRow;

    // Build reduced-resolution luminance grid
    final grid = List.generate(h, (_) => List.filled(w, 0));
    for (int y = 0; y < h; y++) {
      final srcY = y * scaleDown;
      for (int x = 0; x < w; x++) {
        final srcX = x * scaleDown;
        final idx = srcY * yRowStride + srcX;
        grid[y][x] = idx < yPlane.bytes.length ? yPlane.bytes[idx] : 255;
      }
    }

    // Define search bounds based on ROI, adjusting for 90deg rotation if sensor is landscape
    double l, r, t, b;
    if (w > h && roi != null) {
      // Portrait UI (roi) -> Landscape Sensor (grid)
      // UI: Top (y=0) is sensor Right (x=w)
      // UI: Bottom (y=1) is sensor Left (x=0)
      // UI: Left (x=0) is sensor Top (y=0)
      // UI: Right (x=1) is sensor Bottom (y=h)
      
      // UI Y (top/bottom) maps to Sensor X (inverted)
      l = (1.0 - roi.bottom) * w;
      r = (1.0 - roi.top) * w;
      
      // UI X (left/right) maps to Sensor Y
      t = roi.left * h;
      b = roi.right * h;
    } else {
      l = (roi?.left ?? 0) * w;
      r = (roi?.right ?? 1) * w;
      t = (roi?.top ?? 0) * h;
      b = (roi?.bottom ?? 1) * h;
    }
    
    const cornerSizeFrac = 0.30; // Search in 30% of the ROI dimensions at each corner for maximum robustness
    final sw = (r - l) * cornerSizeFrac;
    final sh = (b - t) * cornerSizeFrac;

    final cornerRegions = [
      // Region 0: Top-Left of ROI in sensor
      _CornerRegion(rx: l.round(), ry: t.round(), rw: sw.round(), rh: sh.round()),
      // Region 1: Top-Right of ROI in sensor
      _CornerRegion(rx: (r - sw).round(), ry: t.round(), rw: sw.round(), rh: sh.round()),
      // Region 2: Bottom-Left of ROI in sensor
      _CornerRegion(rx: l.round(), ry: (b - sh).round(), rw: sw.round(), rh: sh.round()),
      // Region 3: Bottom-Right of ROI in sensor
      _CornerRegion(rx: (r - sw).round(), ry: (b - sh).round(), rw: sw.round(), rh: sh.round()),
    ];

    final results = <({bool detected, double x, double y})>[];
    for (final region in cornerRegions) {
      final result = _findDarkBlobInRegion(grid, w, h, region);
      results.add(result);
    }

    // Convert results to normalised coordinates (0–1)
    double? toNormX(double px) => px / w;
    double? toNormY(double py) => py / h;

    // Correct mapping from Sensor Regions back to UI corners (TL, TR, BL, BR)
    // Assuming 90deg rotation for landscape sensor to portrait UI
    if (w > h && roi != null) {
      // Sensor Index Mapping: 0:L,T | 1:R,T | 2:L,B | 3:R,B
      // CW 90deg Map:
      // UI TL (0,0) -> Sensor (1,0) = R,T = Index 1
      // UI TR (1,0) -> Sensor (1,1) = R,B = Index 3
      // UI BL (0,1) -> Sensor (0,0) = L,T = Index 0
      // UI BR (1,1) -> Sensor (0,1) = L,B = Index 2
      
      return (
        tl: results[1].detected, tlx: results[1].detected ? toNormX(results[1].x) : null, tly: results[1].detected ? toNormY(results[1].y) : null,
        tr: results[3].detected, trx: results[3].detected ? toNormX(results[3].x) : null, tryv: results[3].detected ? toNormY(results[3].y) : null,
        bl: results[0].detected, blx: results[0].detected ? toNormX(results[0].x) : null, bly: results[0].detected ? toNormY(results[0].y) : null,
        br: results[2].detected, brx: results[2].detected ? toNormX(results[2].x) : null, bry: results[2].detected ? toNormY(results[2].y) : null,
      );
    }

    return (
      tl: results[0].detected,
      tlx: results[0].detected ? toNormX(results[0].x) : null,
      tly: results[0].detected ? toNormY(results[0].y) : null,
      tr: results[1].detected,
      trx: results[1].detected ? toNormX(results[1].x) : null,
      tryv: results[1].detected ? toNormY(results[1].y) : null,
      bl: results[2].detected,
      blx: results[2].detected ? toNormX(results[2].x) : null,
      bly: results[2].detected ? toNormY(results[2].y) : null,
      br: results[3].detected,
      brx: results[3].detected ? toNormX(results[3].x) : null,
      bry: results[3].detected ? toNormY(results[3].y) : null,
    );
  }

  /// Finds the centroid of the darkest contiguous blob within a corner region.
  static ({bool detected, double x, double y}) _findDarkBlobInRegion(
    List<List<int>> grid, int w, int h, _CornerRegion region,
  ) {
    final visited = <int>{};
    int bestCx = 0, bestCy = 0, bestSize = 0;
    // Increased threshold to 100 for better detection in varying light and motion blur
    final darkThreshold = 100;

    final rx = region.rx.clamp(0, w - 1);
    final ry = region.ry.clamp(0, h - 1);
    final rw = region.rw;
    final rh = region.rh;

    for (int y = ry; y < (ry + rh).clamp(0, h); y++) {
      for (int x = rx; x < (rx + rw).clamp(0, w); x++) {
        final key = y * w + x;
        if (visited.contains(key)) continue;
        if (grid[y][x] > darkThreshold) continue;

        // BFS/flood fill to find blob
        final q = <_Pix>[_Pix(x, y)];
        visited.add(key);
        int blobSize = 0;
        int sumX = 0, sumY = 0;
        int minX = x, maxX = x, minY = y, maxY = y;

        while (q.isNotEmpty) {
          final p = q.removeAt(0);
          blobSize++;
          // Weighted moments: darker pixels contribute more to centroid
          // (mirrors OpenCV's moment-based centroid for sub-pixel precision)
          final darkness = (darkThreshold - grid[p.y][p.x]).clamp(1, darkThreshold);
          sumX += p.x * darkness;
          sumY += p.y * darkness;
          if (p.x < minX) minX = p.x;
          if (p.x > maxX) maxX = p.x;
          if (p.y < minY) minY = p.y;
          if (p.y > maxY) maxY = p.y;

          for (final d in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
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

        // Validate blob: must be roughly square-ish within size bounds
        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        final minDim = (w * 0.010).round().clamp(2, 20); // Even smaller min
        final maxDim = (w * 0.35).round().clamp(20, 150); // Even larger max
        // Very relaxed aspect ratio to handle extreme tilt/skew and blur stretching
        final aspectOk = bw > 0 && bh > 0 && (bw / bh).abs() >= 0.2 && (bw / bh).abs() <= 5.0;

        // Total darkness weight for normalising weighted centroid
        final totalDarkness = (() {
          int td = 0;
          for (int yy = minY; yy <= maxY; yy++) {
            for (int xx = minX; xx <= maxX; xx++) {
              if (grid[yy][xx] <= darkThreshold) {
                td += (darkThreshold - grid[yy][xx]).clamp(1, darkThreshold);
              }
            }
          }
          return td;
        })();

        if (bw >= minDim && bh >= minDim && bw <= maxDim && bh <= maxDim && aspectOk && blobSize > bestSize) {
          bestSize = blobSize;
          bestCx = totalDarkness > 0 ? (sumX / totalDarkness).round() : (sumX ~/ blobSize);
          bestCy = totalDarkness > 0 ? (sumY / totalDarkness).round() : (sumY ~/ blobSize);
        }
      }
    }

    // Lowered minimum pixel count to be extremely responsive
    if (bestSize >= 2) {
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
class _CornerRegion { final int rx, ry, rw, rh; _CornerRegion({required this.rx, required this.ry, required this.rw, required this.rh}); }
class _Pix { final int x, y; _Pix(this.x, this.y); }
class _PointDist { final _FPoint point; final double dist; _PointDist(this.point, this.dist); }
