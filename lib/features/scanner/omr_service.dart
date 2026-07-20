import 'dart:convert';
import 'package:dio/dio.dart';
import '../grading/models.dart';
import 'omr_engine.dart';
import 'omr_models.dart';

/// Client for the Python OMR FastAPI server.
/// Primary path: Python OpenCV (reliable). Fallback: on-device Dart (if server unreachable).
class OmrService {
  static const String _defaultBaseUrl = 'http://192.168.1.3:8001';
  static const Duration _timeout = Duration(seconds: 6);

  final Dio _dio;
  final String baseUrl;
  bool _serverChecked = false;
  bool _serverAvailable = false;

  OmrService({String? baseUrl})
      : baseUrl = baseUrl ?? _defaultBaseUrl,
        _dio = Dio(BaseOptions(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
        ));

  /// Quick health check to see if Python server is reachable.
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

  /// Use the local engine whenever the network is weak or the server cannot respond quickly.
  Future<bool> shouldUseLocalEngine() async {
    final available = await isServerAvailable();
    if (!available) return true;

    try {
      final stopwatch = Stopwatch()..start();
      await _dio.get(
        '$baseUrl/api/omr/health',
        options: Options(responseType: ResponseType.json),
      );
      stopwatch.stop();
      return stopwatch.elapsed > const Duration(milliseconds: 1500);
    } catch (_) {
      return true;
    }
  }

  /// Scan an OMR image using the Python server.
  /// Falls back to on-device Dart engine if server is unreachable.
  Future<OmrResult> scanImage(
    String imagePath,
    BubbleTemplate template, {
    String? studentId,
  }) async {
    final useLocal = await shouldUseLocalEngine();

    if (useLocal) {
      return OmrEngine.processScan(imagePath, template, studentId: studentId);
    }

    try {
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

      return _parseOmrResult(response.data as Map<String, dynamic>);
    } catch (e) {
      // Server error — fallback to on-device
      return OmrEngine.processScan(imagePath, template, studentId: studentId);
    }
  }

  /// Parse Python server JSON into OmrResult.
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
