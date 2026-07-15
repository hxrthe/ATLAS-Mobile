import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  late Dio dio;
  // Replace with your actual local or cloud Django server IP
  static const String baseUrl = 'https://anemia-reflector-jingling.ngrok-free.dev';

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
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
          // Fetch the JWT token from local storage
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('access_token');

          // If the token exists, inject it into the headers
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // Here we will eventually add logic to catch 401 Unauthorized errors
          // and automatically hit Django's token refresh endpoint.
          return handler.next(e);
        },
      ),
    );
  }
}