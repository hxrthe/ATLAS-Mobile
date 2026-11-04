import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/error_messages.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import '../grading/scan_events.dart';
import '../quick_exam/quick_exam_repository.dart';
import 'offline_pack.dart';
import 'omr_models.dart';
import 'scan_history.dart';
import 'template_cache.dart';

/// Marker written when a queued scan can never reach the server (e.g. photo gone).
const _unrecoverableScanId = 'local-unrecoverable';

/// A scan that reached the database.
class SyncedScan {
  final String localId;
  final String serverScanId;
  final bool replaced;
  final String studentId;
  final String templateId;
  final double? scoreRaw;
  final double? maxScore;
  final String? section;

  const SyncedScan({
    required this.localId,
    required this.serverScanId,
    required this.studentId,
    required this.templateId,
    this.replaced = false,
    this.scoreRaw,
    this.maxScore,
    this.section,
  });
}

/// Sends saved scores, and any section assignments made offline, once the
/// server is reachable. Safe to call often: it does nothing when the queue
/// is empty, and two callers share one upload for the same sheet.
class OfflineSync with WidgetsBindingObserver {
  OfflineSync._();

  static final OfflineSync instance = OfflineSync._();

  final GradingRepository _grading = GradingRepository();
  final QuickExamRepository _quick = QuickExamRepository();
  final Map<String, Future<SyncedScan>> _jobs = {};
  final StreamController<SyncedScan> _notices =
      StreamController<SyncedScan>.broadcast();

  bool _started = false;
  bool _flushing = false;

  Stream<SyncedScan> get synced => _notices.stream;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    Timer.periodic(const Duration(seconds: 30), (_) => flush());
    flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) flush();
  }

  /// Uploads everything still waiting. Stops at the first connection failure.
  ///
  /// Returns an error message when [reportFailures] is true and something
  /// prevented a clean sync; otherwise null.
  Future<String?> flush({bool reportFailures = false}) async {
    if (_flushing) {
      return reportFailures ? 'Already updating. Please wait a moment.' : null;
    }
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString('access_token') ?? '').isEmpty) {
      return reportFailures ? 'Sign in again, then try syncing.' : null;
    }
    final adds = await RosterCache.pendingAdds();
    final pending = await ScanHistory.getPendingUpload();
    if (adds.isEmpty && pending.isEmpty) {
      await OfflinePack.refreshLocalAttention();
      return null;
    }
    if (!await OfflinePack.probe(force: true)) {
      return reportFailures
          ? 'Connect to the internet, then try again.'
          : null;
    }

    _flushing = true;
    String? failure;
    var abandonedMissingPhoto = 0;
    try {
      final offline = await _syncSectionAdds();
      if (offline) {
        failure = 'Connect to the internet, then try again.';
        return reportFailures ? failure : null;
      }
      pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final record in pending) {
        try {
          await upload(record);
        } on StudentNotInSectionException {
          continue;
        } on _MissingScanPhotoException {
          await ScanHistory.updateRecord(record.id, {
            'server_scan_id': _unrecoverableScanId,
          });
          abandonedMissingPhoto++;
        } catch (e) {
          if (isOfflineError(e)) {
            OfflinePack.markOffline();
            failure = 'Connect to the internet, then try again.';
            return reportFailures ? failure : null;
          }
          failure ??= friendlyError(
            e,
            fallback: 'That did not finish. Try again in a moment.',
          );
        }
      }
      if (abandonedMissingPhoto > 0) {
        failure ??= abandonedMissingPhoto == 1
            ? 'One answer sheet could not be sent because its photo is missing on this phone.'
            : '$abandonedMissingPhoto answer sheets could not be sent because their photos are missing on this phone.';
      }
    } finally {
      _flushing = false;
      unawaited(OfflinePack.refreshLocalAttention());
    }
    return reportFailures ? failure : null;
  }

  Future<SyncedScan> upload(ScanRecord record) {
    final existing = _jobs[record.id];
    if (existing != null) return existing;
    final job = _upload(record);
    _jobs[record.id] = job;
    return job.whenComplete(() => _jobs.remove(record.id));
  }

  Future<SyncedScan> _upload(ScanRecord record) async {
    final latest = await _latest(record);
    if (latest.serverScanId != null && latest.serverScanId!.isNotEmpty) {
      return SyncedScan(
        localId: latest.id,
        serverScanId: latest.serverScanId!,
        studentId: latest.studentIdentifier,
        templateId: latest.templateId,
        scoreRaw: latest.scoreRaw,
        maxScore: latest.maxScore,
      );
    }
    if (await _syncSectionAdds()) {
      throw const SocketException('offline');
    }

    final quick = await _isQuick(latest);
    final SyncedScan synced;
    if (quick) {
      final saved = await _quick.uploadScan(
        examId: latest.templateId,
        studentId: _studentOrNull(latest.studentIdentifier),
        responses: latest.responses,
        isFlagged: latest.isFlagged,
        flagReason: latest.flagReason,
        failFast: true,
      );
      synced = SyncedScan(
        localId: latest.id,
        serverScanId: saved.scan.scanId,
        replaced: saved.replaced,
        studentId: latest.studentIdentifier,
        templateId: latest.templateId,
        scoreRaw: saved.scan.scoreRaw ?? latest.scoreRaw,
        maxScore: saved.scan.maxScore ?? latest.maxScore,
      );
    } else {
      final path = latest.imagePath;
      if (path == null || path.isEmpty || !File(path).existsSync()) {
        throw const _MissingScanPhotoException();
      }
      final scan = await _grading.uploadGradedScan(
        templateId: latest.templateId,
        imagePath: path,
        studentId: latest.studentIdentifier,
        responses: latest.responses,
        isFlagged: latest.isFlagged,
        flagReason: latest.flagReason,
        failFast: true,
      );
      final roster = await RosterCache.load();
      synced = SyncedScan(
        localId: latest.id,
        serverScanId: scan.scanId,
        studentId: scan.studentIdentifier.isNotEmpty
            ? scan.studentIdentifier
            : latest.studentIdentifier,
        templateId: latest.templateId,
        scoreRaw: scan.scoreRaw ?? latest.scoreRaw,
        maxScore: scan.maxScore ?? latest.maxScore,
        section: roster?.blocks[scan.studentIdentifier]?.section ??
            roster?.blocks[latest.studentIdentifier]?.section,
      );
    }

    await ScanHistory.updateRecord(latest.id, {
      'server_scan_id': synced.serverScanId,
    });
    OfflinePack.markOnline();
    ScanEvents.emit(ScanSavedEvent(
      templateId: synced.templateId,
      studentId: synced.studentId,
      section: synced.section,
      score: synced.scoreRaw,
      maxScore: synced.maxScore,
    ));
    if (!_notices.isClosed) _notices.add(synced);
    return synced;
  }

  /// Returns true when the connection dropped and the rest should wait.
  Future<bool> _syncSectionAdds() async {
    final adds = await RosterCache.pendingAdds();
    for (final add in adds) {
      try {
        final block = await _grading.addStudentToSection(
          studentId: add.studentId,
          sectionId: add.sectionId,
          sectionName: add.sectionName,
          gradeLevel: add.gradeLevel,
          courseId: add.courseId,
          failFast: true,
        );
        await RosterCache.rememberBlock(block);
        await RosterCache.removeAdd(add.studentId);
      } on StudentInOtherSectionException catch (e) {
        await RosterCache.rememberBlock(e.existing);
        await RosterCache.removeAdd(add.studentId);
      } catch (e) {
        if (isOfflineError(e)) {
          OfflinePack.markOffline();
          return true;
        }
      }
    }
    return false;
  }

  Future<ScanRecord> _latest(ScanRecord record) async {
    final all = await ScanHistory.getAll();
    final idx = all.indexWhere((r) => r.id == record.id);
    return idx < 0 ? record : all[idx];
  }

  Future<bool> _isQuick(ScanRecord record) async {
    if (record.isQuickExam) return true;
    final saved = await TemplateCache.load() ?? <BubbleTemplate>[];
    return saved.any(
      (t) => t.templateId == record.templateId && t.isQuickExam,
    );
  }

  String? _studentOrNull(String id) {
    final v = id.trim();
    if (v.isEmpty || v.toLowerCase() == 'unknown') return null;
    return v;
  }
}

class _MissingScanPhotoException implements Exception {
  const _MissingScanPhotoException();
}
