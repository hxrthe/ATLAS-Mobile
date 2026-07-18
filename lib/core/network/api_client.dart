import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/login_screen.dart';

/// Resolves the API base URL depending on the platform:
/// - Uses ngrok tunnel for all platforms so the app works from anywhere.
/// - Fallback: localhost / 10.0.2.2 for local dev without ngrok.
String _resolveBaseUrl() {
  // When using ngrok, use the same public URL for all platforms.
  return 'https://platinoid-sandra-endocentric.ngrok-free.dev/api/';
}

class ApiClient {
  late Dio dio;
  static final String baseUrl = _resolveBaseUrl();
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ));

    _initializeInterceptors();
  }

  void _initializeInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // Don't try to refresh on the login endpoint itself
          if (e.response?.statusCode == 401 && e.requestOptions.path != '/auth/token/') {
            final refreshed = await _tryRefreshToken();
            if (refreshed) {
              final retryOptions = e.requestOptions;
              final prefs = await SharedPreferences.getInstance();
              final newToken = prefs.getString('access_token');
              if (newToken != null) {
                retryOptions.headers['Authorization'] = 'Bearer $newToken';
              }
              try {
                final response = await dio.fetch(retryOptions);
                return handler.resolve(response);
              } catch (retryError) {
                return handler.next(e);
              }
            } else {
              // Refresh failed or no refresh token - logout user
              await _forceLogout();
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  Future<void> _forceLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');

    // Use navigatorKey to redirect to LoginScreen
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const LoginScreen(autoLogout: true),
        ),
        (route) => false,
      );
    }
  }

  Future<bool> _tryRefreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');
      if (refreshToken == null) return false;

      final response = await Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      )).post('/auth/token/refresh/', data: {'refresh': refreshToken});

      final access = response.data['access'] as String?;
      if (access != null) {
        await prefs.setString('access_token', access);
        return true;
      }
    } catch (_) {
      // refresh failed — user must log in again
    }
    return false;
  }
}
