import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'omr_models.dart';

/// Local persistent store for scan history used by the Review Papers screen
/// and for offline batch upload queue.
///
/// Review Papers only shows scans from the current ISO calendar week
/// (Monday 00:00:00 – Sunday 23:59:59.999 local).
/// Uploaded rows from prior weeks are pruned automatically on load/refresh;
/// not-yet-uploaded rows are kept for offline sync but hidden from Review Papers.
class ScanHistory {
  static const _key = 'scan_history';
  static const _weekStampKey = 'scan_history_week_start';

  /// Monday 00:00:00 local of the week that contains [now].
  /// If today is Monday, the start is today at 00:00:00.
  static DateTime currentWeekStart([DateTime? now]) {
    final n = now ?? DateTime.now();
    final day = DateTime(n.year, n.month, n.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// Sunday 23:59:59.999 local — start + 6 days 23:59:59.999.
  static DateTime currentWeekEnd([DateTime? now]) {
    final start = currentWeekStart(now);
    return start.add(const Duration(
      days: 6,
      hours: 23,
      minutes: 59,
      seconds: 59,
      milliseconds: 999,
    ));
  }

  /// Next Monday 00:00:00 local after the current week's start.
  static DateTime nextWeekStart([DateTime? now]) =>
      currentWeekStart(now).add(const Duration(days: 7));

  /// `start <= dt <= end` for the current Mon–Sun week.
  static bool isInCurrentWeek(DateTime dt, [DateTime? now]) {
    final start = currentWeekStart(now);
    final end = currentWeekEnd(now);
    return !dt.isBefore(start) && !dt.isAfter(end);
  }

  static String _weekStampValue(DateTime start) =>
      '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';

  static bool _isPendingUpload(ScanRecord r) =>
      r.serverScanId == null || r.serverScanId!.isEmpty;

  /// Drops uploaded scans from previous weeks and updates the week stamp.
  /// Pending uploads are retained so offline sync can still send them.
  static Future<int> pruneOlderThanCurrentWeek([DateTime? now]) async {
    final start = currentWeekStart(now);
    final stamp = _weekStampValue(start);
    final prefs = await SharedPreferences.getInstance();
    final all = await getAll();
    final kept = all
        .where((r) => !r.createdAt.isBefore(start) || _isPendingUpload(r))
        .toList();
    final pruned = all.length - kept.length;
    final prevStamp = prefs.getString(_weekStampKey);
    final weekChanged = prevStamp != stamp;
    if (pruned > 0) {
      await _save(prefs, kept);
    }
    if (weekChanged) {
      await prefs.setString(_weekStampKey, stamp);
    }
    return pruned;
  }

  /// True when the persisted week stamp does not match this week's Monday.
  static Future<bool> hasWeekRolledOver([DateTime? now]) async {
    final prefs = await SharedPreferences.getInstance();
    final stamp = prefs.getString(_weekStampKey);
    if (stamp == null) return true;
    return stamp != _weekStampValue(currentWeekStart(now));
  }

  static Future<void> addRecord(ScanRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await pruneOlderThanCurrentWeek();
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

  /// Scans from this week only, newest first. Prunes stale uploaded rows first.
  static Future<List<ScanRecord>> getRecent({int count = 50}) async {
    await pruneOlderThanCurrentWeek();
    final all = await getAll();
    final recent = all.where((r) => isInCurrentWeek(r.createdAt)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return recent.take(count).toList();
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
      answerKey: updates['answer_key'] is Map
          ? Map<String, String>.from(
              (updates['answer_key'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            )
          : old.answerKey,
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
      isQuickExam: old.isQuickExam,
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
    await prefs.remove(_weekStampKey);
  }

  static Future<void> _save(SharedPreferences prefs, List<ScanRecord> records) async {
    final list = records.map((r) => r.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}
