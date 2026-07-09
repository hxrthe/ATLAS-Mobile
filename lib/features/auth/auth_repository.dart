import 'package:shared_preferences/shared_preferences.dart';

class AuthRepository {

  /// Simulates a login request. Returns the user role if successful.
  Future<String> login({
    required String email,
    required String password,
  }) async {
    try {
      await Future.delayed(const Duration(seconds: 2));

      final prefs = await SharedPreferences.getInstance();

      // Faculty Login Check
      if (email == 'admin@g.batstate-u.edu.ph' && password == '021424admin') {
        await prefs.setString('access_token', 'mock_faculty_token_777');
        return 'faculty';
      }
      // Student Login Check
      else if (email == 'student@g.batstate-u.edu.ph' && password == '021424student') {
        await prefs.setString('access_token', 'mock_student_token_111');
        return 'student';
      }
      else {
        throw Exception('Invalid institutional email or password.');
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }
}