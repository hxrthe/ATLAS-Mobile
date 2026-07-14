import 'dart:io';

class LocalOmrEngine {
  /// Instantly grades the extracted responses against the downloaded answer key.
  static Map<String, dynamic> gradeSheet({
    required Map<String, String> responses,
    required Map<String, dynamic> answerKey,
  }) {
    int correct = 0;

    // Match responses against the answer key
    answerKey.forEach((itemNo, correctAns) {
      // If the response matches the correct answer, increase score.
      // Ambiguous answers marked as "?" automatically fail this check.
      if (responses[itemNo] == correctAns) {
        correct++;
      }
    });

    double maxScore = answerKey.length.toDouble();
    double scorePercent = (correct / maxScore) * 100;

    return {
      'score_raw': correct,
      'max_score': maxScore,
      'score_percent': scorePercent,
    };
  }

  /// Extracts responses using layout_metadata coordinates.
  static Future<Map<String, String>> extractResponsesFromImage(
      File image,
      Map<String, dynamic> layoutMetadata
      ) async {
    // 1. Get DPI from fiducials: dpi = image_width_px / (page_width_pt / 72.0)
    // 2. Convert mm to px: cx_px = round(cx_mm * dpi / 25.4)
    // 3. Sample circular regions at bubble_r_px
    // 4. Calculate fill ratio (< 128 threshold)

    // TODO: Integrate opencv_dart or Google ML Kit here for pixel sampling.
    // Returning dummy data to test the UI and grading math immediately.
    return {
      "1": "A",
      "2": "C",
      "3": "B",
      "4": "?", // Example of a flagged/ambiguous bubble
    };
  }
}