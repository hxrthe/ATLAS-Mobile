import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// High-throughput grayscale warp / blur / Otsu using raw [Uint8List] buffers.
///
/// Same algorithms as OpenCV `warpPerspective` + box blur + `THRESH_BINARY_INV`,
/// without per-pixel `Image.getPixel` / `setPixel` overhead (the previous
/// multi-minute bottleneck on a full Long Bond canvas).
class OmrFastPixels {
  /// Inverse-homography warp of a grayscale source into [outW]×[outH].
  /// [inv] is a 9-element row-major 3×3 inverse homography (dst → src).
  static Uint8List warpGray({
    required Uint8List src,
    required int srcW,
    required int srcH,
    required List<double> inv,
    required int outW,
    required int outH,
  }) {
    final out = Uint8List(outW * outH);
    out.fillRange(0, out.length, 255);
    final h0 = inv[0], h1 = inv[1], h2 = inv[2];
    final h3 = inv[3], h4 = inv[4], h5 = inv[5];
    final h6 = inv[6], h7 = inv[7], h8 = inv[8];
    for (var y = 0; y < outH; y++) {
      final yd = y.toDouble();
      final row = y * outW;
      for (var x = 0; x < outW; x++) {
        final xd = x.toDouble();
        final w = h6 * xd + h7 * yd + h8;
        if (w.abs() < 1e-12) continue;
        final sx = (h0 * xd + h1 * yd + h2) / w;
        final sy = (h3 * xd + h4 * yd + h5) / w;
        final ix = sx.round();
        final iy = sy.round();
        if (ix >= 0 && iy >= 0 && ix < srcW && iy < srcH) {
          out[row + x] = src[iy * srcW + ix];
        }
      }
    }
    return out;
  }

  /// Separable box blur (odd [kernel]). OpenCV-style denoise before Otsu.
  static Uint8List boxBlur(Uint8List src, int w, int h, {int kernel = 5}) {
    final k = kernel.isOdd ? kernel : kernel + 1;
    final r = k ~/ 2;
    if (r < 1) return Uint8List.fromList(src);
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);
    final norm = 1.0 / k;

    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        var sum = 0;
        for (var dx = -r; dx <= r; dx++) {
          final xx = (x + dx).clamp(0, w - 1);
          sum += src[row + xx];
        }
        tmp[row + x] = (sum * norm).round().clamp(0, 255);
      }
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0;
        for (var dy = -r; dy <= r; dy++) {
          final yy = (y + dy).clamp(0, h - 1);
          sum += tmp[yy * w + x];
        }
        out[y * w + x] = (sum * norm).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Otsu threshold; BINARY_INV style: dark marks → 255, paper → 0.
  static Uint8List otsuBinaryInv(Uint8List src, int w, int h) {
    final hist = List<int>.filled(256, 0);
    final n = w * h;
    for (var i = 0; i < n; i++) {
      hist[src[i]]++;
    }
    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }
    var sumB = 0.0;
    var wB = 0;
    var maxVar = -1.0;
    var thr = 128;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = n - wB;
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
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = src[i] < thr ? 255 : 0;
    }
    return out;
  }

  /// Build grayscale [img.Image] from luma (for bubble samplers).
  static img.Image toGrayImage(Uint8List luma, int w, int h) {
    final out = img.Image(width: w, height: h);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = luma[i++];
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  /// Extract luma from an [img.Image] (handles gray or RGB).
  static Uint8List lumaFromImage(img.Image src) {
    final w = src.width;
    final h = src.height;
    final out = Uint8List(w * h);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out[i++] = img.getLuminance(src.getPixel(x, y)).toInt().clamp(0, 255);
      }
    }
    return out;
  }
}
