import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class ScannerRepository {
  // Use 10.0.2.2 for Android Emulator to connect to local Django
  final String baseUrl = 'http://10.0.2.2:8000/api';

  Future<bool> uploadAssessmentScan(String imagePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      // Create a Multipart request targeting your future Django scanning endpoint
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/scanner/upload/'),
      );

      // Attach the faculty member's authorization token
      if (token != null) {
        request.headers.addAll({
          'Authorization': 'Bearer $token',
        });
      }

      // Attach the physical image file
      request.files.add(await http.MultipartFile.fromPath('exam_sheet', imagePath));

      // Send the request and wait for Django's response
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Connection timed out. Is the Django server running?');
        },
      );
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('Upload successful: ${response.body}');
        return true;
      } else {
        debugPrint('Upload failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Network error during upload: $e');
      return false;
    }
  }
}