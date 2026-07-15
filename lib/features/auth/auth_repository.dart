import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();

  /// Logs in against POST /api/auth/token/ and returns the user role.
  Future<String> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/auth/token/',
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
      );

      final data = response.data;
      final accessToken = data['access'] as String?;
      final refreshToken = data['refresh'] as String?;
      final user = data['user'] as Map<String, dynamic>?;

      if (accessToken == null) {
        throw Exception('Login failed — no access token returned.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', accessToken);
      if (refreshToken != null) {
        await prefs.setString('refresh_token', refreshToken);
      }

      // Persist user profile for dashboard display
      if (user != null) {
        await prefs.setString('user_name', user['name']?.toString() ?? '');
        await prefs.setString('user_email', user['email']?.toString() ?? '');
        await prefs.setString('user_role', user['role']?.toString() ?? 'faculty');
        await prefs.setString('user_id', user['user_id']?.toString() ?? '');
        // Store student_details as JSON string for later retrieval
        if (user['student_details'] != null) {
          await prefs.setString('student_details', jsonEncode(user['student_details']));
        }
      }

      final role = user?['role']?.toString() ?? 'faculty';
      return role;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Invalid credentials. Check your email and password.');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception(
            'Cannot reach the server. Make sure the backend is running.');
      }
      throw Exception(
          e.response?.data?['detail'] ?? 'Network error. Try again.');
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }
}
