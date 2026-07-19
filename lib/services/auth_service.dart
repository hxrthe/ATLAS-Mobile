import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = 'https://platinoid-sandra-endocentric.ngrok-free.dev/api/auth';
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Sign in with Google
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        return {'error': 'Google sign-in cancelled'};
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Get the ID token
      final String? idToken = googleAuth.idToken;
      
      if (idToken == null) {
        return {'error': 'Failed to get ID token'};
      }

      // Send the ID token to your backend
      final response = await http.post(
        Uri.parse('$baseUrl/google/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'credential': idToken,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Store tokens securely
        await _storage.write(key: 'access_token', value: data['access']);
        await _storage.write(key: 'refresh_token', value: data['refresh']);
        
        return {
          'success': true,
          'access': data['access'],
          'refresh': data['refresh'],
          'created': data['created'] ?? false,
        };
      } else {
        return {
          'error': data['detail'] ?? 'Authentication failed',
        };
      }
    } catch (e) {
      return {'error': 'Error: $e'};
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  // Get stored access token
  Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  // Refresh access token
  Future<String?> refreshAccessToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      
      if (refreshToken == null) return null;

      final response = await http.post(
        Uri.parse('$baseUrl/token/refresh/'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'refresh': refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storage.write(key: 'access_token', value: data['access']);
        return data['access'];
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
}
