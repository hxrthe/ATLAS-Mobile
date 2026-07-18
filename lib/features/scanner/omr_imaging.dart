import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Low‑level pixel operations for fiducial detection, perspective warp,
/// bubble sampling, and ID‑bubble decoding.
// ignore_for_file: library_private_types_in_public_api, curly_braces_in_flow_control_structures

class OmrImaging {
  // ── QR decode ──────────────────────────────────────────────────────────

  static Future<String?> decodeQR(String path) async {
    try {
      final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
      final input = InputImage.fromFilePath(path);
      final barcodes = await scanner.processImage(input);
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
    final rMm = (idc['bubble_r_mm'] as num?)?.toDouble() ?? 1.5; // Slightly smaller for dense grids

    final rPx = (rMm * dpi / 25.4).round();
    final labels = ['0','1','2','3','4','5','6','7','8','9','-'];

    final buf = StringBuffer();
    for (int c = 0; c < cols; c++) {
      final cx = ((x0mm + c * colPitch) * dpi / 25.4).round();

      double bestFill = 0;
      int bestRow = -1;
      
      for (int r = 0; r < labels.length; r++) {
        final cy = ((yTopMm + r * rowPitch) * dpi / 25.4).round();
        final fill = sampleCircle(warped, cx, cy, rPx);
        if (fill > bestFill) {
          bestFill = fill;
          bestRow = r;
        }
      }
      
      // Using a slightly more conservative threshold for ID bubbles
      if (bestRow != -1 && bestFill > 0.35) {
        buf.write(labels[bestRow]);
      } else {
        buf.write('?');
      }
    }

    final raw = buf.toString();
    return raw.contains('?') ? null : raw;
  }

  // ── Circle sampling ────────────────────────────────────────────────────

  /// Fraction of pixels below threshold 128 inside circle radius r at (cx,cy).
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
        if (lum < 128) filled++;
      }
    }
    return total > 0 ? filled / total : 0;
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
    return x;
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
}

// Internal types
class _FPoint { final double x, y; _FPoint(this.x, this.y); }
class _Blob { final double cx, cy; _Blob({required this.cx, required this.cy}); }
