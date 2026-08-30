import 'dart:convert';
import 'package:dio/dio.dart';
import '../grading/models.dart';
import 'omr_engine.dart';
import 'omr_models.dart';

/// OMR scan client.
///
/// Primary: on-device hybrid pipeline (contour page detect → Otsu → mask fill).
/// Optional: Python OpenCV sidecar when [preferPythonServer] is true and reachable.
class OmrService {
  static const String _defaultBaseUrl = 'http://192.168.1.3:8001';
  static const Duration _timeout = Duration(seconds: 30);

  final Dio _dio;
  final String baseUrl;
  final bool preferPythonServer;
  bool _serverChecked = false;
  bool _serverAvailable = false;

  OmrService({
    String? baseUrl,
    this.preferPythonServer = false,
  })  : baseUrl = baseUrl ?? _defaultBaseUrl,
        _dio = Dio(BaseOptions(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
        ));

  Future<bool> isServerAvailable() async {
    if (_serverChecked) return _serverAvailable;
    try {
      final response = await _dio.get(
        '$baseUrl/api/omr/health',
        options: Options(responseType: ResponseType.json),
      );
      _serverAvailable = response.statusCode == 200;
    } catch (_) {
      _serverAvailable = false;
    }
    _serverChecked = true;
    return _serverAvailable;
  }

  /// Scan an OMR image using the hybrid on-device engine by default.
  Future<OmrResult> scanImage(
    String imagePath,
    BubbleTemplate template, {
    String? studentId,
    String? assessmentId,
  }) async {
    if (preferPythonServer && await isServerAvailable()) {
      try {
        return await _scanViaPython(
          imagePath,
          template,
          studentId: studentId,
          assessmentId: assessmentId,
        );
      } catch (_) {
        // Fall through to on-device hybrid
      }
    }

    return OmrEngine.processScan(
      imagePath,
      template,
      studentId: studentId,
      assessmentId: assessmentId,
    );
  }

  Future<OmrResult> _scanViaPython(
    String imagePath,
    BubbleTemplate template, {
    String? studentId,
    String? assessmentId,
  }) async {
    final layoutJson = jsonEncode(template.layoutMetadata);
    final answerKeyJson = jsonEncode(template.answerKey);

    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(imagePath, filename: 'scan.jpg'),
      'layout_json': layoutJson,
      'answer_key_json': answerKeyJson,
    });

    final response = await _dio.post(
      '$baseUrl/api/omr/scan',
      data: formData,
      options: Options(responseType: ResponseType.json),
    );

    final result = _parseOmrResult(response.data as Map<String, dynamic>);
    if (assessmentId != null && result.assessmentId == null) {
      return OmrResult(
        studentIdentifier: result.studentIdentifier ?? studentId,
        assessmentId: assessmentId,
        responses: result.responses,
        readings: result.readings,
        correctCount: result.correctCount,
        maxScore: result.maxScore,
        scorePercent: result.scorePercent,
        isFlagged: result.isFlagged,
        flagReason: result.flagReason,
        flaggedItems: result.flaggedItems,
        processingTime: result.processingTime,
      );
    }
    return result;
  }

  OmrResult _parseOmrResult(Map<String, dynamic> json) {
    final readingsJson = json['readings'] as List<dynamic>? ?? [];
    final readings = readingsJson.map((r) {
      final m = r as Map<String, dynamic>;
      return BubbleReading(
        itemNumber: m['item_number'] ?? 0,
        detectedAnswer: m['detected_answer'] ?? '?',
        fillRatio: (m['fill_ratio'] as num?)?.toDouble() ?? 0,
        secondFillRatio: (m['second_fill_ratio'] as num?)?.toDouble(),
        isAmbiguous: m['is_ambiguous'] ?? false,
        isConfirmed: m['is_confirmed'] ?? false,
        confidenceNote: m['confidence_note'],
      );
    }).toList();

    final responses = <String, String>{};
    final rawResponses = json['responses'] as Map<String, dynamic>? ?? {};
    rawResponses.forEach((k, v) => responses[k] = v.toString());

    final flaggedItems = (json['flagged_items'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [];

    return OmrResult(
      studentIdentifier: json['student_identifier'],
      assessmentId: json['assessment_id']?.toString(),
      responses: responses,
      readings: readings,
      correctCount: json['correct_count'] ?? 0,
      maxScore: json['max_score'] ?? 0,
      scorePercent: (json['score_percent'] as num?)?.toDouble() ?? 0,
      isFlagged: json['is_flagged'] ?? false,
      flagReason: json['flag_reason'],
      flaggedItems: flaggedItems,
    );
  }
}
