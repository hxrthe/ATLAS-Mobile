import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'omr_models.dart';

/// Local persistent store for scan history used by the Review Papers screen
/// and for offline batch upload queue.
class ScanHistory {
  static const _key = 'scan_history';

  static Future<void> addRecord(ScanRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    all.add(record);
    await _save(prefs, all);
  }

  static Future<List<ScanRecord>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((j) => ScanRecord.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<ScanRecord>> getRecent({int count = 50}) async {
    final all = await getAll();
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.take(count).toList();
  }

  static Future<List<ScanRecord>> getByTemplate(String templateId) async {
    final all = await getAll();
    return all.where((r) => r.templateId == templateId).toList();
  }

  static Future<List<ScanRecord>> getPendingUpload() async {
    final all = await getAll();
    return all.where((r) => r.serverScanId == null || r.serverScanId!.isEmpty).toList();
  }

  static Future<void> updateRecord(String id, Map<String, dynamic> updates) async {
    final all = await getAll();
    final idx = all.indexWhere((r) => r.id == id);
    if (idx < 0) return;

    final old = all[idx];
    final updated = ScanRecord(
      id: old.id,
      templateId: updates['template_id'] as String? ?? old.templateId,
      templateName: updates['template_name'] as String? ?? old.templateName,
      studentIdentifier: updates['student_identifier'] as String? ?? old.studentIdentifier,
      responses: updates['responses'] is Map<String, String>
          ? Map<String, String>.from(updates['responses'])
          : old.responses,
      scorePercent: (updates['score_percent'] as num?)?.toDouble() ?? old.scorePercent,
      scoreRaw: (updates['score_raw'] as num?)?.toDouble() ?? old.scoreRaw,
      maxScore: (updates['max_score'] as num?)?.toDouble() ?? old.maxScore,
      isFlagged: updates['is_flagged'] as bool? ?? old.isFlagged,
      flagReason: updates['flag_reason'] as String? ?? old.flagReason,
      flaggedItems: updates['flagged_items'] is List
          ? List<int>.from(updates['flagged_items'])
          : old.flaggedItems,
      imagePath: updates['image_path'] as String? ?? old.imagePath,
      createdAt: old.createdAt,
      serverScanId: updates['server_scan_id'] as String? ?? old.serverScanId,
    );

    all[idx] = updated;
    final prefs = await SharedPreferences.getInstance();
    await _save(prefs, all);
  }

  static Future<void> removeRecord(String id) async {
    final all = await getAll();
    all.removeWhere((r) => r.id == id);
    final prefs = await SharedPreferences.getInstance();
    await _save(prefs, all);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _save(SharedPreferences prefs, List<ScanRecord> records) async {
    final list = records.map((r) => r.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}
