import 'dart:math';
import 'dart:typed_data';

import 'package:atlas_mobile/features/scanner/omr_aruco.dart';
import 'package:atlas_mobile/features/scanner/omr_constants.dart';
import 'package:atlas_mobile/features/scanner/omr_imaging.dart';
import 'package:atlas_mobile/features/scanner/omr_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('detectLuma finds ArUco IDs 0–3 as soon as they are in frame', () {
    const w = 480;
    const h = 640;
    const size = 48;
    final luma = Uint8List(w * h);
    luma.fillRange(0, luma.length, 255);

    _stamp(luma, w, 0, 24, 40, size);
    _stamp(luma, w, 1, w - 24 - size, 40, size);
    _stamp(luma, w, 2, w - 24 - size, h - 40 - size, size);
    _stamp(luma, w, 3, 24, h - 40 - size, size);

    final hits = OmrAruco.detectLuma(luma, w, h);
    expect(OmrAruco.hasAllFour(hits), isTrue, reason: 'hits=$hits');
    expect(hits[0]!.cx, closeTo(24 + size / 2, 6));
    expect(hits[0]!.cy, closeTo(40 + size / 2, 6));
    expect(hits[1]!.cx, closeTo(w - 24 - size / 2, 6));
    expect(hits[2]!.cy, closeTo(h - 40 - size / 2, 6));
    expect(hits[3]!.cx, closeTo(24 + size / 2, 6));
  });

  test('forced ArUco hits warp the same luma the live preview used', () {
    const w = 480;
    const h = 640;
    const size = 48;
    final luma = Uint8List(w * h);
    luma.fillRange(0, luma.length, 255);
    _stamp(luma, w, 0, 24, 40, size);
    _stamp(luma, w, 1, w - 24 - size, 40, size);
    _stamp(luma, w, 2, w - 24 - size, h - 40 - size, size);
    _stamp(luma, w, 3, 24, h - 40 - size, size);

    final hits = OmrAruco.detectLuma(luma, w, h);
    expect(OmrAruco.hasAllFour(hits), isTrue);

    final gray = OmrImaging.lumaToGray(luma, w, h);
    final prepared = OmrImaging.prepareSheetForOmr(
      gray,
      const {},
      forcedAruco: hits,
    );
    expect(prepared.method, 'aruco');
    expect(prepared.lowConfidence, isFalse);
    expect(prepared.dpi, OmrConstants.gradingDpi);
    expect(
      prepared.color.width / prepared.color.height,
      closeTo(OmrConstants.cropAspect, 0.08),
    );

    final result = OmrResult(
      responses: const {},
      readings: const [],
      correctCount: 60,
      maxScore: 60,
      scorePercent: 100,
      alignedImageBytes: Uint8List.fromList([0, 1, 2, 3]),
      alignedWidth: prepared.color.width,
      alignedHeight: prepared.color.height,
      alignmentMethod: 'aruco',
    );
    expect(result.isRectifiedSheet, isTrue);

    final jpeg = OmrImaging.alignedSheetJpeg(
      luma: luma,
      width: w,
      height: h,
      arucoXy: [
        hits[0]!.cx,
        hits[0]!.cy,
        hits[1]!.cx,
        hits[1]!.cy,
        hits[2]!.cx,
        hits[2]!.cy,
        hits[3]!.cx,
        hits[3]!.cy,
      ],
      outW: 85,
    );
    expect(jpeg, isNotNull);
    final decoded = img.decodeJpg(jpeg!);
    expect(decoded, isNotNull);
    expect(
      decoded!.width / decoded.height,
      closeTo(OmrConstants.cropAspect, 0.04),
    );

    final tlPage = (
      OmrConstants.fidCenterInsetMm / OmrConstants.pageWmm,
      OmrConstants.fidCenterTopMm / OmrConstants.pageHmm,
    );
    final tlCrop = OmrConstants.pageNormToCropNorm(tlPage.$1, tlPage.$2);
    final expected = OmrConstants.cropEdgeToCenterMm / OmrConstants.cropWmm;
    expect(tlCrop.$1, closeTo(expected, 0.02));
    expect(
      tlCrop.$2,
      closeTo(OmrConstants.cropEdgeToCenterMm / OmrConstants.cropHmm, 0.02),
    );
  });

  test('camera-still aspect is not treated as a rectified sheet', () {
    final still = OmrResult(
      responses: const {},
      readings: const [],
      correctCount: 0,
      maxScore: 1,
      scorePercent: 0,
      alignedImageBytes: Uint8List.fromList([0, 1, 2, 3]),
      alignedWidth: 4000,
      alignedHeight: 3000,
      alignmentMethod: 'aruco',
    );
    expect(still.isRectifiedSheet, isFalse);
  });

  test('detectLuma still decodes smaller live-preview markers', () {
    const w = 320;
    const h = 180;
    const size = 24;
    final luma = Uint8List(w * h);
    luma.fillRange(0, luma.length, 255);

    _stamp(luma, w, 0, 8, 8, size);
    _stamp(luma, w, 1, w - 8 - size, 8, size);
    _stamp(luma, w, 2, w - 8 - size, h - 8 - size, size);
    _stamp(luma, w, 3, 8, h - 8 - size, size);

    var dark = 0;
    for (final v in luma) {
      if (v <= 118) dark++;
    }

    final hits = OmrAruco.detectLuma(luma, w, h);
    expect(
      hits.keys.toSet(),
      {0, 1, 2, 3},
      reason: 'darkPixels=$dark hits=${hits.keys.toList()}',
    );
  });

  test('fiducial lock snaps on the first decoded frame', () {
    var state = FiducialLockState.initial();
    state = state.update(
      tl: true,
      tr: true,
      bl: true,
      br: true,
      tlPos: const Offset(0.2, 0.2),
      trPos: const Offset(0.8, 0.2),
      blPos: const Offset(0.2, 0.8),
      brPos: const Offset(0.8, 0.8),
      lockThresholdFrames: 1,
    );
    expect(state.allLocked, isTrue);
    expect(state.allFresh, isTrue);
    expect(state.corners.every((c) => c.locked && c.position != null), isTrue);
  });

  test('lock boxes follow a moving marker instead of freezing', () {
    var state = FiducialLockState.initial();
    state = state.update(
      tl: true,
      tr: true,
      bl: true,
      br: true,
      tlPos: const Offset(0.20, 0.20),
      trPos: const Offset(0.80, 0.20),
      blPos: const Offset(0.20, 0.80),
      brPos: const Offset(0.80, 0.80),
      lockThresholdFrames: 1,
    );
    state = state.update(
      tl: true,
      tr: true,
      bl: true,
      br: true,
      tlPos: const Offset(0.40, 0.22),
      trPos: const Offset(0.82, 0.22),
      blPos: const Offset(0.22, 0.82),
      brPos: const Offset(0.82, 0.82),
      lockThresholdFrames: 1,
    );
    expect(state.corners[0].position!.dx, closeTo(0.376, 0.02));
    expect(state.corners[0].fresh, isTrue);
  });

  test('stale lock drops instead of staying pinned on screen', () {
    var state = FiducialLockState.initial();
    state = state.update(
      tl: true,
      tr: true,
      bl: true,
      br: true,
      tlPos: const Offset(0.2, 0.2),
      trPos: const Offset(0.8, 0.2),
      blPos: const Offset(0.2, 0.8),
      brPos: const Offset(0.8, 0.8),
      lockThresholdFrames: 1,
    );
    state = state.update(
      tl: false,
      tr: false,
      bl: false,
      br: false,
      lockThresholdFrames: 1,
    );
    expect(state.allFresh, isFalse);
    expect(state.corners.every((c) => c.position == null), isTrue);
  });

  test('completeMissingCorner infers the fourth ArUco centre', () {
    final hits = {
      0: ArucoHit(0, 10, 10, 0),
      1: ArucoHit(1, 110, 10, 0),
      3: ArucoHit(3, 10, 210, 0),
    };
    final done = OmrAruco.completeMissingCorner(hits);
    expect(OmrAruco.hasAllFour(done), isTrue);
    expect(done[2]!.cx, closeTo(110, 0.1));
    expect(done[2]!.cy, closeTo(210, 0.1));
  });

  test('detectOnImage finds ArUco on a still-photo canvas', () {
    const w = 480;
    const h = 640;
    const size = 48;
    final im = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        im.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    _stampImage(im, 0, 24, 40, size);
    _stampImage(im, 1, w - 24 - size, 40, size);
    _stampImage(im, 2, w - 24 - size, h - 40 - size, size);
    _stampImage(im, 3, 24, h - 40 - size, size);

    final hits = OmrAruco.detectOnImage(im);
    expect(OmrAruco.hasAllFour(hits), isTrue, reason: 'hits=${hits.keys}');
  });
}

void _stamp(Uint8List luma, int w, int id, int x0, int y0, int size) {
  const modules = 6;
  final cell = max(1, size ~/ modules);
  final bits = OmrConstants.arucoInner[id]!;
  final side = cell * modules;
  for (var y = 0; y < side; y++) {
    final rowOff = (y0 + y) * w;
    for (var x = 0; x < side; x++) {
      luma[rowOff + x0 + x] = 20;
    }
  }
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 4; col++) {
      if (bits[row][col] == 0) continue;
      for (var y = 0; y < cell; y++) {
        final rowOff = (y0 + (row + 1) * cell + y) * w;
        for (var x = 0; x < cell; x++) {
          luma[rowOff + x0 + (col + 1) * cell + x] = 255;
        }
      }
    }
  }
}

void _stampImage(img.Image im, int id, int x0, int y0, int size) {
  const modules = 6;
  final cell = max(1, size ~/ modules);
  final bits = OmrConstants.arucoInner[id]!;
  final side = cell * modules;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      im.setPixelRgb(x0 + x, y0 + y, 20, 20, 20);
    }
  }
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 4; col++) {
      if (bits[row][col] == 0) continue;
      for (var y = 0; y < cell; y++) {
        for (var x = 0; x < cell; x++) {
          im.setPixelRgb(
            x0 + (col + 1) * cell + x,
            y0 + (row + 1) * cell + y,
            255,
            255,
            255,
          );
        }
      }
    }
  }
}
