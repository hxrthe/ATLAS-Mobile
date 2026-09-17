import 'dart:math';
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
      final decoded = _decode(work, b);
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

  static (int id, int hamming)? _decode(img.Image gray, _Blob b) {
    const modules = 6;
    final pad = 0.08;
    final x0 = b.minX - (b.maxX - b.minX) * pad;
    final y0 = b.minY - (b.maxY - b.minY) * pad;
    final x1 = b.maxX + (b.maxX - b.minX) * pad;
    final y1 = b.maxY + (b.maxY - b.minY) * pad;
    final cellW = (x1 - x0) / modules;
    final cellH = (y1 - y0) / modules;
    final grid = List.generate(modules, (_) => List.filled(modules, 0));
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        final sx = x0 + (col + 0.5) * cellW;
        final sy = y0 + (row + 0.5) * cellH;
        var sum = 0;
        var n = 0;
        final r = max(1, (min(cellW, cellH) * 0.25).round());
        for (var dy = -r; dy <= r; dy++) {
          for (var dx = -r; dx <= r; dx++) {
            final ix = (sx + dx).round();
            final iy = (sy + dy).round();
            if (ix < 0 || iy < 0 || ix >= gray.width || iy >= gray.height) {
              continue;
            }
            sum += img.getLuminance(gray.getPixel(ix, iy)).toInt();
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
    if (bestId < 0 || bestHam > 2) return null;
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
