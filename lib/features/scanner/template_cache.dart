import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../grading/models.dart';

/// Answer keys and sheet layouts saved on the device.
///
/// Holds web course exams and mobile major exams together. Writes are
/// serialized so a background download cannot wipe a key that was just saved.
class TemplateCache {
  static const _key = 'cached_templates';
  static const _fetchedAt = 'cached_templates_fetched_at';

  static Future<void> _queue = Future.value();
  static int _epoch = 0;

  static int get epoch => _epoch;

  static Future<T> _sync<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<void> store(List<BubbleTemplate> templates) =>
      _sync(() => _store(templates));

  static Future<void> upsert(BubbleTemplate template) => _sync(() async {
        _epoch++;
        final current = await _load() ?? <BubbleTemplate>[];
        final idx =
            current.indexWhere((t) => t.templateId == template.templateId);
        if (idx >= 0) {
          current[idx] = template;
        } else {
          current.add(template);
        }
        await _store(current);
      });

  /// Replaces every saved template for [courseId]. Other courses and major
  /// exams stay as they are.
  static Future<void> mergeCourse(
    String courseId,
    List<BubbleTemplate> fresh,
  ) =>
      _sync(() async {
        _epoch++;
        final current = await _load() ?? <BubbleTemplate>[];
        final kept = current
            .where((t) => t.isQuickExam || t.courseId != courseId)
            .toList();
        await _store([...kept, ...fresh]);
      });

  /// Replaces saved major exams when [seenEpoch] is still current.
  /// Returns false when a newer save landed while the download was in flight.
  static Future<bool> replaceQuick(
    List<BubbleTemplate> fresh,
    int seenEpoch,
  ) =>
      _sync(() async {
        if (seenEpoch != _epoch) return false;
        _epoch++;
        final current = await _load() ?? <BubbleTemplate>[];
        final kept = current.where((t) => !t.isQuickExam).toList();
        await _store([...kept, ...fresh]);
        return true;
      });

  static Future<void> remove(String templateId) => _sync(() async {
        _epoch++;
        final current = await _load() ?? <BubbleTemplate>[];
        current.removeWhere((t) => t.templateId == templateId);
        await _store(current);
      });

  static Future<List<BubbleTemplate>?> load() => _sync(_load);

  static Future<BubbleTemplate?> find(String templateId) => _sync(() async {
        final all = await _load() ?? <BubbleTemplate>[];
        final idx = all.indexWhere((t) => t.templateId == templateId);
        return idx < 0 ? null : all[idx];
      });

  static Future<DateTime?> lastFetched() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_fetchedAt);
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  static Future<void> clear() => _sync(() async {
        _epoch++;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key);
        await prefs.remove(_fetchedAt);
      });

  static Future<List<BubbleTemplate>?> _load() async {
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

  static Future<void> _store(List<BubbleTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final list = templates.map(_toJson).toList();
    await prefs.setString(_key, jsonEncode(list));
    await prefs.setInt(_fetchedAt, DateTime.now().millisecondsSinceEpoch);
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
        'parts': t.parts
            .map((p) => {
                  'label': p.label,
                  'start_item': p.startItem,
                  'end_item': p.endItem,
                })
            .toList(),
        'has_essay': t.hasEssay,
        'essay_lines': t.essayLines,
        'passing_score': t.passingScore,
        'is_quick_exam': t.isQuickExam,
        'updated_at': t.updatedAt,
      };

  /// Writes server timestamps onto templates already saved, without replacing their keys.
  static Future<void> patchUpdatedAt(Map<String, String> stamps) =>
      _sync(() async {
        if (stamps.isEmpty) return;
        final current = await _load() ?? <BubbleTemplate>[];
        var changed = false;
        final next = <BubbleTemplate>[];
        for (final template in current) {
          final stamp = stamps[template.templateId];
          if (stamp == null || stamp.isEmpty || stamp == template.updatedAt) {
            next.add(template);
            continue;
          }
          next.add(template.copyWith(updatedAt: stamp));
          changed = true;
        }
        if (changed) await _store(next);
      });

  static BubbleTemplate _fromJson(Map<String, dynamic> j) =>
      BubbleTemplate.fromJson(j);
}
