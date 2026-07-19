import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/network/api_client.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Logs in against POST /api/auth/token/ and returns the user role.
  Future<String> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        'auth/token/',
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected server response. Please try again.');
      }

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

  /// Extract a human-readable error from a DioException response.
  String _parseError(DioException e, String fallback) {
    final data = e.response?.data;
    if (data == null) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Cannot reach the server. Check your connection.';
      }
      return fallback;
    }
    if (data is Map<String, dynamic>) {
      // Common single-message keys
      for (final key in ['detail', 'message', 'error']) {
        if (data[key] != null) return data[key].toString();
      }
      // Nested field errors, e.g. {"email": ["not found"]}
      for (final entry in data.entries) {
        if (entry.key == 'status_code' || entry.key == 'success') continue;
        final value = entry.value;
        if (value is List && value.isNotEmpty) {
          return '${entry.key}: ${value.first}';
        } else if (value is String && value.isNotEmpty) {
          return value;
        }
      }
    }
    return fallback;
  }

  /// Request a password reset code
  Future<void> requestPasswordReset(String email) async {
    try {
      final response = await _apiClient.dio.post(
        'auth/password-reset/request/',
        data: {'email': email.trim().toLowerCase()},
      );
      // Some backends return a message on success — check it's not an error
      final data = response.data;
      if (data is Map && data['detail'] != null && response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(data['detail'].toString());
      }
    } on DioException catch (e) {
      throw Exception(_parseError(e, 'Failed to send reset code.'));
    }
  }

  /// Verify the OTP and return a reset token
  Future<String> verifyPasswordResetOtp(String email, String otp) async {
    try {
      final response = await _apiClient.dio.post(
        'auth/password-reset/verify/',
        data: {
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
        },
      );
      final resetToken = response.data['reset_token'] as String?;
      if (resetToken == null) throw Exception('No reset token returned.');
      return resetToken;
    } on DioException catch (e) {
      throw Exception(_parseError(e, 'Invalid or expired OTP.'));
    }
  }

  /// Confirm the new password using the reset token
  Future<void> confirmPasswordReset(String resetToken, String newPassword) async {
    try {
      await _apiClient.dio.post(
        'auth/password-reset/confirm/',
        data: {
          'reset_token': resetToken,
          'new_password': newPassword,
        },
      );
    } on DioException catch (e) {
      throw Exception(_parseError(e, 'Failed to reset password.'));
    }
  }

  Future<Map<String, dynamic>> loginWithGoogle() async {
    try {
      // Your Web Client ID serves as the server client ID for Android
      const String webClientId = '140618226788-lt31psljafm1en4n3aajo054thn5kfin.apps.googleusercontent.com';

      // Use the singleton instance and initialize it
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        serverClientId: webClientId,
      );

      final GoogleSignInAccount googleUser = await googleSignIn.authenticate();
      
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      
      // Access token is now obtained via the authorization client in 7.2.0
      // FIX: Scopes cannot be null or empty
      final authz = await googleUser.authorizationClient.authorizationForScopes(['email', 'profile']);
      final String? accessToken = authz?.accessToken;

      if (idToken == null) {
        throw Exception('Native Google Sign-In failed: Missing ID Token.');
      }

      final AuthResponse response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final session = response.session;
      final supabaseUser = response.user;

      if (session == null || supabaseUser == null) {
        throw Exception('Supabase Sign-In failed.');
      }

      // --- NEW STEP: Sync with custom backend to get the correct role and backend tokens ---
      // This prevents the instant logout and ensures "faculty" role is respected.
      final backendResp = await _apiClient.dio.post(
        'auth/google/',
        data: {'id_token': idToken},
      );

      final data = backendResp.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected server response. Please try again.');
      }

      // Backend indicates no user with this email exists in your DB
      if (data['user_exists'] == false) {
        return {
          'user_exists': false,
          'email': data['email']?.toString() ?? supabaseUser.email ?? '',
          'name': data['name']?.toString() ?? supabaseUser.userMetadata?['full_name'] ?? '',
        };
      }

      final backendAccessToken = data['access'] as String?;
      final backendRefreshToken = data['refresh'] as String?;
      final user = data['user'] as Map<String, dynamic>?;

      if (backendAccessToken == null) {
        throw Exception('Backend synchronization failed — no access token returned.');
      }

      // Persist BACKEND session to SharedPreferences (NOT Supabase session)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', backendAccessToken);
      if (backendRefreshToken != null) {
        await prefs.setString('refresh_token', backendRefreshToken);
      }

      // Map backend User data to app expectations
      final String name = user?['name']?.toString() ?? supabaseUser.userMetadata?['full_name'] ?? 'User';
      final String role = user?['role']?.toString() ?? 'student';

      await prefs.setString('user_name', name);
      await prefs.setString('user_email', user?['email']?.toString() ?? supabaseUser.email ?? '');
      await prefs.setString('user_role', role);
      await prefs.setString('user_id', user?['user_id']?.toString() ?? supabaseUser.id);

      if (user?['student_details'] != null) {
        await prefs.setString('student_details', jsonEncode(user?['student_details']));
      }

      return {
        'user_exists': true,
        'role': role,
      };
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<String> signup({
    required String email,
    required String password,
    required String name,
    required String studentId,
    required String course,
    required String section,
    required String yearLevel,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        'auth/register/',
        data: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'name': name.trim(),
          'student_id': studentId.trim(),
          'course': course.trim(),
          'section': section.trim(),
          'year_level': yearLevel.trim(),
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected server response. Please try again.');
      }

      final accessToken = data['access'] as String?;
      final refreshToken = data['refresh'] as String?;
      final user = data['user'] as Map<String, dynamic>?;

      if (accessToken == null) {
        throw Exception('Signup failed — no access token returned.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', accessToken);
      if (refreshToken != null) {
        await prefs.setString('refresh_token', refreshToken);
      }

      if (user != null) {
        await prefs.setString('user_name', user['name']?.toString() ?? '');
        await prefs.setString('user_email', user['email']?.toString() ?? '');
        await prefs.setString('user_role', user['role']?.toString() ?? 'student');
        await prefs.setString('user_id', user['user_id']?.toString() ?? '');
        if (user['student_details'] != null) {
          await prefs.setString('student_details', jsonEncode(user['student_details']));
        }
      }

      return user?['role']?.toString() ?? 'student';
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw Exception('An account with this email already exists.');
      }
      throw Exception(
        e.response?.data?['detail'] ?? _parseError(e, 'Signup failed. Try again.'),
      );
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }
}
