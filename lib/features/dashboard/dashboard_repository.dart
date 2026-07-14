import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/dashboard_models.dart';

class DashboardRepository {
  final String baseUrl = 'http://10.0.2.2:8000/api';

  Future<Map<String, List<dynamic>>> fetchFacultyData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null) throw Exception('No access token found. Please log in again.');

    final response = await http.get(
      Uri.parse('$baseUrl/faculty/dashboard/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // The VIP pass!
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      // Convert the JSON lists into Dart objects
      final courses = (data['courses'] as List)
          .map((courseJson) => Course.fromJson(courseJson))
          .toList();

      final assessments = (data['active_assessments'] as List)
          .map((assessmentJson) => Assessment.fromJson(assessmentJson))
          .toList();

      return {
        'courses': courses,
        'assessments': assessments,
      };
    } else if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      throw Exception('Failed to load dashboard data.');
    }
  }

  Future<Map<String, List<dynamic>>> fetchStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null) throw Exception('No access token found. Please log in again.');

    final response = await http.get(
      Uri.parse('$baseUrl/student/dashboard/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);

      final courses = (data['enrolled_courses'] as List)
          .map((courseJson) => Course.fromJson(courseJson))
          .toList();

      final grades = (data['recent_grades'] as List)
          .map((gradeJson) => StudentGrade.fromJson(gradeJson))
          .toList();

      return {
        'courses': courses,
        'grades': grades,
      };
    } else if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      throw Exception('Failed to load student data.');
    }
  }

}