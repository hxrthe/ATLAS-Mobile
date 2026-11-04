import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/login_screen.dart';

/// Hostinger VPS production API. For local dev, swap to ngrok or http://10.0.2.2:8000/api/
const String _vpsApiBaseUrl = 'https://atlas-ph.tech/api/';

String _resolveBaseUrl() {
  return _vpsApiBaseUrl;
}

/// Short timeouts for a sync attempt. Skips the interceptor's extra retry
/// so an offline upload fails in seconds instead of minutes.
Options failFastOptions() => Options(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 25),
      extra: const {'_retried': true},
    );

class ApiClient {
  late Dio dio;
  static final String baseUrl = _resolveBaseUrl();
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static int _loginScreens = 0;
  static Future<void>? _logoutTask;
  static bool _inactivityLogout = false;

  /// The sign-in screen is already on screen, so a failed request must not open it again.
  static void loginScreenOpened() => _loginScreens++;

  static void loginScreenClosed() {
    if (_loginScreens > 0) _loginScreens--;
  }

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
          // Global JSON Content-Type breaks multipart uploads (screenshots).
          // Let Dio set multipart/form-data with the correct boundary.
          if (options.data is FormData) {
            options.headers.remove('Content-Type');
            options.headers.remove('content-type');
            options.contentType = Headers.multipartFormDataContentType;
          }
          // Binary image GETs should not advertise JSON Content-Type.
          if (options.responseType == ResponseType.bytes) {
            options.headers.remove('Content-Type');
            options.headers.remove('content-type');
            options.contentType = null;
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // Retry on connection errors or transient 502 from the reverse proxy
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

          // A request with no sign-in is not a logout. Login itself is handled by the form.
          final hadSession = e.requestOptions.headers['Authorization'] != null;
          if (e.response?.statusCode == 401 &&
              hadSession &&
              e.requestOptions.path != 'auth/token/') {
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
              await ApiClient.forceLogout();
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  /// Ends the saved sign-in. Opens the sign-in screen once.
  /// The inactivity message is only for a real idle timeout.
  static Future<void> forceLogout({bool inactivity = false}) {
    if (inactivity) _inactivityLogout = true;
    final running = _logoutTask;
    if (running != null) return running;
    final task = _performLogout();
    _logoutTask = task;
    return task.whenComplete(() {
      _logoutTask = null;
      _inactivityLogout = false;
    });
  }

  static Future<void> _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final isIntentional = prefs.getString('logout_type') == 'intentional';
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('logout_type');

    // Already on the sign-in screen, or the user chose Log Out.
    // Opening it again is what made that screen restart in a loop.
    if (isIntentional || _loginScreens > 0) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final showIdleMessage = _inactivityLogout;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => LoginScreen(autoLogout: showIdleMessage),
      ),
      (route) => false,
    );
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
