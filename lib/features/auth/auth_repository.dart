import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();

  static const String _facultyOnlyMessage =
      'This app is for faculty only. Create your faculty account on the ATLAS website, then sign in here.';

  void _ensureFacultyRole(String? role) {
    if (role != 'faculty') {
      throw Exception(_facultyOnlyMessage);
    }
  }

  Future<void> _persistProfile({
    required SharedPreferences prefs,
    required String role,
    Map<String, dynamic>? user,
    String? fallbackName,
    String? fallbackEmail,
    String? photoUrl,
  }) async {
    await prefs.setString(
      'user_name',
      user?['name']?.toString() ?? fallbackName ?? '',
    );
    await prefs.setString(
      'user_email',
      user?['email']?.toString() ?? fallbackEmail ?? '',
    );
    await prefs.setString('user_role', role);
    await prefs.setString('user_id', user?['user_id']?.toString() ?? '');

    String? savedPhoto;
    for (final candidate in [photoUrl, user?['picture_url']?.toString()]) {
      final url = candidate?.trim() ?? '';
      if (url.isNotEmpty) {
        savedPhoto = url;
        break;
      }
    }
    if (savedPhoto != null) {
      await prefs.setString('user_photo_url', savedPhoto);
    } else {
      await prefs.remove('user_photo_url');
    }
  }

  String? _pictureFromIdToken(String? idToken) {
    if (idToken == null || idToken.isEmpty) return null;
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map && payload['picture'] is String) {
        return payload['picture'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// Web OAuth client ID — required as [GoogleSignIn.initialize] `serverClientId`
  /// so Android can mint an ID token the backend can verify.
  static const String _googleWebClientId =
      '140618226788-lt31psljafm1en4n3aajo054thn5kfin.apps.googleusercontent.com';

  static Future<void>? _googleInit;

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

      final role = user?['role']?.toString() ?? '';
      _ensureFacultyRole(role);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', accessToken);
      if (refreshToken != null) {
        await prefs.setString('refresh_token', refreshToken);
      }

      await _persistProfile(prefs: prefs, role: role, user: user);

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
    await prefs.setString('logout_type', 'intentional');
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('student_details');
    await prefs.remove('user_photo_url');
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

  Future<void> _ensureGoogleInitialized() async {
    final existing = _googleInit;
    if (existing != null) {
      await existing;
      return;
    }
    final future = GoogleSignIn.instance.initialize(
      serverClientId: _googleWebClientId,
    );
    _googleInit = future;
    try {
      await future;
    } catch (_) {
      _googleInit = null;
      rethrow;
    }
  }

  static const String androidPackage = 'com.example.atlas_mobile';
  static const String debugSha1 =
      '77:1B:4E:E6:52:80:AB:4E:CD:BC:E0:2A:F8:04:9D:1B:BF:BB:E8:8B';

  String _googleSignInError(GoogleSignInException e) {
    debugPrint(
      'GoogleSignInException code=${e.code} description=${e.description} details=${e.details}',
    );
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        // Credential Manager reports "canceled" for SHA-1 / package mismatches.
        return 'GOOGLE_OAUTH_CONFIG: Android Credential Manager rejected sign-in. '
            'Create an Android OAuth client for package $androidPackage with SHA-1 $debugSha1 '
            'in Google Cloud Console (project 140618226788), then wait a few minutes and try again.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'GOOGLE_OAUTH_CONFIG: Google Sign-In is not configured for this app. '
            'Register package $androidPackage with SHA-1 $debugSha1 in Google Cloud Console.';
      default:
        return e.description?.isNotEmpty == true
            ? e.description!
            : 'Google Sign-In failed. Please try again.';
    }
  }

  Future<Map<String, dynamic>> loginWithGoogle() async {
    try {
      await _ensureGoogleInitialized();

      final GoogleSignInAccount googleUser =
          await GoogleSignIn.instance.authenticate();
      final String? idToken = googleUser.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google Sign-In failed: missing ID token.');
      }

      final backendResp = await _apiClient.dio.post(
        'auth/google/',
        data: {'id_token': idToken},
      );

      final data = backendResp.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Unexpected server response. Please try again.');
      }

      if (data['user_exists'] == false) {
        throw Exception(_facultyOnlyMessage);
      }

      final backendAccessToken = data['access'] as String?;
      final backendRefreshToken = data['refresh'] as String?;
      final user = data['user'] as Map<String, dynamic>?;

      if (backendAccessToken == null) {
        throw Exception('Backend synchronization failed — no access token returned.');
      }

      final String role = user?['role']?.toString() ?? '';
      _ensureFacultyRole(role);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', backendAccessToken);
      if (backendRefreshToken != null) {
        await prefs.setString('refresh_token', backendRefreshToken);
      }

      final String name = user?['name']?.toString() ?? googleUser.displayName ?? 'User';

      await _persistProfile(
        prefs: prefs,
        role: role,
        user: user,
        fallbackName: name,
        fallbackEmail: googleUser.email,
        photoUrl: googleUser.photoUrl ?? _pictureFromIdToken(idToken),
      );

      return {
        'role': role,
      };
    } on GoogleSignInException catch (e) {
      throw Exception(_googleSignInError(e));
    } on DioException catch (e) {
      throw Exception(_parseError(e, 'Google sign-in failed.'));
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }
}
