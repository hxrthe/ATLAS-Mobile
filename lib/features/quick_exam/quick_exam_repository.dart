import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import 'quick_exam_models.dart';

/// Talks to `/api/grading/quick/…` — quick exams live in their own tables and
/// never mix with course templates, scans or reports.
class QuickExamRepository {
  final ApiClient _api = ApiClient();
  static const _base = 'grading/quick/';

  Future<Map<String, dynamic>> _call(
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final r = await send();
      final data = Map<String, dynamic>.from(r.data as Map);
      if (data['success'] == false) throw Exception(_detail(data));
      return data;
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map) throw Exception(_detail(Map<String, dynamic>.from(body)));
      rethrow;
    }
  }

  static String _detail(Map<String, dynamic> body) {
    final detail = body['detail'];
    if (detail != null) return detail is List ? detail.join(' ') : detail.toString();
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      return first is List ? first.join(' ') : first.toString();
    }
    return 'Request failed.';
  }

  // ── Subjects ────────────────────────────────────────────────────────────

  Future<List<QuickSubject>> fetchSubjects() async {
    final d = await _call(() => _api.dio.get('${_base}subjects/'));
    return (d['subjects'] as List<dynamic>? ?? [])
        .map((s) => QuickSubject.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
  }

  /// The faculty's assigned courses — the only allowed quick-exam subjects.
  Future<List<QuickCourseOption>> fetchCourseOptions() async =>
      (await fetchSubjectOptions()).courses;

  /// Saved subjects plus the faculty's assigned courses, in one request.
  Future<({List<QuickSubject> subjects, List<QuickCourseOption> courses})>
      fetchSubjectOptions() async {
    final d = await _call(() => _api.dio.get('${_base}subjects/'));
    return (
      subjects: (d['subjects'] as List<dynamic>? ?? [])
          .map((s) => QuickSubject.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
      courses: (d['courses'] as List<dynamic>? ?? [])
          .map((c) => QuickCourseOption.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
    );
  }

  Future<void> deleteSubject(String subjectId) =>
      _call(() => _api.dio.delete('${_base}subjects/$subjectId/'));

  // ── Exams ───────────────────────────────────────────────────────────────

  Future<List<QuickExam>> fetchExams({String? subjectId}) async {
    final d = await _call(() => _api.dio.get(
          '${_base}exams/',
          queryParameters: {'subject_id': ?subjectId},
        ));
    return (d['exams'] as List<dynamic>? ?? [])
        .map((e) => QuickExam.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<QuickExam> fetchExam(String examId) async {
    final d = await _call(() => _api.dio.get('${_base}exams/$examId/'));
    return QuickExam.fromJson(Map<String, dynamic>.from(d['exam'] as Map));
  }

  /// Creates or updates an exam. [body] uses the API field names.
  Future<QuickExam> saveExam(Map<String, dynamic> body, {String? examId}) async {
    final d = await _call(() => examId == null
        ? _api.dio.post('${_base}exams/', data: body)
        : _api.dio.patch('${_base}exams/$examId/', data: body));
    return QuickExam.fromJson(Map<String, dynamic>.from(d['exam'] as Map));
  }

  Future<void> deleteExam(String examId) =>
      _call(() => _api.dio.delete('${_base}exams/$examId/'));

  Future<QuickExam> saveAnswerKey(String examId, Map<String, String> key) async {
    final d = await _call(() => _api.dio.post(
          '${_base}exams/$examId/answer-key/',
          data: {'answer_key': key},
        ));
    return QuickExam.fromJson(Map<String, dynamic>.from(d['exam'] as Map));
  }

  Future<QuickExamRecords> fetchExamRecords(String examId) async {
    final d = await _call(() => _api.dio.get('${_base}exams/$examId/scans/'));
    return QuickExamRecords.fromJson(d);
  }

  // ── Scans / records ─────────────────────────────────────────────────────

  /// Saves an on-device graded sheet; the server re-grades with its key.
  /// A sheet for an already-recorded student ID replaces that record.
  Future<({QuickScan scan, bool replaced})> uploadScan({
    required String examId,
    String? studentId,
    required Map<String, String> responses,
    bool isFlagged = false,
    String? flagReason,
  }) async {
    final reason = (flagReason ?? '').isEmpty
        ? null
        : (flagReason!.length > 255 ? '${flagReason.substring(0, 254)}…' : flagReason);
    final d = await _call(() => _api.dio.post('${_base}scans/', data: {
          'exam_id': examId,
          if (studentId != null && studentId.isNotEmpty && studentId != 'Unknown')
            'student_identifier': studentId,
          'responses': responses,
          'is_flagged': isFlagged,
          'flag_reason': ?reason,
        }));
    return (
      scan: QuickScan.fromJson(Map<String, dynamic>.from(d['scan'] as Map)),
      replaced: d['replaced'] == true,
    );
  }

  Future<QuickScan> updateScan(String scanId, Map<String, dynamic> updates) async {
    final d = await _call(() => _api.dio.patch('${_base}scans/$scanId/', data: updates));
    return QuickScan.fromJson(Map<String, dynamic>.from(d['scan'] as Map));
  }

  Future<void> deleteScan(String scanId) =>
      _call(() => _api.dio.delete('${_base}scans/$scanId/'));

  Future<({int total, List<QuickScan> scans})> fetchRecords({
    String? subjectId,
    String? examId,
    String? query,
  }) async {
    final d = await _call(() => _api.dio.get('${_base}records/', queryParameters: {
          'subject_id': ?subjectId,
          'exam_id': ?examId,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        }));
    return (
      total: (d['total'] as num?)?.toInt() ?? 0,
      scans: (d['scans'] as List<dynamic>? ?? [])
          .map((s) => QuickScan.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
    );
  }
}
