import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_constants.dart';

class AuthRepository {
  // Use 10.0.2.2 for Android Emulators.
  final String baseUrl = 'https://anemia-reflector-jingling.ngrok-free.dev';

  /// Sends the credentials to Django and retrieves the JWT securely.
  Future<Map<String, String>> login({
    required String email,
    required String password,
  }) async {
    try {
      // 1. Make the POST request to the Django Token Endpoint
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': email, // Django expects 'username'
          'password': password,
        }),
      );

      // 2. If Django says OK (200)
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        // 1. Extract the tokens AND the new custom data
        final String token = data['access'];
        final String role = data['role'] ?? 'student';
        final String name = data['name'] ?? 'Unknown User';

        // 2. Save them all to SharedPreferences so the app remembers them
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', token);
        await prefs.setString('user_role', role);
        await prefs.setString('user_name', name);

        // 3. Make sure your function returns a Map or object that includes the role
        // so your AuthBloc can update the state!
        return {
          'token': token,
          'role': role,
          'name': name,
        };
      }
      // 3. If Django rejects the password (401 Unauthorized)
      else if (response.statusCode == 401) {
        throw Exception('Invalid institutional email or password.');
      }
      // 4. Any other server error
      else {
        throw Exception('Server error. Please try again later.');
      }
    } catch (e) {
      // Catch network errors
      if (e.toString().contains('Connection refused')) {
        throw Exception('Cannot connect to the ATLAS server. Is it running?');
      }
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Clears the tokens from the device on Log Out
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }
}