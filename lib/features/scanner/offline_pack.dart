import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/error_messages.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import '../quick_exam/quick_exam_models.dart';
import '../quick_exam/quick_exam_repository.dart';
import 'scan_history.dart';
import 'template_cache.dart';

/// A section assignment made while offline, sent when the connection returns.
class PendingSectionAdd {
  final String studentId;
  final String? sectionId;
  final String? sectionName;
  final String gradeLevel;
  final String? courseId;

  const PendingSectionAdd({
    required this.studentId,
    this.sectionId,
    this.sectionName,
    this.gradeLevel = '',
    this.courseId,
  });

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'section_id': sectionId,
        'section_name': sectionName,
        'grade_level': gradeLevel,
        'course_id': courseId,
      };

  factory PendingSectionAdd.fromJson(Map<String, dynamic> j) =>
      PendingSectionAdd(
        studentId: (j['student_id'] ?? '').toString(),
        sectionId: j['section_id']?.toString(),
        sectionName: j['section_name']?.toString(),
        gradeLevel: (j['grade_level'] ?? '').toString(),
        courseId: j['course_id']?.toString(),
      );
}

class SavedRoster {
  final Map<String, StudentBlock> blocks;
  final List<SectionOption> sections;

  const SavedRoster({required this.blocks, required this.sections});
}

/// How far the automatic save onto the phone has gotten.
class OfflineSaveProgress {
  final bool active;
  final bool finished;
  final int done;
  final int total;
  final int percent;

  const OfflineSaveProgress({
    this.active = false,
    this.finished = false,
    this.done = 0,
    this.total = 0,
    this.percent = 0,
  });

  bool get known => total > 0;

  double get fraction {
    if (percent <= 0) return 0;
    if (percent >= 100) return 1;
    return percent / 100;
  }
}

/// Files on the phone that still need to move to or from the database.
class PackAttention {
  final int pendingScans;
  final int pendingSections;
  final bool needsDownload;
  final bool busy;

  const PackAttention({
    this.pendingScans = 0,
    this.pendingSections = 0,
    this.needsDownload = false,
    this.busy = false,
  });

  bool get needsUpload => pendingScans > 0 || pendingSections > 0;
  bool get needsAttention => needsUpload || needsDownload;

  String get headline {
    if (busy) return 'Updating';
    if (needsUpload && needsDownload) return 'Send and get updates';
    if (needsUpload) return 'Send from this phone';
    return 'Get the latest copy';
  }

  String get detail {
    if (busy) return 'This will only take a moment.';
    final parts = <String>[];
    if (pendingScans == 1) {
      parts.add('1 answer sheet is saved here and has not been sent yet');
    } else if (pendingScans > 1) {
      parts.add('$pendingScans answer sheets are saved here and have not been sent yet');
    }
    if (pendingSections == 1) {
      parts.add('1 class-list change is saved here and has not been sent yet');
    } else if (pendingSections > 1) {
      parts.add(
        '$pendingSections class-list changes are saved here and have not been sent yet',
      );
    }
    if (needsDownload) {
      parts.add('Exams or class lists were changed somewhere else');
    }
    return parts.join('. ');
  }
}

/// Downloads answer keys, sheet layouts, and class sections onto the device
/// when they differ from the copy already saved. Scanning then uses this copy.
///
/// Opening the app only compares a catalog stamp. The save notice appears
/// when files are actually written.
class OfflinePack {
  static const _coursesKey = 'cached_faculty_courses';
  static const _blocksKey = 'cached_section_blocks';
  static const _sectionsKey = 'cached_section_options';
  static const _pendingAddsKey = 'pending_section_adds';
  static const _stampKey = 'offline_pack_stamp';

  static DateTime? _probedAt;
  static bool _online = true;
  static final Set<String> _keySyncTried = {};

  static final ValueNotifier<OfflineSaveProgress> progress =
      ValueNotifier<OfflineSaveProgress>(const OfflineSaveProgress());
  static final ValueNotifier<PackAttention> attention =
      ValueNotifier<PackAttention>(const PackAttention());

  static Future<void>? _save;
  static Future<void>? _check;
  static _RemoteCatalog? _lastCatalog;
  static DateTime? _catalogCheckedAt;
  static bool _saveDone = false;
  static int _jobs = 0;
  static int _done = 0;
  static int _total = 0;
  static int _floor = 0;
  static bool _holding = false;

  /// Compares the phone's copy with the server. Shows the save notice only
  /// when this phone has never stored the pack. Later calls within a short
  /// window reuse the same result.
  static Future<void> ensureSaved({
    GradingRepository? grading,
    QuickExamRepository? quick,
  }) {
    final running = _check;
    if (running != null) return running;
    late final Future<void> job;
    job = _checkCatalog(
      grading ?? GradingRepository(),
      quick ?? QuickExamRepository(),
    ).whenComplete(() {
      if (identical(_check, job)) _check = null;
    });
    _check = job;
    return job;
  }

  /// Uploads whatever [upload] sends, then downloads when the server copy changed.
  /// Returns false when the phone still needs a connection or the save failed.
  static Future<bool> runSync(Future<void> Function() upload) async {
    if (attention.value.busy) return false;
    _setBusy(true);
    try {
      await upload();
      await refreshLocalAttention();
      if (attention.value.needsDownload) return await downloadUpdates();
      return !attention.value.needsUpload;
    } finally {
      _setBusy(false);
    }
  }

  /// Writes the server copy onto the phone and shows the save notice.
  static Future<bool> downloadUpdates({
    GradingRepository? grading,
    QuickExamRepository? quick,
  }) async {
    final g = grading ?? GradingRepository();
    final q = quick ?? QuickExamRepository();
    if (!await probe(force: true)) return false;
    await _startSave(g, q);
    if (!_saveDone) return false;
    final catalog = await _loadCatalog(g, q);
    if (catalog == null) return false;
    _remember(catalog);
    await _storeStamp(catalog.stamp);
    await TemplateCache.patchUpdatedAt(catalog.updatedAts);
    await refreshLocalAttention(needsDownload: false);
    return true;
  }

  /// Recounts scans and class changes still waiting on this phone.
  static Future<void> refreshLocalAttention({bool? needsDownload}) async {
    final pending = await ScanHistory.getPendingUpload();
    final adds = await RosterCache.pendingAdds();
    final prev = attention.value;
    attention.value = PackAttention(
      pendingScans: pending.length,
      pendingSections: adds.length,
      needsDownload: needsDownload ?? prev.needsDownload,
      busy: prev.busy,
    );
  }

  /// After the home screen writes a fresh copy, drop a download flag that
  /// was raised against the older one.
  static Future<void> adoptIfUnchanged() async {
    final catalog = _lastCatalog;
    if (catalog == null) return;
    await _settle(catalog);
  }

  static void _setBusy(bool busy) {
    final prev = attention.value;
    attention.value = PackAttention(
      pendingScans: prev.pendingScans,
      pendingSections: prev.pendingSections,
      needsDownload: prev.needsDownload,
      busy: busy,
    );
  }

  static void _remember(_RemoteCatalog catalog) {
    _lastCatalog = catalog;
    _catalogCheckedAt = DateTime.now();
  }

  static Future<void> _storeStamp(String stamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stampKey, stamp);
  }

  static Future<void> _checkCatalog(
    GradingRepository grading,
    QuickExamRepository quick,
  ) async {
    await refreshLocalAttention();
    final last = _lastCatalog;
    final checked = _catalogCheckedAt;
    if (last != null &&
        checked != null &&
        DateTime.now().difference(checked) < const Duration(seconds: 45)) {
      await _settle(last);
      return;
    }
    if (!await probe()) return;
    if (!await _hasLocalPack()) {
      await _startSave(grading, quick);
      final catalog = await _loadCatalog(grading, quick);
      if (catalog == null) return;
      _remember(catalog);
      await _storeStamp(catalog.stamp);
      await refreshLocalAttention(needsDownload: false);
      return;
    }
    final catalog = await _loadCatalog(grading, quick);
    if (catalog == null) return;
    _remember(catalog);
    await _settle(catalog);
  }

  static Future<void> _settle(_RemoteCatalog catalog) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_stampKey);
    if (saved == catalog.stamp) {
      await refreshLocalAttention(needsDownload: false);
      return;
    }
    final firstLook = saved == null || saved.isEmpty;
    if (await _matches(catalog, allowUntimed: firstLook)) {
      await _storeStamp(catalog.stamp);
      await TemplateCache.patchUpdatedAt(catalog.updatedAts);
      await refreshLocalAttention(needsDownload: false);
      return;
    }
    await refreshLocalAttention(needsDownload: true);
  }

  static Future<void> _startSave(
    GradingRepository grading,
    QuickExamRepository quick,
  ) {
    final running = _save;
    if (running != null) return running;
    final job = _runSave(grading, quick);
    _save = job;
    return job;
  }

  /// A pack from an earlier visit. Courses alone do not count: the home screen
  /// saves those before the class list exists, and that first save should
  /// still show the notice.
  static Future<bool> _hasLocalPack() async {
    if (await RosterCache.load() == null) return false;
    if ((await loadCourses()).isNotEmpty) return true;
    final templates = await TemplateCache.load();
    return templates != null && templates.isNotEmpty;
  }

  static Future<_RemoteCatalog?> _loadCatalog(
    GradingRepository grading,
    QuickExamRepository quick,
  ) async {
    try {
      final courses = await grading.fetchFacultyCourses();
      final templates = <BubbleTemplate>[];
      for (final course in courses) {
        final id = (course['course_id'] ?? '').toString();
        if (id.isEmpty) continue;
        templates.addAll(await grading.fetchTemplates(id));
      }
      final exams = await quick.fetchExams();
      final roster = await grading.fetchSectionedBlocks();
      return _RemoteCatalog(
        courses: courses,
        templates: templates,
        exams: exams,
        blocks: roster.blocks,
        sections: roster.sections,
      );
    } catch (e) {
      debugPrint('Offline pack: catalog check skipped: $e');
      if (isOfflineError(e)) markOffline();
      return null;
    }
  }

  /// True when the phone already has the same exams, keys, and class list.
  static Future<bool> _matches(
    _RemoteCatalog remote, {
    required bool allowUntimed,
  }) async {
    final cached = await TemplateCache.load() ?? <BubbleTemplate>[];
    final byId = {for (final template in cached) template.templateId: template};
    final remoteCourseIds = <String>{};

    for (final template in remote.templates) {
      if (template.isQuickExam) continue;
      remoteCourseIds.add(template.templateId);
      final local = byId[template.templateId];
      if (local == null || local.isQuickExam) return false;
      if (local.name != template.name || local.totalItems != template.totalItems) {
        return false;
      }
      if (_keySig(local.answerKey) != _keySig(template.answerKey)) return false;
      if (template.hasLayoutItems != local.hasLayoutItems) return false;
      if (!_sameClock(local.updatedAt, template.updatedAt, allowUntimed)) {
        return false;
      }
    }
    for (final template in cached) {
      if (template.isQuickExam || template.courseId.isEmpty) continue;
      if (!remoteCourseIds.contains(template.templateId)) return false;
    }

    final remoteQuickIds = <String>{};
    for (final exam in remote.exams) {
      remoteQuickIds.add(exam.examId);
      final local = byId[exam.examId];
      if (local == null || !local.isQuickExam) return false;
      if (local.name != exam.name || local.totalItems != exam.totalItems) {
        return false;
      }
      final knownItems = _distinctItems(local.answerKey);
      if (knownItems < exam.keyedItems &&
          local.answerKey.length < exam.keyedItems) {
        return false;
      }
      if (!_sameClock(local.updatedAt, exam.updatedAt, allowUntimed)) return false;
    }
    for (final template in cached) {
      if (!template.isQuickExam) continue;
      if (!remoteQuickIds.contains(template.templateId)) return false;
    }

    final localCourses = await loadCourses();
    if (localCourses.length != remote.courses.length) return false;
    final coursesById = {
      for (final course in localCourses)
        (course['course_id'] ?? '').toString(): course,
    };
    for (final course in remote.courses) {
      final id = (course['course_id'] ?? '').toString();
      final local = coursesById[id];
      if (local == null) return false;
      if ('${local['course_code']}' != '${course['course_code']}') return false;
      if ('${local['course_title']}' != '${course['course_title']}') return false;
      if ('${local['section']}' != '${course['section']}') return false;
    }

    final saved = await RosterCache.load();
    final localBlocks = saved?.blocks ?? {};
    final pending = {
      for (final add in await RosterCache.pendingAdds()) add.studentId,
    };
    for (final block in remote.blocks.values) {
      final local = localBlocks[block.studentId];
      if (local == null) return false;
      if ((local.sectionId ?? '') != (block.sectionId ?? '')) return false;
      if (local.section != block.section) return false;
      if (local.gradeLevel != block.gradeLevel) return false;
    }
    for (final id in localBlocks.keys) {
      if (pending.contains(id)) continue;
      if (!remote.blocks.containsKey(id)) return false;
    }
    final localSections = saved?.sections ?? [];
    if (localSections.length != remote.sections.length) return false;
    final sectionsById = {
      for (final section in localSections) section.sectionId: section,
    };
    for (final section in remote.sections) {
      final local = sectionsById[section.sectionId];
      if (local == null || local.name != section.name) return false;
      final localIds = [...local.courseIds]..sort();
      final remoteIds = [...section.courseIds]..sort();
      if (localIds.join(',') != remoteIds.join(',')) return false;
    }
    return true;
  }

  static bool _sameClock(String? local, String? remote, bool allowUntimed) {
    final left = local ?? '';
    final right = remote ?? '';
    if (left.isNotEmpty && right.isNotEmpty) return left == right;
    return allowUntimed || (left.isEmpty && right.isEmpty);
  }

  static String _keySig(Map<String, String> key) {
    final parts = [for (final entry in key.entries) '${entry.key}=${entry.value}']
      ..sort();
    return parts.join(',');
  }

  static int _distinctItems(Map<String, String> key) {
    final nums = <int>{};
    for (final item in key.keys) {
      final n = int.tryParse(item);
      if (n != null) nums.add(n);
    }
    return nums.length;
  }

  static Future<void> _runSave(
    GradingRepository grading,
    QuickExamRepository quick,
  ) async {
    var succeeded = false;
    _saveDone = false;
    try {
      if (!await probe()) return;
      await _track(() async {
        await _refreshCourses(grading);
        await _refreshRoster(grading);
        await _fillMissingCourseKeys(grading);
        await _refreshQuick(quick);
      });
      succeeded = _online && _total > 0;
    } finally {
      if (succeeded) _saveDone = true;
      _save = null;
    }
  }

  static Future<void> _track(Future<void> Function() body) async {
    _enter();
    try {
      await body();
    } finally {
      _leave();
    }
  }

  static void _enter() {
    if (_jobs == 0 && !_holding) {
      _done = 0;
      _total = 0;
      _floor = 0;
    }
    _holding = false;
    _jobs++;
    _emit(active: true);
  }

  static void _leave() {
    if (_jobs == 0) return;
    _jobs--;
    if (_jobs > 0) return;
    final success = _online && _total > 0;
    if (!success) {
      _holding = false;
      _floor = 0;
      _done = 0;
      _total = 0;
      _emit(active: false);
      return;
    }
    _done = _total;
    _holding = true;
    _emit(active: true, finished: true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_jobs != 0) return;
      _holding = false;
      _floor = 0;
      _done = 0;
      _total = 0;
      _emit(active: false);
    });
  }

  /// Adds [more] steps before they are saved. The shown percent never falls.
  static void expect(int more) {
    if (_jobs == 0 || more <= 0) return;
    _total += more;
    _emit(active: true);
  }

  /// Marks [n] steps saved.
  static void saved([int n = 1]) {
    if (_jobs == 0 || n <= 0) return;
    _done += n;
    if (_total < _done) _total = _done;
    _emit(active: true);
  }

  static void _emit({required bool active, bool finished = false}) {
    var raw = 0;
    if (_total > 0) {
      raw = ((_done / _total) * 100).round();
      if (raw > 100) raw = 100;
    }
    var shown = finished ? 100 : (raw > 99 ? 99 : raw);
    if (active && shown < _floor) shown = _floor;
    if (active && shown > _floor) _floor = shown;
    if (!active) _floor = 0;
    progress.value = OfflineSaveProgress(
      active: active,
      finished: finished && active,
      done: _done,
      total: _total,
      percent: active ? shown : 0,
    );
  }

  static void markOffline() {
    _online = false;
    _probedAt = DateTime.now();
  }

  static void markOnline() {
    _online = true;
    _probedAt = DateTime.now();
  }

  /// Whether the server answered recently. A failed probe is reused for a
  /// short while so offline scanning does not wait on every sheet.
  static Future<bool> probe({bool force = false}) async {
    if (!force &&
        _probedAt != null &&
        DateTime.now().difference(_probedAt!) < const Duration(seconds: 15)) {
      return _online;
    }
    try {
      await ApiClient().dio.get(
            'auth/me/',
            options: Options(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
              extra: const {'_retried': true},
            ),
          );
      _online = true;
    } on DioException catch (e) {
      _online = e.response != null || !isOfflineError(e);
    } catch (e) {
      _online = !isOfflineError(e);
    }
    _probedAt = DateTime.now();
    return _online;
  }

  /// Pulls every course exam, major exam, and the section roster once.
  static Future<void> refresh({
    GradingRepository? grading,
    QuickExamRepository? quick,
  }) =>
      ensureSaved(grading: grading, quick: quick);

  /// Class list only. Does not start the on-screen save notice.
  static Future<void> refreshRoster({GradingRepository? grading}) =>
      _refreshRoster(grading ?? GradingRepository());

  /// Same one-time save as [ensureSaved]. Safe to call from every screen.
  static Future<void> refreshQuickAndRoster({
    GradingRepository? grading,
    QuickExamRepository? quick,
  }) =>
      ensureSaved(grading: grading, quick: quick);

  static Future<void> saveCourses(List<Map<String, dynamic>> courses) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = [
      for (final c in courses)
        {
          'course_id': '${c['course_id'] ?? ''}',
          'course_code': '${c['course_code'] ?? ''}',
          'course_title': '${c['course_title'] ?? ''}',
          'section': '${c['section'] ?? ''}',
        },
    ];
    await prefs.setString(_coursesKey, jsonEncode(clean));
  }

  static Future<List<Map<String, dynamic>>> loadCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_coursesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _refreshCourses(GradingRepository grading) async {
    try {
      final courses = await grading.fetchFacultyCourses();
      expect(courses.length + 1);
      await saveCourses(courses);
      saved();
      for (final c in courses) {
        final id = (c['course_id'] ?? '').toString();
        if (id.isEmpty) {
          saved();
          continue;
        }
        try {
          final templates = await grading.fetchTemplates(id);
          await TemplateCache.mergeCourse(id, templates);
        } catch (e) {
          debugPrint('Offline pack: course $id skipped: $e');
        }
        saved();
      }
    } catch (e) {
      debugPrint('Offline pack: courses skipped: $e');
      if (isOfflineError(e)) markOffline();
    }
  }

  static Future<void> _fillMissingCourseKeys(GradingRepository grading) async {
    final cached = await TemplateCache.load() ?? <BubbleTemplate>[];
    final missing = [
      for (final t in cached)
        if (!t.isQuickExam &&
            t.answerKey.isEmpty &&
            t.assessmentId != null &&
            !_keySyncTried.contains(t.templateId))
          t,
    ];
    expect(missing.length);
    for (var i = 0; i < missing.length; i++) {
      final t = missing[i];
      if (!_keySyncTried.add(t.templateId)) {
        saved();
        continue;
      }
      try {
        final synced = await grading.syncKeyFromAssessment(t.templateId);
        if (synced.answerKey.isNotEmpty || synced.hasLayoutItems) {
          await TemplateCache.upsert(synced);
        }
      } catch (e) {
        debugPrint('Offline pack: key sync skipped for ${t.templateId}: $e');
        if (isOfflineError(e)) {
          markOffline();
          saved(missing.length - i);
          return;
        }
      }
      saved();
    }
  }

  static Future<void> _refreshQuick(QuickExamRepository quick) async {
    final seen = TemplateCache.epoch;
    final List<QuickExam> exams;
    try {
      exams = await quick.fetchExams();
    } catch (e) {
      debugPrint('Offline pack: major exams skipped: $e');
      if (isOfflineError(e)) markOffline();
      return;
    }
    final cached = await TemplateCache.load() ?? <BubbleTemplate>[];
    final byId = {for (final t in cached) t.templateId: t};
    final full = <BubbleTemplate>[];
    var complete = true;
    expect(exams.length);
    for (var i = 0; i < exams.length; i++) {
      final exam = exams[i];
      final prev = byId[exam.examId];
      final unchanged = prev != null &&
          prev.hasLayoutItems &&
          prev.answerKey.length >= exam.keyedItems &&
          prev.name == exam.name &&
          prev.totalItems == exam.totalItems;
      if (unchanged) {
        full.add(prev);
        saved();
        continue;
      }
      try {
        final detail = await quick.fetchExam(exam.examId);
        full.add(detail.toTemplate());
      } catch (e) {
        debugPrint('Offline pack: exam ${exam.examId} skipped: $e');
        if (prev != null) full.add(prev);
        if (isOfflineError(e)) {
          markOffline();
          complete = false;
          saved(exams.length - i);
          break;
        }
      }
      saved();
    }
    if (!complete) {
      for (final template in full) {
        await TemplateCache.upsert(template);
      }
      return;
    }
    await TemplateCache.replaceQuick(full, seen);
  }

  static Future<void> _refreshRoster(GradingRepository grading) async {
    expect(1);
    try {
      final remote = await grading.fetchSectionedBlocks();
      await RosterCache.store(remote.blocks, remote.sections);
      markOnline();
    } catch (e) {
      debugPrint('Offline pack: sections skipped: $e');
      if (isOfflineError(e)) markOffline();
    }
    saved();
  }
}

class _RemoteCatalog {
  final List<Map<String, dynamic>> courses;
  final List<BubbleTemplate> templates;
  final List<QuickExam> exams;
  final Map<String, StudentBlock> blocks;
  final List<SectionOption> sections;

  const _RemoteCatalog({
    required this.courses,
    required this.templates,
    required this.exams,
    required this.blocks,
    required this.sections,
  });

  Map<String, String> get updatedAts => {
        for (final template in templates)
          if ((template.updatedAt ?? '').isNotEmpty)
            template.templateId: template.updatedAt!,
        for (final exam in exams)
          if ((exam.updatedAt ?? '').isNotEmpty) exam.examId: exam.updatedAt!,
      };

  String get stamp {
    final lines = <String>[
      for (final course in courses)
        'c|${course['course_id']}|${course['course_code']}|${course['course_title']}|${course['section']}',
      for (final template in templates)
        if (!template.isQuickExam)
          't|${template.templateId}|${template.updatedAt}|${template.name}|${template.totalItems}|${template.hasLayoutItems}|${OfflinePack._keySig(template.answerKey)}',
      for (final exam in exams)
        'q|${exam.examId}|${exam.updatedAt}|${exam.name}|${exam.totalItems}|${exam.keyedItems}',
      for (final block in blocks.values)
        'r|${block.studentId}|${block.sectionId}|${block.section}|${block.gradeLevel}',
      for (final section in sections)
        's|${section.sectionId}|${section.name}|${([...section.courseIds]..sort()).join(',')}',
    ]..sort();
    return lines.join('\n');
  }
}

/// Class list saved on the device, plus section assignments waiting to sync.
class RosterCache {
  static Future<void> store(
    Map<String, StudentBlock> blocks,
    List<SectionOption> sections,
  ) async {
    final merged = Map<String, StudentBlock>.from(blocks);
    for (final add in await pendingAdds()) {
      merged.putIfAbsent(
        add.studentId,
        () => StudentBlock(
          studentId: add.studentId,
          gradeLevel: add.gradeLevel,
          sectionId: add.sectionId,
          section: add.sectionName ?? '',
        ),
      );
    }
    await _write(merged, sections);
  }

  static Future<SavedRoster?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final blocksRaw = prefs.getString(OfflinePack._blocksKey);
    final sectionsRaw = prefs.getString(OfflinePack._sectionsKey);
    if (blocksRaw == null && sectionsRaw == null) return null;
    try {
      final blocks = <String, StudentBlock>{};
      if (blocksRaw != null && blocksRaw.isNotEmpty) {
        final decoded = jsonDecode(blocksRaw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              blocks[k.toString()] =
                  StudentBlock.fromJson(Map<String, dynamic>.from(v));
            }
          });
        }
      }
      final sections = <SectionOption>[];
      if (sectionsRaw != null && sectionsRaw.isNotEmpty) {
        final decoded = jsonDecode(sectionsRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              sections.add(
                SectionOption.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      }
      return SavedRoster(blocks: blocks, sections: sections);
    } catch (_) {
      return null;
    }
  }

  static Future<void> rememberBlock(StudentBlock block) async {
    final current = await load();
    final blocks = Map<String, StudentBlock>.from(current?.blocks ?? {});
    blocks[block.studentId] = block;
    await _write(blocks, current?.sections ?? const []);
  }

  static Future<void> queueAdd(PendingSectionAdd add) async {
    final all = await pendingAdds();
    all.removeWhere((a) => a.studentId == add.studentId);
    all.add(add);
    await _saveAdds(all);
    await OfflinePack.refreshLocalAttention();
  }

  static Future<List<PendingSectionAdd>> pendingAdds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(OfflinePack._pendingAddsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          if (item is Map)
            PendingSectionAdd.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> removeAdd(String studentId) async {
    final all = await pendingAdds();
    all.removeWhere((a) => a.studentId == studentId);
    await _saveAdds(all);
    await OfflinePack.refreshLocalAttention();
  }

  static Future<void> _saveAdds(List<PendingSectionAdd> adds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      OfflinePack._pendingAddsKey,
      jsonEncode(adds.map((a) => a.toJson()).toList()),
    );
  }

  static Future<void> _write(
    Map<String, StudentBlock> blocks,
    List<SectionOption> sections,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      OfflinePack._blocksKey,
      jsonEncode({
        for (final entry in blocks.entries) entry.key: entry.value.toJson(),
      }),
    );
    await prefs.setString(
      OfflinePack._sectionsKey,
      jsonEncode(sections.map((s) => s.toJson()).toList()),
    );
  }
}
