import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../grading/models.dart';
import 'omr_aruco.dart';
import 'omr_constants.dart';
import 'omr_imaging.dart';
import 'omr_models.dart';
import 'omr_contour_bubbles.dart';

/// Payload for background isolate OMR (no ML Kit — QR decoded on UI isolate).
class OmrIsolateArgs {
  final String imagePath;
  final Map<String, dynamic> layout;
  final Map<String, String> answerKey;
  final int totalItems;
  final int numChoices;
  final String? studentId;
  final String? assessmentId;
  final String? qrAssessmentId;
  final Uint8List? gradeLuma;
  final int? gradeWidth;
  final int? gradeHeight;
  final List<double>? arucoXy;
  final bool requireSnapshot;

  const OmrIsolateArgs({
    required this.imagePath,
    required this.layout,
    required this.answerKey,
    required this.totalItems,
    required this.numChoices,
    this.studentId,
    this.assessmentId,
    this.qrAssessmentId,
    this.gradeLuma,
    this.gradeWidth,
    this.gradeHeight,
    this.arucoXy,
    this.requireSnapshot = false,
  });
}

/// Top-level entry for [Isolate.run] / [compute].
Map<String, dynamic> omrProcessInIsolate(
  OmrIsolateArgs args, {
  void Function(String status)? onProgress,
}) {
  void progress(String s) => onProgress?.call(s);
  final sw = Stopwatch()..start();
  img.Image image;
  Map<int, ArucoHit>? forcedAruco;
  final luma = args.gradeLuma;
  final gw = args.gradeWidth;
  final gh = args.gradeHeight;
  final xy = args.arucoXy;
  final snapshotOk = luma != null &&
      gw != null &&
      gh != null &&
      xy != null &&
      xy.length == 8 &&
      luma.length >= gw * gh;
  if (args.requireSnapshot && !snapshotOk) {
    throw Exception('Grade snapshot missing in isolate.');
  }
  if (snapshotOk) {
    image = OmrImaging.lumaToGray(luma!, gw!, gh!);
    forcedAruco = {
      0: ArucoHit(0, xy![0], xy[1], 0),
      1: ArucoHit(1, xy[2], xy[3], 0),
      2: ArucoHit(2, xy[4], xy[5], 0),
      3: ArucoHit(3, xy[6], xy[7], 0),
    };
  } else {
    final bytes = File(args.imagePath).readAsBytesSync();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Failed to decode image.');
    }
    image = img.bakeOrientation(decoded);
  }

  final layout = args.layout;
  final resolvedAssessmentId = args.assessmentId ?? args.qrAssessmentId;

  progress('Aligning sheet…');
  final prepared =
      OmrImaging.prepareSheetForOmr(image, layout, forcedAruco: forcedAruco);

  progress('Reading student ID…');
  final studentId = args.studentId ??
      OmrImaging.readIDBubbles(
        prepared.binary,
        layout,
        prepared.dpi,
        originXmm: prepared.cropOriginXmm,
        originYmm: prepared.cropOriginYmm,
      );

  final hasItems =
      (layout['items'] is Map) && (layout['items'] as Map).isNotEmpty;

  progress('Extracting answers…');
  final rowResults = hasItems
      ? OmrReferenceGrader.readAnswerBubblesFromTemplate(
          prepared.binary,
          prepared.gray,
          layout,
          prepared.dpi,
          args.numChoices,
          originXmm: prepared.cropOriginXmm,
          originYmm: prepared.cropOriginYmm,
        )
      : List.generate(
          args.totalItems,
          (i) => RowReadResult(
            itemNumber: i + 1,
            answer: '?',
            ambiguous: true,
          ),
        );

  final readings = OmrReferenceGrader.toBubbleReadings(
    rowResults,
    args.totalItems,
  );

  final responses = <String, String>{};
  for (final r in readings) {
    if (r.detectedAnswer != '?') {
      responses[r.itemNumber.toString()] = r.detectedAnswer;
    }
  }

  progress('Scoring answers…');
  final gr = OmrEngine.grade(responses, args.answerKey, args.totalItems);
  sw.stop();

  // Display JPEG is the capture-time ArUco crop — do not rebuild from grade canvas.
  const Uint8List? alignedJpeg = null;
  const int? alignedW = null;
  const int? alignedH = null;

  progress('Building result…');
  final markers = _buildScoredMarkers(
    layout: layout,
    answerKey: args.answerKey,
    responses: responses,
    readings: readings,
    dpi: prepared.dpi,
    imageWidth: prepared.gray.width,
    imageHeight: prepared.gray.height,
    studentId: studentId,
  );

  final flagged = readings
      .where((r) => r.isAmbiguous)
      .map((r) => r.itemNumber)
      .toList();
  final reasons = <String>[];
  if (prepared.lowConfidence) {
    reasons.add('Low-confidence alignment (${prepared.method})');
  }
  if (!hasItems) {
    reasons.add('Template missing bubble layout — regenerate PDF');
  }
  final idPartial = studentId != null && studentId.contains('?');
  if (studentId == null || idPartial) reasons.add('Student ID incomplete');
  if (flagged.isNotEmpty) {
    reasons.add('${flagged.length} invalid item(s)');
  }

  final flagReasonRaw = reasons.isEmpty ? null : reasons.join('; ');
  final flagReason = flagReasonRaw != null && flagReasonRaw.length > 255
      ? '${flagReasonRaw.substring(0, 254)}…'
      : flagReasonRaw;

  return {
    'student_identifier': studentId,
    'assessment_id': resolvedAssessmentId,
    'responses': responses,
    'readings': readings
        .map((r) => {
              'item_number': r.itemNumber,
              'detected_answer': r.detectedAnswer,
              'fill_ratio': r.fillRatio,
              'second_fill_ratio': r.secondFillRatio,
              'is_ambiguous': r.isAmbiguous,
              'is_confirmed': r.isConfirmed,
              'confidence_note': r.confidenceNote,
              'confidence_score': r.confidenceScore,
            })
        .toList(),
    'correct_count': gr.$1,
    'max_score': gr.$2,
    'score_percent': gr.$3,
    'is_flagged': reasons.isNotEmpty,
    'flag_reason': flagReason,
    'flagged_items': flagged,
    'processing_ms': sw.elapsedMilliseconds,
    'alignment': prepared.method,
    'low_confidence': prepared.lowConfidence,
    'aligned_jpeg': alignedJpeg,
    'aligned_width': alignedW,
    'aligned_height': alignedH,
    'scored_markers': markers,
  };
}

List<Map<String, dynamic>> _buildScoredMarkers({
  required Map<String, dynamic> layout,
  required Map<String, String> answerKey,
  required Map<String, String> responses,
  required List<BubbleReading> readings,
  required double dpi,
  required int imageWidth,
  required int imageHeight,
  String? studentId,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) return [];

  final out = <Map<String, dynamic>>[];
  final grid = layout['answer_grid'];
  final answerRMm = grid is Map
      ? (grid['bubble_r_mm'] as num?)?.toDouble() ?? 2.0
      : ((layout['bubble_radius_pt'] as num?)?.toDouble() ?? 5.67) * 25.4 / 72.0;

  double pageNx(double cxMm) =>
      (cxMm / OmrConstants.pageWmm).clamp(0.0, 1.0);
  double pageNy(double cyMm) =>
      (cyMm / OmrConstants.pageHmm).clamp(0.0, 1.0);

  final readingByItem = <int, BubbleReading>{
    for (final r in readings) r.itemNumber: r,
  };

  final items = layout['items'];
  if (items is Map) {
    for (final entry in answerKey.entries) {
      final itemNum = entry.key;
      final correct = entry.value;
      final detected = responses[itemNum];
      final itemNo = int.tryParse(itemNum) ?? 0;
      final reading = readingByItem[itemNo];
      final isAmbiguous = reading?.isAmbiguous == true ||
          detected == null ||
          detected.isEmpty ||
          detected == '?';
      final isCorrect = !isAmbiguous && detected == correct;

      final itemData = items[itemNum];
      if (itemData is! Map) continue;

      final markChoice = (!isAmbiguous && detected.isNotEmpty)
          ? detected
          : correct;
      final coord = itemData[markChoice] ?? itemData[correct];
      if (coord is! Map) continue;

      final cxMm = (coord['cx_mm'] as num?)?.toDouble() ?? 0;
      final cyMm = (coord['cy_spec_mm'] as num?)?.toDouble() ?? 0;

      out.add({
        'item_number': itemNo,
        'nx': pageNx(cxMm),
        'ny': pageNy(cyMm),
        'r_mm': answerRMm,
        'kind': isAmbiguous
            ? 'ambiguous'
            : (isCorrect ? 'correct' : 'wrong'),
      });
    }
  }

  final idc = layout['id_columns'];
  if (studentId != null && studentId.isNotEmpty && idc is Map) {
    const labels = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-'];
    const firstRowOffsetMm = 2.5;
    final x0mm = (idc['x0_mm'] as num?)?.toDouble() ?? 0;
    final yTopMm = (idc['y_top_spec_mm'] as num?)?.toDouble() ?? 0;
    final colPitch = (idc['col_pitch_mm'] as num?)?.toDouble() ?? 6.5;
    final rowPitch = (idc['row_pitch_mm'] as num?)?.toDouble() ?? 5.0;
    final idRMm = (idc['bubble_r_mm'] as num?)?.toDouble() ?? 1.75;
    final cols = (idc['num_cols'] as num?)?.toInt() ?? studentId.length;
    final n = min(cols, studentId.length);
    for (var c = 0; c < n; c++) {
      final ch = studentId[c];
      if (ch == '?') continue;
      final row = labels.indexOf(ch);
      if (row < 0) continue;
      final cxMm = x0mm + c * colPitch;
      final cyMm = yTopMm + firstRowOffsetMm + row * rowPitch;
      out.add({
        'item_number': -(c + 1),
        'nx': pageNx(cxMm),
        'ny': pageNy(cyMm),
        'r_mm': idRMm,
        'kind': 'id',
      });
    }
  }

  return out;
}

/// On-device OMR for ATLAS 3-column bubble sheets.
///
/// Align → student ID bubbles → answer bubbles → grade vs answer key.
/// Heavy pixel work runs in a background isolate to avoid ANR.
class OmrEngine {
  static Future<OmrResult> processScan(
    String imagePath,
    BubbleTemplate template, {
    String? studentId,
    String? assessmentId,
    OmrGradeSnapshot? gradeSnapshot,
    void Function(String status)? onProgress,
  }) async {
    final layout = template.layoutMetadata;
    if (!template.hasLayoutItems) {
      debugPrint(
        'OMR warning: template ${template.templateId} has no layout items — '
        'regenerate the PDF on the server.',
      );
    }

    // ML Kit must stay on the main/UI isolate.
    final qrRaw = await OmrImaging.decodeQR(imagePath);
    final qrAssessmentId = OmrImaging.parseAssessmentId(qrRaw);

    final snap = gradeSnapshot != null && gradeSnapshot.isComplete
        ? gradeSnapshot
        : null;
    final gradeLuma =
        snap == null ? null : Uint8List.fromList(snap.luma);
    final gradeWidth = snap?.width;
    final gradeHeight = snap?.height;
    final arucoXy =
        snap == null ? null : List<double>.from(snap.arucoXy);

    final args = OmrIsolateArgs(
      imagePath: imagePath,
      layout: Map<String, dynamic>.from(layout),
      answerKey: Map<String, String>.from(template.answerKey),
      totalItems: template.totalItems,
      numChoices: template.numChoices,
      studentId: studentId,
      assessmentId: assessmentId,
      qrAssessmentId: qrAssessmentId,
      gradeLuma: gradeLuma,
      gradeWidth: gradeWidth,
      gradeHeight: gradeHeight,
      arucoXy: arucoXy,
      requireSnapshot: snap != null,
    );

    if (onProgress == null) {
      final map = await Isolate.run(() => omrProcessInIsolate(args));
      return _resultFromMap(map);
    }

    final receive = ReceivePort();
    final errorPort = ReceivePort();
    await Isolate.spawn(
      _omrIsolateMain,
      _OmrIsolateLaunch(receive.sendPort, args),
      onError: errorPort.sendPort,
      errorsAreFatal: true,
    );
    final completer = Completer<Map<String, dynamic>>();
    late final StreamSubscription sub;
    late final StreamSubscription errSub;
    sub = receive.listen((msg) {
      if (msg is String) {
        onProgress(msg);
      } else if (msg is Map) {
        completer.complete(Map<String, dynamic>.from(msg));
      }
    });
    errSub = errorPort.listen((err) {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception(err is List ? err.first : err),
        );
      }
    });
    try {
      final map = await completer.future;
      return _resultFromMap(map);
    } finally {
      await sub.cancel();
      await errSub.cancel();
      receive.close();
      errorPort.close();
    }
  }

  static OmrResult _resultFromMap(Map<String, dynamic> map) {
    final readingsJson = map['readings'] as List<dynamic>? ?? [];
    final readings = readingsJson.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return BubbleReading(
        itemNumber: m['item_number'] as int? ?? 0,
        detectedAnswer: m['detected_answer'] as String? ?? '?',
        fillRatio: (m['fill_ratio'] as num?)?.toDouble() ?? 0,
        secondFillRatio: (m['second_fill_ratio'] as num?)?.toDouble(),
        isAmbiguous: m['is_ambiguous'] as bool? ?? false,
        isConfirmed: m['is_confirmed'] as bool? ?? false,
        confidenceNote: m['confidence_note'] as String?,
        confidenceScore: (m['confidence_score'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    final responses = <String, String>{};
    final raw = map['responses'] as Map? ?? {};
    raw.forEach((k, v) => responses[k.toString()] = v.toString());

    final flagged = (map['flagged_items'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [];

    debugPrint(
      'OMR alignment=${map['alignment']} '
      'answers=${responses.length} studentId=${map['student_identifier']}',
    );

    return OmrResult(
      studentIdentifier: map['student_identifier'] as String?,
      assessmentId: map['assessment_id'] as String?,
      responses: responses,
      readings: readings,
      correctCount: map['correct_count'] as int? ?? 0,
      maxScore: map['max_score'] as int? ?? 0,
      scorePercent: (map['score_percent'] as num?)?.toDouble() ?? 0,
      isFlagged: map['is_flagged'] as bool? ?? false,
      flagReason: map['flag_reason'] as String?,
      flaggedItems: flagged,
      processingTime: Duration(milliseconds: map['processing_ms'] as int? ?? 0),
      alignedImageBytes: map['aligned_jpeg'] is Uint8List
          ? map['aligned_jpeg'] as Uint8List
          : (map['aligned_jpeg'] is List
              ? Uint8List.fromList(List<int>.from(map['aligned_jpeg'] as List))
              : null),
      alignedWidth: (map['aligned_width'] as num?)?.toInt(),
      alignedHeight: (map['aligned_height'] as num?)?.toInt(),
      scoredMarkers: (map['scored_markers'] as List<dynamic>? ?? []).map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        return ScoredBubbleMarker(
          itemNumber: m['item_number'] as int? ?? 0,
          nx: (m['nx'] as num?)?.toDouble() ?? 0,
          ny: (m['ny'] as num?)?.toDouble() ?? 0,
          rMm: (m['r_mm'] as num?)?.toDouble() ?? 2.0,
          kind: switch (m['kind']?.toString()) {
            'id' => ScoredMarkerKind.studentId,
            'wrong' => ScoredMarkerKind.wrong,
            'ambiguous' => ScoredMarkerKind.ambiguous,
            _ => (m['is_correct'] as bool? ?? true)
                ? ScoredMarkerKind.correct
                : ScoredMarkerKind.wrong,
          },
        );
      }).toList(),
      alignmentMethod: map['alignment']?.toString() ?? 'unknown',
      lowConfidenceAlignment: map['alignment']?.toString() == 'direct' ||
          (map['low_confidence'] as bool? ?? false),
    );
  }

  static (int, int, double) grade(
    Map<String, String> responses,
    Map<String, String> answerKey,
    int totalItems,
  ) {
    final maxScore = answerKey.isNotEmpty ? answerKey.length : totalItems;
    if (answerKey.isEmpty) {
      return (0, maxScore, 0.0);
    }
    var correct = 0;
    for (final entry in answerKey.entries) {
      if (responses[entry.key] == entry.value) correct++;
    }
    final pct = maxScore > 0 ? (correct / maxScore) * 100.0 : 0.0;
    return (correct, maxScore, pct);
  }
}

class _OmrIsolateLaunch {
  final SendPort sendPort;
  final OmrIsolateArgs args;
  _OmrIsolateLaunch(this.sendPort, this.args);
}

void _omrIsolateMain(_OmrIsolateLaunch launch) {
  final map = omrProcessInIsolate(
    launch.args,
    onProgress: launch.sendPort.send,
  );
  launch.sendPort.send(map);
}
