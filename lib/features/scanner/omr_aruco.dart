import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'omr_constants.dart';

class ArucoHit {
  final int id;
  final double cx;
  final double cy;
  final int hamming;
  ArucoHit(this.id, this.cx, this.cy, this.hamming);
}

/// Detect OpenCV DICT_4X4_50 markers 0–3 by sampling a 6×6 grid on dark squares.
class OmrAruco {
  static final _rotated = _buildRotations();

  static Map<int, List<List<List<int>>>> _buildRotations() {
    final out = <int, List<List<List<int>>>>{};
    OmrConstants.arucoInner.forEach((id, bits) {
      var cur = bits;
      final rots = <List<List<int>>>[];
      for (var i = 0; i < 4; i++) {
        rots.add(cur);
        cur = _rot90(cur);
      }
      out[id] = rots;
    });
    return out;
  }

  static List<List<int>> _rot90(List<List<int>> m) {
    final n = m.length;
    return List.generate(n, (c) => List.generate(n, (r) => m[n - 1 - r][c]));
  }

  /// Returns map id → center in image pixels. Empty / partial if not all found.
  static Map<int, ArucoHit> detect(img.Image src) {
    final gray = src.numChannels == 1 ? src : img.grayscale(src);
    img.Image work = gray;
    var scale = 1.0;
    const maxW = 1600;
    if (work.width > maxW) {
      scale = work.width / maxW;
      final nh = max(40, (work.height / scale).round());
      work = img.copyResize(work, width: maxW, height: nh);
    }

    final candidates = _squareBlobs(work);
    final best = <int, ArucoHit>{};
    for (final b in candidates) {
      final decoded = _decodeImg(work, b);
      if (decoded == null) continue;
      final hit = ArucoHit(
        decoded.$1,
        b.cx * scale,
        b.cy * scale,
        decoded.$2,
      );
      final prev = best[hit.id];
      if (prev == null || hit.hamming < prev.hamming) {
        best[hit.id] = hit;
      }
    }
    return best;
  }

  /// Fast live-camera path: packed 8-bit luma, tightly packed `w * h`.
  static Map<int, ArucoHit> detectLuma(Uint8List luma, int w, int h) {
    if (luma.length < w * h || w < 16 || h < 16) return {};

    final visited = Uint8List(w * h);
    final best = <int, ArucoHit>{};
    const dark = 118;
    final minSide = max(6, min(w, h) ~/ 60);
    final maxSide = max(minSide + 1, min(w, h) ~/ 4);
    final maxPixels = maxSide * maxSide * 2;

    final qx = <int>[];
    final qy = <int>[];

    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final i = row + x;
        if (visited[i] != 0) continue;
        if (luma[i] > dark) {
          visited[i] = 1;
          continue;
        }

        qx
          ..clear()
          ..add(x);
        qy
          ..clear()
          ..add(y);
        visited[i] = 1;

        var minX = x, maxX = x, minY = y, maxY = y;
        var count = 0;
        var qh = 0;
        while (qh < qx.length) {
          final px = qx[qh];
          final py = qy[qh];
          qh++;
          count++;
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;
          for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nx = px + d.$1;
            final ny = py + d.$2;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final ni = ny * w + nx;
            if (visited[ni] != 0) continue;
            visited[ni] = 1;
            if (luma[ni] <= dark) {
              qx.add(nx);
              qy.add(ny);
            }
          }
        }

        if (count > maxPixels) continue;
        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        if (bw < minSide ||
            bh < minSide ||
            bw > maxSide ||
            bh > maxSide) {
          continue;
        }
        final aspect = bw / bh;
        if (aspect < 0.68 || aspect > 1.48) continue;
        final fill = count / (bw * bh);
        if (fill < 0.28 || fill > 0.94) continue;

        final blob = _Blob(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          cx: (minX + maxX) / 2.0,
          cy: (minY + maxY) / 2.0,
        );
        final decoded = _decodeLum(
          (ix, iy) => luma[iy * w + ix],
          w,
          h,
          blob,
          maxHamming: 3,
        );
        if (decoded == null) continue;
        final hit = ArucoHit(decoded.$1, blob.cx, blob.cy, decoded.$2);
        final prev = best[hit.id];
        if (prev == null || hit.hamming < prev.hamming) {
          best[hit.id] = hit;
        }
        if (best.length == 4) return best;
      }
    }
    return best;
  }

  /// Same detector as the live camera, on a still JPEG / decoded image.
  /// Downsamples to a live-preview scale so 12MP captures do not fall through
  /// to page-contour (which grabs laptop lids, screens, and table edges).
  static Map<int, ArucoHit> detectOnImage(
    img.Image src, {
    int targetLongSide = 960,
  }) {
    final w0 = src.width;
    final h0 = src.height;
    if (w0 < 16 || h0 < 16) return {};
    final longSide = max(w0, h0);
    final step = longSide > targetLongSide
        ? max(1, (longSide / targetLongSide).round())
        : 1;
    final w = max(40, w0 ~/ step);
    final h = max(40, h0 ~/ step);
    final luma = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final sy = min(y * step, h0 - 1);
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final sx = min(x * step, w0 - 1);
        luma[row + x] = img.getLuminance(src.getPixel(sx, sy)).toInt();
      }
    }
    final hits = detectLuma(luma, w, h);
    final scaled = <int, ArucoHit>{};
    hits.forEach((id, hit) {
      scaled[id] = ArucoHit(id, hit.cx * step, hit.cy * step, hit.hamming);
    });
    return completeMissingCorner(scaled);
  }

  /// Infer one missing ID from the other three (parallelogram).
  static Map<int, ArucoHit> completeMissingCorner(Map<int, ArucoHit> hits) {
    if (hits.length != 3) return hits;
    const ids = [0, 1, 2, 3];
    final missing = ids.firstWhere((id) => !hits.containsKey(id));
    final h0 = hits[0];
    final h1 = hits[1];
    final h2 = hits[2];
    final h3 = hits[3];
    final (cx, cy) = switch (missing) {
      0 => (h1!.cx + h3!.cx - h2!.cx, h1.cy + h3.cy - h2.cy),
      1 => (h0!.cx + h2!.cx - h3!.cx, h0.cy + h2.cy - h3.cy),
      2 => (h1!.cx + h3!.cx - h0!.cx, h1.cy + h3.cy - h0.cy),
      _ => (h0!.cx + h2!.cx - h1!.cx, h0.cy + h2.cy - h1.cy),
    };
    final out = Map<int, ArucoHit>.from(hits);
    out[missing] = ArucoHit(missing, cx, cy, 9);
    return out;
  }

  static bool hasAllFour(Map<int, ArucoHit> hits) =>
      hits.containsKey(0) &&
      hits.containsKey(1) &&
      hits.containsKey(2) &&
      hits.containsKey(3);

  static List<_Blob> _squareBlobs(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    final visited = List.generate(h, (_) => List.filled(w, false));
    final blobs = <_Blob>[];
    final minSide = max(10, min(w, h) ~/ 40);
    final maxSide = max(minSide + 1, min(w, h) ~/ 4);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (visited[y][x]) continue;
        final lum = img.getLuminance(gray.getPixel(x, y)).toInt();
        if (lum > 110) {
          visited[y][x] = true;
          continue;
        }
        var minX = x, maxX = x, minY = y, maxY = y;
        var count = 0;
        final q = <(int, int)>[(x, y)];
        visited[y][x] = true;
        while (q.isNotEmpty) {
          final (px, py) = q.removeLast();
          count++;
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;
          for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final nx = px + d.$1;
            final ny = py + d.$2;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (visited[ny][nx]) continue;
            visited[ny][nx] = true;
            if (img.getLuminance(gray.getPixel(nx, ny)).toInt() <= 110) {
              q.add((nx, ny));
            }
          }
        }
        final bw = maxX - minX + 1;
        final bh = maxY - minY + 1;
        if (bw < minSide || bh < minSide || bw > maxSide || bh > maxSide) {
          continue;
        }
        final aspect = bw / bh;
        if (aspect < 0.72 || aspect > 1.38) continue;
        final fill = count / (bw * bh);
        if (fill < 0.28 || fill > 0.92) continue;
        blobs.add(_Blob(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          cx: (minX + maxX) / 2.0,
          cy: (minY + maxY) / 2.0,
        ));
      }
    }
    return blobs;
  }

  static (int id, int hamming)? _decodeImg(img.Image gray, _Blob b) =>
      _decodeLum(
        (x, y) => img.getLuminance(gray.getPixel(x, y)).toInt(),
        gray.width,
        gray.height,
        b,
      );

  static (int id, int hamming)? _decodeLum(
    int Function(int x, int y) lum,
    int width,
    int height,
    _Blob b, {
    int maxHamming = 2,
  }) {
    const modules = 6;
    final bw = (b.maxX - b.minX + 1).toDouble();
    final bh = (b.maxY - b.minY + 1).toDouble();
    // Tiny inset — keep samples inside the marker, not on surrounding paper.
    final pad = min(bw, bh) < 36 ? 0.0 : 0.06;
    final x0 = b.minX + bw * pad;
    final y0 = b.minY + bh * pad;
    final x1 = b.maxX + 1 - bw * pad;
    final y1 = b.maxY + 1 - bh * pad;
    final cellW = (x1 - x0) / modules;
    final cellH = (y1 - y0) / modules;
    final grid = List.generate(modules, (_) => List.filled(modules, 0));
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        final sx = x0 + (col + 0.5) * cellW;
        final sy = y0 + (row + 0.5) * cellH;
        var sum = 0;
        var n = 0;
        final r = max(0, (min(cellW, cellH) * 0.18).floor());
        for (var dy = -r; dy <= r; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            final ix = (sx + dx).round().clamp(b.minX, b.maxX);
            final iy = (sy + dy).round().clamp(b.minY, b.maxY);
            if (ix < 0 || iy < 0 || ix >= width || iy >= height) continue;
            sum += lum(ix, iy);
            n++;
          }
        }
        final mean = n == 0 ? 255 : sum / n;
        grid[row][col] = mean < 128 ? 0 : 1; // 0 black, 1 white
      }
    }

    var borderDark = 0;
    var borderTotal = 0;
    for (var i = 0; i < modules; i++) {
      for (final rc in [
        [0, i],
        [modules - 1, i],
        [i, 0],
        [i, modules - 1],
      ]) {
        borderTotal++;
        if (grid[rc[0]][rc[1]] == 0) borderDark++;
      }
    }
    if (borderTotal == 0 || borderDark / borderTotal < 0.7) return null;

    final inner = List.generate(
      4,
      (r) => List.generate(4, (c) => grid[r + 1][c + 1]),
    );

    var bestId = -1;
    var bestHam = 17;
    _rotated.forEach((id, rots) {
      for (final rot in rots) {
        var ham = 0;
        for (var r = 0; r < 4; r++) {
          for (var c = 0; c < 4; c++) {
            if (rot[r][c] != inner[r][c]) ham++;
          }
        }
        if (ham < bestHam) {
          bestHam = ham;
          bestId = id;
        }
      }
    });
    if (bestId < 0 || bestHam > maxHamming) return null;
    return (bestId, bestHam);
  }
}

class _Blob {
  final int minX, maxX, minY, maxY;
  final double cx, cy;
  _Blob({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.cx,
    required this.cy,
  });
}
