import 'dart:convert';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'models.dart';

class GradingRepository {
  final ApiClient _apiClient = ApiClient();

  /// Fetch all bubble sheet templates for a course.
  Future<List<BubbleTemplate>> fetchTemplates(String courseId) async {
    final response = await _apiClient.dio.get(
      'grading/bubble/templates/',
      queryParameters: {'course_id': courseId},
    );

    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to fetch templates.');
    }

    return (data['templates'] as List<dynamic>)
        .map((t) => BubbleTemplate.fromJson(t))
        .toList();
  }

  /// Fetch a template by its linked assessment ID.
  Future<BubbleTemplate> fetchTemplateByAssessment(
    String assessmentId, {
    String? courseId,
  }) async {
    final response = await _apiClient.dio.get(
      'grading/bubble/templates/',
      queryParameters: {
        'assessment_id': assessmentId,
        if (courseId != null && courseId.isNotEmpty) 'course_id': courseId,
      },
    );

    final data = response.data;
    final templates = (data['templates'] as List? ?? [])
        .map((t) => BubbleTemplate.fromJson(Map<String, dynamic>.from(t as Map)))
        .where((t) => t.assessmentId == assessmentId)
        .toList();
    if (data['success'] != true || templates.isEmpty) {
      throw Exception(data['detail'] ?? 'Template for assessment not found.');
    }
    return templates.first;
  }

  /// Fetch a single template detail (includes answer_key and layout_metadata).
  Future<BubbleTemplate> fetchTemplateDetail(String templateId) async {
    final response = await _apiClient.dio.get(
      'grading/bubble/templates/$templateId/',
    );

    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to fetch template detail.');
    }

    return BubbleTemplate.fromJson(data['template']);
  }

  /// Submit a scanned bubble sheet image for server-side OMR and grading.
  Future<BubbleScan> submitScan(String templateId, String imagePath) async {
    final formData = FormData.fromMap({
      'template_id': templateId,
      'image': await MultipartFile.fromFile(imagePath, filename: 'scan.jpg'),
    });

    final response = await _apiClient.dio.post(
      '/grading/bubble/scans/',
      data: formData,
    );

    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to submit scan.');
    }

    return BubbleScan.fromJson(data['scan']);
  }

  /// Fetch all scans for a template.
  Future<List<BubbleScan>> fetchScans(String templateId,
      {bool? flaggedOnly}) async {
    final queryParams = <String, dynamic>{};
    if (flaggedOnly == true) {
      queryParams['flagged'] = '1';
    }

    final response = await _apiClient.dio.get(
      'grading/bubble/templates/$templateId/scans/',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to fetch scans.');
    }

    return (data['scans'] as List<dynamic>)
        .map((s) => BubbleScan.fromJson(s))
        .toList();
  }

  /// PATCH a scan (e.g., manual correction of responses).
  Future<BubbleScan> updateScan(
      String scanId, Map<String, dynamic> updates) async {
    final response = await _apiClient.dio.patch(
      'grading/bubble/scans/$scanId/',
      data: updates,
    );

    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to update scan.');
    }

    return BubbleScan.fromJson(data['scan']);
  }

  /// Upload a locally-graded scan in one POST (client_graded) so the row
  /// appears on faculty web grading results without depending on server OpenCV.
  Future<BubbleScan> uploadGradedScan({
    required String templateId,
    required String imagePath,
    String? studentId,
    required Map<String, String> responses,
    bool? isFlagged,
    String? flagReason,
  }) async {
    final truncatedReason = (flagReason != null && flagReason.isNotEmpty)
        ? (flagReason.length > 255
            ? '${flagReason.substring(0, 254)}…'
            : flagReason)
        : null;

    final formData = FormData.fromMap({
      'template_id': templateId,
      'image': await MultipartFile.fromFile(imagePath, filename: 'scan.jpg'),
      'client_graded': true,
      'responses': jsonEncode(responses),
      if (studentId != null &&
          studentId.isNotEmpty &&
          studentId != 'Unknown')
        'student_identifier': studentId,
      'is_flagged': ?isFlagged,
      'flag_reason': ?truncatedReason,
    });

    final Response postResp;
    try {
      postResp = await _apiClient.dio.post(
        'grading/bubble/scans/',
        data: formData,
      );
    } on DioException catch (e) {
      throw _sectionErrorOr(e);
    }
    if (postResp.data['success'] != true) {
      throw Exception(postResp.data['detail'] ?? 'Upload failed.');
    }

    final scanJson = postResp.data['scan'] as Map<String, dynamic>?;
    if (scanJson == null) {
      throw Exception('Upload succeeded but scan payload missing.');
    }

    // If the server ignored client_graded (older API), fall back to PATCH.
    final source = postResp.data['source']?.toString();
    if (source != 'client_graded') {
      final scanId = scanJson['scan_id'];
      final Response patchResp;
      try {
        patchResp = await _apiClient.dio.patch(
          '/grading/bubble/scans/$scanId/',
          data: <String, dynamic>{
            if (studentId != null &&
                studentId.isNotEmpty &&
                studentId != 'Unknown')
              'student_identifier': studentId,
            'responses': responses,
            'is_flagged': ?isFlagged,
            'flag_reason': ?truncatedReason,
          },
        );
      } on DioException catch (e) {
        throw _sectionErrorOr(e);
      }
      if (patchResp.data['success'] != true) {
        throw Exception(patchResp.data['detail'] ?? 'Score update failed.');
      }
      return BubbleScan.fromJson(patchResp.data['scan']);
    }

    return BubbleScan.fromJson(scanJson);
  }

  Object _sectionErrorOr(DioException e) {
    final body = e.response?.data;
    if (e.response?.statusCode == 409 && body is Map) {
      final detail = body['detail']?.toString() ?? 'Student is not on any section.';
      if (body['code'] == 'student_not_in_section') {
        return StudentNotInSectionException(body['student_id']?.toString(), detail);
      }
      if (body['code'] == 'student_in_other_section' && body['block'] is Map) {
        return StudentInOtherSectionException(
          StudentBlock.fromJson(Map<String, dynamic>.from(body['block'] as Map)),
          detail,
        );
      }
    }
    return e;
  }

  /// Students assigned to a section (keyed by student ID) and the selectable sections.
  Future<({Map<String, StudentBlock> blocks, List<SectionOption> sections})>
      fetchSectionedBlocks({String? studentId}) async {
    try {
      final response = await _apiClient.dio.get(
        'grading/blocks/',
        queryParameters: {'student_id': ?studentId},
      );
      final blocks = response.data['blocks'] as List<dynamic>? ?? [];
      final sections = response.data['sections'] as List<dynamic>? ?? [];
      return (
        blocks: {
          for (final b in blocks)
            (b['student_id'] ?? '').toString():
                StudentBlock.fromJson(Map<String, dynamic>.from(b as Map)),
        },
        sections: sections
            .map((s) => SectionOption.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
    } on DioException catch (e) {
      throw _sectionErrorOr(e);
    }
  }

  /// Add a student ID to a section (by [sectionId], or by a new [sectionName])
  /// and link that section to [courseId].
  Future<StudentBlock> addStudentToSection({
    required String studentId,
    String? sectionId,
    String? sectionName,
    String? gradeLevel,
    String? courseId,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        'grading/blocks/',
        data: {
          'student_id': studentId,
          if (sectionId != null && sectionId.isNotEmpty) 'section_id': sectionId,
          if (sectionName != null && sectionName.isNotEmpty) 'section': sectionName,
          if (gradeLevel != null && gradeLevel.isNotEmpty) 'grade_level': gradeLevel,
          if (courseId != null && courseId.isNotEmpty) 'course_id': courseId,
        },
      );
      return StudentBlock.fromJson(
        Map<String, dynamic>.from(response.data['block'] as Map),
      );
    } on DioException catch (e) {
      final mapped = _sectionErrorOr(e);
      if (mapped is DioException) {
        final body = mapped.response?.data;
        if (body is Map && body['detail'] != null) {
          throw Exception(body['detail'].toString());
        }
      }
      throw mapped;
    }
  }

  /// Batch-upload locally-graded scans when connectivity is available.
  Future<List<BubbleScan>> uploadBatch({
    required List<String> imagePaths,
    required String templateId,
    required List<String?> studentIds,
    required List<Map<String, String>> responsesList,
  }) async {
    final results = <BubbleScan>[];
    for (int i = 0; i < imagePaths.length; i++) {
      try {
        final scan = await uploadGradedScan(
          templateId: templateId,
          imagePath: imagePaths[i],
          studentId: studentIds[i],
          responses: responsesList[i],
        );
        results.add(scan);
      } catch (_) {
        // Skip failed uploads; caller can inspect results.length
      }
    }
    return results;
  }

  /// Trigger a server-side re-extraction of answer_key from linked assessment items.
  Future<BubbleTemplate> syncKeyFromAssessment(String templateId) async {
    final response = await _apiClient.dio.post(
      'grading/bubble/templates/$templateId/sync-key/',
    );

    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to sync answer key.');
    }

    return BubbleTemplate.fromJson(data['template']);
  }

  /// Update the passing score for a bubble template.
  Future<BubbleTemplate> updateTemplatePassingScore(
      String templateId, double passingScore, String courseId) async {
    final scoreRounded = double.parse(passingScore.toStringAsFixed(2));

    try {
      final response = await _apiClient.dio.patch(
        'grading/bubble/templates/$templateId/',
        data: {
          'passing_score': scoreRounded,
          'course_id': courseId,
        },
      );

      final data = response.data;
      final templateJson = data['template'] ?? data;
      return BubbleTemplate.fromJson(templateJson);
    } catch (e) {
      // Handle both DioException (from interceptor chain) and plain Exception
      String detail = 'Failed to update passing score.';
      if (e is DioException) {
        final body = e.response?.data;
        if (body is Map) {
          detail = body['detail']?.toString() ??
              body['passing_score']?.toString() ??
              body.values.first?.toString() ??
              detail;
        } else if (e.message != null && e.message!.isNotEmpty) {
          detail = e.message!;
        }
      } else {
        detail = e.toString().replaceAll('Exception: ', '');
      }
      throw Exception(detail);
    }
  }

  /// DELETE a scan.
  Future<void> deleteScan(String scanId) async {
    final response = await _apiClient.dio.delete(
      'grading/bubble/scans/$scanId/',
    );

    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to delete scan.');
    }
  }

  /// Fetch course list for the faculty user via dashboard summary.
  Future<List<Map<String, dynamic>>> fetchFacultyCourses() async {
    final response = await _apiClient.dio.get('auth/dashboard/summary/');
    final data = response.data;

    final recent =
        data['courses'] as List<dynamic>? ?? data['recent'] as List<dynamic>? ?? [];
    return recent
        .map((item) => {
              'course_id': item['course_id'] ?? '',
              'course_code': item['course_code'] ?? '',
              'course_title': item['course_title'] ?? '',
              'section': item['section'] ?? '',
            })
        .toList();
  }

  /// Fetch all assessments for a course.
  Future<List<Map<String, dynamic>>> fetchAssessments(String courseId) async {
    final response = await _apiClient.dio.get(
      'assessment/assessments/',
      queryParameters: {'course_id': courseId},
    );
    final data = response.data;
    final items = data['assessments'] as List<dynamic>? ?? data['results'] as List<dynamic>? ?? [];
    return items
        .map((a) => {
              'assessment_id': a['assessment_id'] ?? '',
              'title': a['title'] ?? '',
              'assessment_type': a['assessment_type'] ?? '',
              'term': a['term'] ?? '',
              'status': a['status'] ?? '',
            })
        .toList();
  }

  /// Scans on the faculty's courses between [from] and [to] (inclusive days),
  /// newest first, with section, score and pass/fail.
  Future<List<Map<String, dynamic>>> fetchScansInRange({
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final response = await _apiClient.dio.get(
        'grading/scans/recent/',
        queryParameters: {
          'date_from': ?(from == null ? null : day(from)),
          'date_to': ?(to == null ? null : day(to)),
          'limit': limit,
        },
      );
      return (response.data['scans'] as List<dynamic>? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      final start = from == null ? null : DateTime(from.year, from.month, from.day);
      final end = to == null ? null : DateTime(to.year, to.month, to.day + 1);
      final all = await fetchRecentScans(limit: limit);
      return all.where((s) {
        final at = DateTime.tryParse(s['created_at']?.toString() ?? '')?.toLocal();
        if (at == null) return false;
        if (start != null && at.isBefore(start)) return false;
        if (end != null && !at.isBefore(end)) return false;
        return true;
      }).toList();
    }
  }

  /// Fetch all scans (with timestamp) across templates for system events.
  Future<List<Map<String, dynamic>>> fetchRecentScans({int limit = 20}) async {
    try {
      // Fetch scans for each course's first template
      final courses = await fetchFacultyCourses();
      final allScans = <Map<String, dynamic>>[];
      for (final c in courses) {
        try {
          final templates = await fetchTemplates(c['course_id']!);
          for (final t in templates) {
            final scans = await fetchScans(t.templateId);
            for (final s in scans) {
              allScans.add({
                'scan_id': s.scanId,
                'student_id': s.studentIdentifier,
                'template_name': t.name,
                'course_code': c['course_code'],
                'course_title': c['course_title'],
                'score_percent': s.scorePercent,
                'created_at': s.createdAt,
                'is_flagged': s.isFlagged,
              });
            }
          }
        } catch (_) {}
      }
      allScans.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
      return allScans.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch assessment items with Bloom level data for analytics.
  Future<List<Map<String, dynamic>>> fetchAssessmentItems(String assessmentId) async {
    final response = await _apiClient.dio.get(
      '/assessment/assessments/$assessmentId/items/',
    );
    final data = response.data;
    final items = data['items'] as List<dynamic>? ?? data['results'] as List<dynamic>? ?? [];
    return items
        .map((i) => {
              'item_id': i['item_id'] ?? '',
              'question_text': i['question_text'] ?? '',
              'difficulty': i['difficulty'] ?? '',
              'rubric': i['rubric'] is Map ? i['rubric'] : <String, dynamic>{},
            })
        .toList();
  }

  /// Distinct sections (from `blocks`) of students in the faculty's courses.
  Future<List<String>> fetchSections({String? courseId}) async {
    try {
      final response = await _apiClient.dio.get(
        'grading/sections/',
        queryParameters: {'course_id': ?courseId},
      );
      final data = response.data;
      final sections = data['sections'] as List<dynamic>? ?? [];
      return sections.map((s) => s.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Descriptive analytics for the Reports tab (pass rates, Bloom, item analysis).
  Future<Map<String, dynamic>> fetchReports({
    String? courseId,
    String? assessmentId,
    String? gradeLevel,
    String? section,
  }) async {
    final response = await _apiClient.dio.get(
      'grading/reports/',
      queryParameters: {
        'course_id': ?courseId,
        'assessment_id': ?assessmentId,
        'grade_level': ?gradeLevel,
        'section': ?section,
      },
    );
    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw Exception((data is Map ? data['detail'] : null) ?? 'Failed to load reports.');
    }
    return Map<String, dynamic>.from(data);
  }

  /// Upper/lower 27% item analysis for one template: `summary` (KR-20, means,
  /// decisions) and per-item `items` (P, D, point-biserial, distractors).
  Future<Map<String, dynamic>> fetchItemAnalysis(
    String templateId, {
    String? gradeLevel,
    String? section,
  }) async {
    final response = await _apiClient.dio.get(
      'grading/bubble/templates/$templateId/item-analysis/',
      queryParameters: {
        'grade_level': ?gradeLevel,
        'section': ?section,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Fetch course workspace (all assessments, modules, course info).
  Future<Map<String, dynamic>> fetchCourseWorkspace(String courseId) async {
    final response = await _apiClient.dio.get(
      '/curriculum/faculty-course-workspace/$courseId/',
    );
    return response.data as Map<String, dynamic>;
  }

  /// Fetch enrolled students for a course from student_data.
  /// Returns list with user_id, sr_code, and courses_enrolled per student.
  Future<List<Map<String, dynamic>>> fetchCourseStudents(String courseId) async {
    try {
      final response = await _apiClient.dio.get(
        '/curriculum/course-students/$courseId/',
      );
      final data = response.data;
      if (data['success'] == true) {
        final students = data['students'] as List<dynamic>? ?? [];
        return students.map((s) => s as Map<String, dynamic>).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetch full assessment detail with items grouped by section.
  Future<Map<String, dynamic>> fetchAssessmentDetail(String assessmentId) async {
    final response = await _apiClient.dio.get(
      '/curriculum/assessment/$assessmentId/',
    );
    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to fetch assessment detail.');
    }
    return data['assessment'] as Map<String, dynamic>;
  }

  /// Fetch student scores for a course and assessment.
  Future<Map<String, dynamic>> fetchStudentScores(
      String courseId, String assessmentId) async {
    final response = await _apiClient.dio.get(
      '/grading/student-scores/',
      queryParameters: {'course_id': courseId, 'assessment_id': assessmentId},
    );
    final data = response.data;
    if (data['success'] != true) {
      throw Exception(data['detail'] ?? 'Failed to fetch student scores.');
    }
    return data;
  }

  /// Update an assessment item's answer via PATCH.
  Future<void> updateAssessmentItem(
      String itemId, Map<String, dynamic> updates) async {
    await _apiClient.dio.patch(
      '/curriculum/assessment-item/$itemId/',
      data: updates,
    );
  }

  /// Fetch current user profile.
  Future<Map<String, dynamic>> fetchMyProfile() async {
    final response = await _apiClient.dio.get('auth/me/');
    return response.data as Map<String, dynamic>;
  }

  /// Update current user profile (name, email).
  Future<void> updateProfile(Map<String, dynamic> updates) async {
    await _apiClient.dio.patch('auth/me/', data: updates);
  }

  /// Request password reset OTP.
  Future<void> requestPasswordReset(String email) async {
    await _apiClient.dio.post('auth/password-reset/request/', data: {'email': email});
  }

  /// Verify password reset OTP.
  Future<String> verifyPasswordResetOtp(String email, String otp) async {
    final response = await _apiClient.dio.post(
      'auth/password-reset/verify/',
      data: {'email': email, 'otp': otp},
    );
    return response.data['reset_token'] as String;
  }

  /// Confirm password reset with new password.
  Future<void> confirmPasswordReset(String resetToken, String newPassword) async {
    await _apiClient.dio.post(
      'auth/password-reset/confirm/',
      data: {'reset_token': resetToken, 'new_password': newPassword},
    );
  }
}
