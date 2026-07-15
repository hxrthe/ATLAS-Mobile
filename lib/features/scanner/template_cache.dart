import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../grading/models.dart';

class TemplateCache {
  static const _key = 'cached_templates';
  static const _fetchedAt = 'cached_templates_fetched_at';

  static Future<void> store(List<BubbleTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final list = templates.map((t) => _toJson(t)).toList();
    await prefs.setString(_key, jsonEncode(list));
    await prefs.setInt(_fetchedAt, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<BubbleTemplate>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((j) => _fromJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastFetched() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_fetchedAt);
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_fetchedAt);
  }

  static Map<String, dynamic> _toJson(BubbleTemplate t) => {
    'template_id': t.templateId,
    'course_id': t.courseId,
    'assessment_id': t.assessmentId,
    'name': t.name,
    'total_items': t.totalItems,
    'num_choices': t.numChoices,
    'has_answer_key': t.hasAnswerKey,
    'answer_key': t.answerKey,
    'layout_metadata': t.layoutMetadata,
    'parts': t.parts.map((p) => {'label': p.label, 'start_item': p.startItem, 'end_item': p.endItem}).toList(),
    'has_essay': t.hasEssay,
    'essay_lines': t.essayLines,
    'passing_score': t.passingScore,
  };

  static BubbleTemplate _fromJson(Map<String, dynamic> j) => BubbleTemplate.fromJson(j);
}
