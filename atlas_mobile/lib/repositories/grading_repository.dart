import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
// Don't forget to import your models and API constants!
import '../models/grading_models.dart';
import '../core/network/api_constants.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GradingRepository {

  /// Fetches the template blueprint containing the answer key and layout coordinates.
  Future<BubbleSheetTemplate> fetchTemplateBlueprint(String templateId, String accessToken) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/grading/bubble/templates/$templateId/');

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $accessToken',
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      return BubbleSheetTemplate.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load template blueprint');
    }
  }

  /// Uploads the locally graded result (Client-Side Scanning via PATCH).
  Future<bool> uploadLocalScanResult({
    required String scanId,
    required String studentIdentifier,
    required Map<String, String> responses,
    required String accessToken,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/grading/bubble/scans/$scanId/');

    final response = await http.patch(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "student_identifier": studentIdentifier,
        "responses": responses,
      }),
    );

    return response.statusCode == 200 || response.statusCode == 204;
  }

  /// Uploads a scanned bubble sheet image to the ATLAS backend for processing.
  Future<BubbleSheetScanResult> uploadExamScan({
    required String templateId,
    required File imageFile,
    required String accessToken,
  }) async {

    // Replace with your Ngrok or deployed URL
    final uri = Uri.parse('${ApiConstants.baseUrl}/grading/bubble-sheet/scan/');

    // Create a multipart request
    var request = http.MultipartRequest('POST', uri);

    // 1. Attach the headers (JWT Auth)
    request.headers.addAll({
      'Authorization': 'Bearer $accessToken',
      'Accept': 'application/json',
    });

    // 2. Attach the Template ID (Text Field)
    request.fields['template_id'] = templateId;

    // 3. Attach the Image File
    var imageStream = http.ByteStream(imageFile.openRead());
    var length = await imageFile.length();

    var multipartFile = http.MultipartFile(
      'image', // This strictly matches the serializer's 'image' key
      imageStream,
      length,
      filename: imageFile.path.split('/').last,
    );

    request.files.add(multipartFile);

    // 4. Send the request and wait for the OMR engine to process
    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return BubbleSheetScanResult.fromJson(data);
    } else {
      throw Exception('Failed to process scan: ${response.body}');
    }
  }
}