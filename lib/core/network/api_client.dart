import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/login_screen.dart';

/// Render backend (public). For local dev, swap to ngrok or http://10.0.2.2:8000/api/
const String _renderApiBaseUrl = 'https://atlas-rcch.onrender.com/api/';

String _resolveBaseUrl() {
  return _renderApiBaseUrl;
}

class ApiClient {
  late Dio dio;
  static final String baseUrl = _resolveBaseUrl();
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 90),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
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
          // Retry on connection errors or 502 (Render cold start / wake-up)
          final isRetryable = e.type == DioExceptionType.connectionError ||
              e.response?.statusCode == 502;

          if (isRetryable && e.requestOptions.extra['_retried'] != true) {
            e.requestOptions.extra['_retried'] = true;

            await Future.delayed(const Duration(seconds: 3));

            try {
              final retryResponse = await dio.fetch(e.requestOptions);
              return handler.resolve(retryResponse);
            } catch (_) {
              // If retry fails, continue to default error handling
            }
          }

          // Don't try to refresh on the login endpoint itself
          if (e.response?.statusCode == 401 && e.requestOptions.path != 'auth/token/') {
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

    // If the user intentionally logged out, the settings tab already handles
    // navigation — don't override with the autoLogout message.
    final isIntentional = prefs.getString('logout_type') == 'intentional';
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('logout_type');

    if (isIntentional) return;

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
        connectTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90),
        headers: {
          'Content-Type': 'application/json',
        },
      )).post('auth/token/refresh/', data: {'refresh': refreshToken});

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
