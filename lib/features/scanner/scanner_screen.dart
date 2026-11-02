import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network/error_messages.dart';
import '../grading/answer_key.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import '../quick_exam/quick_exam_models.dart';
import '../quick_exam/quick_exam_repository.dart';
import 'offline_pack.dart';
import 'offline_sync.dart';
import 'omr_constants.dart';
import 'omr_imaging.dart';
import 'omr_models.dart';
import 'omr_service.dart';
import 'scan_history.dart';
import 'scanner_widgets.dart';
import 'section_gate_dialog.dart';
import 'template_cache.dart';

class ScannerScreen extends StatefulWidget {
  final String? preSelectedCourseId;
  final String? preSelectedCourseName;

  /// Quick exam to scan right away (sheets still switch by their QR).
  final BubbleTemplate? quickExam;

  const ScannerScreen({
    super.key,
    this.preSelectedCourseId,
    this.preSelectedCourseName,
    this.quickExam,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _ScreenMode { scanning, result, review, detail }

class _ScannerScreenState extends State<ScannerScreen> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isStreaming = false;
  int _frameCount = 0;
  static const int _frameSkip = 1;

  final GradingRepository _repository = GradingRepository();
  final QuickExamRepository _quickRepository = QuickExamRepository();
  List<BubbleTemplate> _templates = [];
  BubbleTemplate? _selectedTemplate;

  FiducialLockState _fiducialLock = FiducialLockState.initial();
  ScannerDiagnostics _diagnostics = ScannerDiagnostics.ok();
  bool _assessmentIdentified = false;
  bool _isCapturing = false;
  bool _isIdentifying = false;
  bool _frameBusy = false;
  String? _identifyError;
  Uint8List? _alignedPreviewBytes;
  OmrGradeSnapshot? _gradeSnapshot;
  static const int _lockThresholdFrames = 1;
  int _omrJobId = 0;

  AnimationController? _scoreFlashController;
  Animation<double>? _scoreFlashAnimation;
  String? _scoreFlashText;

  /// User preference: restore torch on "Scan next" only if they turned it on live.
  bool _userWantsTorch = false;
  bool _torchHardwareOn = false;
  Timer? _resultStatusTimer;

  List<ScanRecord> _scanRecords = [];
  bool _isLoadingRecords = false;

  /// Students already assigned to a section; only these may be recorded.
  Map<String, StudentBlock> _sectionedBlocks = {};
  List<SectionOption> _sectionOptions = [];
  String? _lastGateSectionId;
  String? _lastGateGradeLevel;

  _ScreenMode _mode = _ScreenMode.scanning;
  ScanRecord? _detailRecord;

  // Post-capture result screen state
  String? _resultCapturePath;
  Uint8List? _resultPreviewBytes;
  bool _resultProcessing = false;
  String _resultStatus = '';
  OmrResult? _lastOmrResult;
  /// idle | uploading | uploaded | failed | rejected
  String _uploadStatus = 'idle';
  ScanRecord? _pendingUploadRecord;
  /// Answer key used for the sheet currently on the result screen.
  Map<String, String> _resultAnswerKey = const {};
  int _resultTotalItems = 0;

  StreamSubscription<SyncedScan>? _syncSub;

  /// When set, the next capture must match these IDs (Rescan only).
  String? _rescanExpectedStudentId;
  String? _rescanExpectedAssessmentId;
  String? _rescanReplaceRecordId;

  Rect? _roi;
  Size? _lastScreenSize;

  void _updateROI(Size size) {
    if (_lastScreenSize == size) return;
    _lastScreenSize = size;
    
    const double topMargin = 320.0;
    const double bottomMargin = 160.0;
    const double paperAspectRatio = 13.0 / 8.5;

    final availableHeight = size.height - topMargin - bottomMargin;
    final clearWidth = size.width * 0.92;
    double finalClearHeight = clearWidth * paperAspectRatio;
    double finalClearWidth = clearWidth;

    if (finalClearHeight > availableHeight) {
      finalClearHeight = availableHeight;
      finalClearWidth = finalClearHeight / paperAspectRatio;
    }

    final centerY = topMargin + (availableHeight / 2);
    final clearRect = Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: finalClearWidth,
      height: finalClearHeight,
    );

    _roi = Rect.fromLTRB(
      clearRect.left / size.width,
      clearRect.top / size.height,
      clearRect.right / size.width,
      clearRect.bottom / size.height,
    );
  }

  @override
  void initState() {
    super.initState();
    _scoreFlashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _scoreFlashAnimation = CurvedAnimation(parent: _scoreFlashController!, curve: Curves.easeInOut);
    final quick = widget.quickExam;
    if (quick != null) {
      _selectedTemplate = quick;
      _assessmentIdentified = true;
      _templates = [quick];
      // List payloads omit the key and layout. Prefer the copy saved on device.
      if (quick.answerKey.isEmpty || !quick.hasLayoutItems) {
        _refreshQuickExamSeed(quick.templateId);
      }
    }
    _syncSub = OfflineSync.instance.synced.listen(_onRemoteSync);
    _initScanner();
  }

  void _onRemoteSync(SyncedScan synced) {
    if (!mounted) return;
    setState(() {
      final idx = _scanRecords.indexWhere((r) => r.id == synced.localId);
      if (idx >= 0) {
        _scanRecords[idx] =
            _scanRecords[idx].copyWith(serverScanId: synced.serverScanId);
      }
      if (_detailRecord?.id == synced.localId) {
        _detailRecord =
            _detailRecord!.copyWith(serverScanId: synced.serverScanId);
      }
      if (_pendingUploadRecord?.id == synced.localId) {
        _pendingUploadRecord =
            _pendingUploadRecord!.copyWith(serverScanId: synced.serverScanId);
        _uploadStatus = 'uploaded';
        _resultStatus = synced.replaced
            ? 'Replaced earlier exam record'
            : 'Saved to grading results';
      }
    });
  }

  Future<void> _refreshQuickExamSeed(String examId) async {
    final saved = await TemplateCache.find(examId);
    if (saved != null &&
        saved.hasLayoutItems &&
        saved.answerKey.isNotEmpty &&
        mounted &&
        _selectedTemplate?.templateId == examId) {
      setState(() {
        _selectedTemplate = saved;
        final idx = _templates.indexWhere((t) => t.templateId == examId);
        if (idx >= 0) {
          _templates[idx] = saved;
        } else {
          _templates = [saved, ..._templates];
        }
      });
    }
    if (!await OfflinePack.probe()) return;
    try {
      final bound = await _fetchQuickTemplate(examId);
      if (!mounted) return;
      if (_selectedTemplate?.templateId != examId) return;
      setState(() {
        _selectedTemplate = bound;
        final idx = _templates.indexWhere((t) => t.templateId == examId);
        if (idx >= 0) {
          _templates[idx] = bound;
        } else {
          _templates = [bound, ..._templates];
        }
      });
      _updateCachedTemplate(bound);
    } catch (e) {
      debugPrint('Quick exam seed refresh failed: $e');
      if (isOfflineError(e)) OfflinePack.markOffline();
    }
  }

  /// Value printed in a sheet's QR for [t]: `QX:<id>` for quick exams.
  String? _qrKeyOf(BubbleTemplate? t) {
    if (t == null) return null;
    return t.isQuickExam ? '$quickExamQrPrefix${t.templateId}' : t.assessmentId;
  }

  Future<BubbleTemplate> _fetchQuickTemplate(String examId) async =>
      (await _quickRepository.fetchExam(examId)).toTemplate();

  Future<void> _initScanner() async {
    // Camera first — assessment is chosen by QR on the sheet, not by UI.
    await _setupCamera();
    _loadScanRecords();
    // Background cache of course templates (faster QR match when already known).
    _loadTemplates();
    _loadSectionedBlocks();
  }

  Future<void> _loadSectionedBlocks() async {
    final saved = await RosterCache.load();
    if (saved != null && mounted) {
      setState(() {
        _sectionedBlocks = Map<String, StudentBlock>.from(saved.blocks);
        _sectionOptions = List<SectionOption>.from(saved.sections);
      });
    }
    if (!await OfflinePack.probe()) return;
    try {
      final data = await _repository.fetchSectionedBlocks();
      await RosterCache.store(data.blocks, data.sections);
      final merged = await RosterCache.load();
      if (mounted) {
        setState(() {
          _sectionedBlocks = Map<String, StudentBlock>.from(
            merged?.blocks ?? data.blocks,
          );
          _sectionOptions = List<SectionOption>.from(
            merged?.sections ?? data.sections,
          );
        });
      }
    } catch (e) {
      debugPrint('Blocks preload failed: $e');
      if (isOfflineError(e)) OfflinePack.markOffline();
    }
  }

  /// Returns the student ID to record, or null when the scan is disregarded.
  Future<String?> _gateStudentSection(
    String? detectedId,
    BubbleTemplate template,
  ) async {
    final id = (detectedId ?? '').trim();
    if (_sectionedBlocks.isEmpty) {
      final saved = await RosterCache.load();
      if (saved != null) {
        _sectionedBlocks = Map<String, StudentBlock>.from(saved.blocks);
        _sectionOptions = List<SectionOption>.from(saved.sections);
      }
    }
    if (isUsableStudentId(id)) {
      if (_sectionedBlocks.containsKey(id)) return id;
      if (await OfflinePack.probe()) {
        try {
          final remote = await _repository.fetchSectionedBlocks(studentId: id);
          _sectionOptions = remote.sections;
          _sectionedBlocks.addAll(remote.blocks);
          await RosterCache.store(_sectionedBlocks, _sectionOptions);
          if (remote.blocks.containsKey(id)) return id;
        } catch (e) {
          debugPrint('Block lookup failed: $e');
          if (isOfflineError(e)) OfflinePack.markOffline();
        }
      }
    }
    if (!mounted) return null;
    final gate = await showSectionGateDialog(
      context: context,
      repository: _repository,
      detectedId: id,
      courseId: template.courseId,
      examLabel: template.name,
      knownBlocks: _sectionedBlocks,
      sections: _sectionOptions,
      lastSectionId: _lastGateSectionId,
      lastGradeLevel: _lastGateGradeLevel,
    );
    if (gate == null) return null;
    _sectionedBlocks[gate.studentId] = gate.block;
    RosterCache.rememberBlock(gate.block);
    final sectionId = gate.block.sectionId;
    if (sectionId != null &&
        !_sectionOptions.any((s) => s.sectionId == sectionId)) {
      _sectionOptions = [
        ..._sectionOptions,
        SectionOption(
          sectionId: sectionId,
          name: gate.block.section,
          courseIds: [template.courseId],
        ),
      ];
    }
    _lastGateSectionId = sectionId;
    _lastGateGradeLevel = gate.block.gradeLevel;
    return gate.studentId;
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _resultStatusTimer?.cancel();
    _stopImageStream();
    _controller?.dispose();
    _scoreFlashController?.dispose();
    OmrImaging.disposeScanner();
    super.dispose();
  }

  BubbleTemplate _richerTemplate(BubbleTemplate a, BubbleTemplate b) {
    int score(BubbleTemplate t) =>
        (t.hasLayoutItems ? 2 : 0) + (t.answerKey.isNotEmpty ? 1 : 0);
    return score(b) > score(a) ? b : a;
  }

  List<BubbleTemplate> _keepQuick(List<BubbleTemplate> next) => [
        ...next,
        ..._templates.where((t) =>
            t.isQuickExam && !next.any((n) => n.templateId == t.templateId)),
      ];

  Future<void> _loadTemplates() async {
    try {
      final cached = await TemplateCache.load();
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() => _templates = _keepQuick(cached));
      }
    } catch (e) {
      debugPrint('Template cache load failed: $e');
    }
    if (!await OfflinePack.probe()) return;
    try {
      await OfflinePack.refresh(
        grading: _repository,
        quick: _quickRepository,
      );
      final fresh = await TemplateCache.load();
      if (fresh != null && mounted) {
        setState(() => _templates = _keepQuick(fresh));
      }
    } catch (e) {
      debugPrint('Template download failed: $e');
      if (isOfflineError(e)) OfflinePack.markOffline();
    }
  }

  /// Bind the sheet from its QR. A saved key and layout are enough to grade
  /// with no connection; a newer copy is fetched when the server is reachable.
  Future<void> _bindTemplateFromQr(BubbleTemplate seed) async {
    var bound = seed;
    final ready = bound.hasLayoutItems && bound.answerKey.isNotEmpty;
    if (!ready && await OfflinePack.probe()) {
      try {
        bound = seed.isQuickExam
            ? await _fetchQuickTemplate(seed.templateId)
            : await _repository.fetchTemplateDetail(seed.templateId);
      } catch (e) {
        debugPrint('Template detail fetch failed: $e');
        if (isOfflineError(e)) OfflinePack.markOffline();
      }

      if (!bound.isQuickExam &&
          bound.answerKey.isEmpty &&
          bound.assessmentId != null &&
          await OfflinePack.probe()) {
        try {
          bound = await _repository.syncKeyFromAssessment(bound.templateId);
        } catch (e) {
          debugPrint('Answer key sync failed: $e');
          if (isOfflineError(e)) OfflinePack.markOffline();
        }
      }
    } else if (ready) {
      _refreshBoundQuietly(seed);
    }

    if (!mounted) return;
    _applyBoundTemplate(bound);
  }

  void _applyBoundTemplate(BubbleTemplate bound) {
    setState(() {
      _selectedTemplate = bound;
      _assessmentIdentified = true;
      _identifyError = null;
      if (!_templates.any((t) => t.templateId == bound.templateId)) {
        _templates.add(bound);
      } else {
        final idx =
            _templates.indexWhere((t) => t.templateId == bound.templateId);
        if (idx >= 0) _templates[idx] = bound;
      }
    });
    _updateCachedTemplate(bound);
  }

  Future<void> _refreshBoundQuietly(BubbleTemplate seed) async {
    if (!await OfflinePack.probe()) return;
    try {
      var bound = seed.isQuickExam
          ? await _fetchQuickTemplate(seed.templateId)
          : await _repository.fetchTemplateDetail(seed.templateId);
      if (!bound.isQuickExam &&
          bound.answerKey.isEmpty &&
          bound.assessmentId != null) {
        bound = await _repository.syncKeyFromAssessment(bound.templateId);
      }
      if (!mounted || _selectedTemplate?.templateId != bound.templateId) return;
      _applyBoundTemplate(bound);
    } catch (e) {
      debugPrint('Background key refresh failed: $e');
      if (isOfflineError(e)) OfflinePack.markOffline();
    }
  }

  void _updateCachedTemplate(BubbleTemplate updated) {
    final all = List<BubbleTemplate>.from(_templates);
    final idx = all.indexWhere((t) => t.templateId == updated.templateId);
    if (idx >= 0) {
      all[idx] = updated;
    } else {
      all.add(updated);
    }
    _templates = all;
    TemplateCache.upsert(updated);
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(
          cameras.first, ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
              ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
        );
        await _controller!.initialize();
        await _applyTorch(false); // start off; user opts in via button
        if (mounted) { setState(() => _isCameraReady = true); _startImageStream(); }
      }
    } catch (e) { debugPrint("Camera init error: $e"); }
  }

  /// Apply hardware torch. Does not change [_userWantsTorch].
  Future<void> _applyTorch(bool on) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      _torchHardwareOn = on;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _toggleTorch() async {
    _userWantsTorch = !_userWantsTorch;
    await _applyTorch(_userWantsTorch);
  }

  Future<void> _startImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized || _isStreaming) return;
    try {
      await _controller!.startImageStream(_onFrame);
      _isStreaming = true;
      // Restore torch only if the user turned it on during live scanning.
      await _applyTorch(_userWantsTorch);
    } catch (e) { debugPrint("Image stream error: $e"); }
  }

  Future<void> _stopImageStream() async {
    if (!_isStreaming || _controller == null) return;
    try { await _controller!.stopImageStream(); _isStreaming = false; } catch (_) {}
  }

  void _onFrame(CameraImage frame) async {
    _frameCount++;
    if (_frameCount % _frameSkip != 0) return;
    if (_isCapturing || _frameBusy) return;
    _frameBusy = true;

    try {
      // Warp when we have none, when lock is about to capture, and every 12th
      // frame for the live ALIGNED pip. Never capture without this JPEG.
      final wantWarp = _alignedPreviewBytes == null ||
          _fiducialLock.lockDuration >= 3 ||
          _frameCount % 12 == 0;

      final sheetFrame = OmrFrame.fromLayout(_selectedTemplate?.layoutMetadata);
      OmrFrame.active = sheetFrame;
      final det = OmrImaging.detectFiducialsLive(
        frame,
        previewSize: _controller?.value.previewSize,
        buildAlignedPreview: wantWarp,
        copyGradeSnapshot: wantWarp,
        sheetFrame: sheetFrame,
      );

      final next = _fiducialLock.update(
        tl: det.tl,
        tr: det.tr,
        bl: det.bl,
        br: det.br,
        tlPos: det.tlx != null && det.tly != null
            ? Offset(det.tlx!, det.tly!)
            : null,
        trPos: det.trx != null && det.tryv != null
            ? Offset(det.trx!, det.tryv!)
            : null,
        blPos: det.blx != null && det.bly != null
            ? Offset(det.blx!, det.bly!)
            : null,
        brPos: det.brx != null && det.bry != null
            ? Offset(det.brx!, det.bry!)
            : null,
        lockThresholdFrames: _lockThresholdFrames,
      );

      if (mounted) {
        setState(() {
          _fiducialLock = next;
          if (next.allFresh) {
            _diagnostics = ScannerDiagnostics.ok();
          }
          if (det.alignedPreview != null) {
            _alignedPreviewBytes = det.alignedPreview;
          } else if (!next.corners.any((c) => c.position != null)) {
            _alignedPreviewBytes = null;
            _gradeSnapshot = null;
          }
          if (det.gradeLuma != null &&
              det.gradeW != null &&
              det.gradeH != null &&
              det.arucoXy != null &&
              det.arucoXy!.length == 8) {
            _gradeSnapshot = OmrGradeSnapshot(
              luma: det.gradeLuma!,
              width: det.gradeW!,
              height: det.gradeH!,
              arucoXy: List<double>.from(det.arucoXy!),
              displayLuma: det.displayLuma,
              displayWidth: det.displayW,
              displayHeight: det.displayH,
              displayArucoXy: det.displayXy == null
                  ? null
                  : List<double>.from(det.displayXy!),
            );
          }
        });
      }

      if (_shouldAutoCapture(next) &&
          _alignedPreviewBytes != null &&
          _gradeSnapshot != null) {
        _manualCapture();
        return;
      }
    } catch (e) {
      debugPrint('Live frame error: $e');
    } finally {
      // Release before QR/diagnostics so guides keep updating.
      _frameBusy = false;
    }

    // QR identification — never blocks fiducial tracking above.
    if (_frameCount % 12 == 0 && !_isIdentifying && !_isCapturing) {
      try {
        final qr = await OmrImaging.decodeQRFromFrame(frame);
        if (qr != null && qr.isNotEmpty) {
          final assessmentId = OmrImaging.parseAssessmentId(qr);
          if (assessmentId != null && assessmentId.isNotEmpty) {
            final rescanLocked = _rescanExpectedAssessmentId != null &&
                !_sameId(_rescanExpectedAssessmentId, assessmentId);
            if (!rescanLocked) {
              if (!_sameId(_qrKeyOf(_selectedTemplate), assessmentId)) {
                await _identifyAssessmentFromQr(assessmentId);
              } else if (!_assessmentIdentified && mounted) {
                setState(() => _assessmentIdentified = true);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('QR frame error: $e');
      }
    }

    if (_frameCount % 45 == 0 && !_isCapturing) {
      try {
        final diag = OmrImaging.runDiagnostics(
          frame,
          lockedCorners:
              _fiducialLock.corners.where((c) => c.locked).length,
        );
        if (mounted) setState(() => _diagnostics = diag);
      } catch (_) {}
    }
  }

  bool get _readyToCapture =>
      _assessmentIdentified &&
      _selectedTemplate != null &&
      _selectedTemplate!.hasLayoutItems &&
      _fiducialLock.allFresh &&
      _fiducialLock.lockDuration >= 5 &&
      _alignedPreviewBytes != null &&
      _gradeSnapshot != null &&
      !_isCapturing &&
      !_isIdentifying;

  bool _shouldAutoCapture(FiducialLockState next) =>
      _assessmentIdentified &&
      _selectedTemplate != null &&
      _selectedTemplate!.hasLayoutItems &&
      next.allFresh &&
      next.lockDuration >= 5 &&
      _alignedPreviewBytes != null &&
      _gradeSnapshot != null &&
      !_isCapturing &&
      !_isIdentifying;

  Future<void> _manualCapture() async {
    if (_isCapturing) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    _isCapturing = true;
    try {
      final snapshot = _gradeSnapshot;
      if (snapshot == null || !snapshot.isComplete) {
        _isCapturing = false;
        if (mounted) _startImageStream();
        return;
      }
      HapticFeedback.mediumImpact();
      final sheetJpeg = OmrImaging.alignedSheetJpeg(
            luma: snapshot.hasDisplayLuma
                ? snapshot.displayLuma!
                : snapshot.luma,
            width: snapshot.hasDisplayLuma
                ? snapshot.displayWidth!
                : snapshot.width,
            height: snapshot.hasDisplayLuma
                ? snapshot.displayHeight!
                : snapshot.height,
            arucoXy: snapshot.hasDisplayLuma
                ? snapshot.displayArucoXy!
                : snapshot.arucoXy,
            frame: OmrFrame.active,
          ) ??
          _alignedPreviewBytes;
      await _stopImageStream();
      if (!mounted) return;
      setState(() {
        _resultPreviewBytes = sheetJpeg;
        _resultProcessing = true;
        _resultStatus = 'Aligning sheet…';
        _lastOmrResult = null;
        _mode = _ScreenMode.result;
        final selected = _selectedTemplate;
        if (selected != null) _snapshotResultKey(selected);
      });
      _startResultStatusCycle(); // fallback labels until first milestone
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final image = await _controller!.takePicture();
      // Kill torch for results UI; preference kept for Scan next.
      await _applyTorch(false);
      if (!mounted) return;
      setState(() => _resultCapturePath = image.path);
      final jobId = ++_omrJobId;
      _processScanInBackground(image.path, jobId, snapshot);
    } catch (e) {
      debugPrint("Capture error: $e");
      _isCapturing = false;
      if (mounted) {
        setState(() {
          _mode = _ScreenMode.scanning;
          _resultProcessing = false;
        });
        _startImageStream();
      }
    }
  }

  void _startResultStatusCycle() {
    // Fake timed labels are skipped: real OMR milestones arrive via onProgress.
    // Keep a single fallback only if the isolate is silent for a few seconds.
    _resultStatusTimer?.cancel();
    _resultStatusTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_resultProcessing) return;
      if (_resultStatus == 'Aligning sheet…' ||
          _resultStatus == 'Realigning sheet…') {
        setState(() => _resultStatus = 'Processing sheet…');
      }
    });
  }

  void _bindOmrResult(OmrResult result) {
    _lastOmrResult = result;
  }

  void _snapshotResultKey(BubbleTemplate template) {
    _resultAnswerKey = Map<String, String>.from(template.answerKey);
    _resultTotalItems = template.totalItems;
  }

  Future<void> _rescanCurrent() async {
    final expectedStudent = _lastOmrResult?.studentIdentifier ??
        _pendingUploadRecord?.studentIdentifier;
    final expectedAssessment = _lastOmrResult?.assessmentId ??
        _qrKeyOf(_selectedTemplate);
    final replaceId = _pendingUploadRecord?.id;

    _omrJobId++;
    _resultStatusTimer?.cancel();
    final pending = _pendingUploadRecord;
    _pendingUploadRecord = null;
    if (pending != null) {
      await ScanHistory.removeRecord(pending.id);
      _scanRecords.removeWhere((r) => r.id == pending.id);
    }
    if (!mounted) return;
    _beginRescanSession(
      expectedStudentId: expectedStudent,
      expectedAssessmentId: expectedAssessment,
      replaceRecordId: replaceId,
    );
  }

  void _beginRescanSession({
    String? expectedStudentId,
    String? expectedAssessmentId,
    String? replaceRecordId,
  }) {
    setState(() {
      _rescanExpectedStudentId = expectedStudentId;
      _rescanExpectedAssessmentId = expectedAssessmentId;
      _rescanReplaceRecordId = replaceRecordId;
      _detailRecord = null;
      _mode = _ScreenMode.scanning;
      _isCapturing = false;
      _resultProcessing = false;
      _lastOmrResult = null;
      _resultCapturePath = null;
      _resultPreviewBytes = null;
      _alignedPreviewBytes = null;
      _gradeSnapshot = null;
      _frameCount = 0;
      _resultStatus = '';
      _uploadStatus = 'idle';
      _pendingUploadRecord = null;
      _resultAnswerKey = const {};
      _resultTotalItems = 0;
      _fiducialLock = FiducialLockState.initial();
    });
    _startImageStream();
  }

  void _clearRescanLock() {
    _rescanExpectedStudentId = null;
    _rescanExpectedAssessmentId = null;
    _rescanReplaceRecordId = null;
  }

  bool _sameId(String? a, String? b) {
    final x = (a ?? '').trim().toUpperCase();
    final y = (b ?? '').trim().toUpperCase();
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
  }

  bool get _isRescanSession =>
      _rescanExpectedStudentId != null || _rescanExpectedAssessmentId != null;

  void _scanNext() {
    _omrJobId++;
    _resultStatusTimer?.cancel();
    _clearRescanLock();
    setState(() {
      _mode = _ScreenMode.scanning;
      _isCapturing = false;
      _resultProcessing = false;
      _lastOmrResult = null;
      _resultCapturePath = null;
      _resultPreviewBytes = null;
      _alignedPreviewBytes = null;
      _gradeSnapshot = null;
      _frameCount = 0;
      _resultStatus = '';
      _uploadStatus = 'idle';
      _pendingUploadRecord = null;
      _resultAnswerKey = const {};
      _resultTotalItems = 0;
      _fiducialLock = FiducialLockState.initial();
    });
    _startImageStream();
  }

  Future<void> _processScanInBackground(
    String imagePath,
    int jobId,
    OmrGradeSnapshot snapshot,
  ) async {
    try {
      final selected = _selectedTemplate;
      if (selected == null) {
        _isCapturing = false;
        if (mounted) {
          setState(() {
            _resultProcessing = false;
            _resultStatus = 'No assessment loaded';
            _uploadStatus = 'rejected';
          });
        }
        return;
      }

      BubbleTemplate scanTemplate = selected;

      if (!scanTemplate.hasLayoutItems || scanTemplate.answerKey.isEmpty) {
        final saved = await TemplateCache.find(scanTemplate.templateId);
        if (saved != null &&
            (saved.hasLayoutItems || saved.answerKey.isNotEmpty)) {
          scanTemplate = _richerTemplate(scanTemplate, saved);
        }
        if ((!scanTemplate.hasLayoutItems || scanTemplate.answerKey.isEmpty) &&
            await OfflinePack.probe()) {
          try {
            if (scanTemplate.isQuickExam) {
              scanTemplate = await _fetchQuickTemplate(scanTemplate.templateId);
            } else if (!scanTemplate.hasLayoutItems) {
              scanTemplate = await _repository
                  .fetchTemplateDetail(scanTemplate.templateId);
            }
            if (!scanTemplate.isQuickExam &&
                scanTemplate.answerKey.isEmpty &&
                scanTemplate.assessmentId != null) {
              scanTemplate = await _repository
                  .syncKeyFromAssessment(scanTemplate.templateId);
            }
            if (mounted) {
              setState(() {
                _selectedTemplate = scanTemplate;
                _snapshotResultKey(scanTemplate);
              });
              _updateCachedTemplate(scanTemplate);
            }
          } catch (e) {
            debugPrint('Failed to load template layout/key: $e');
            if (isOfflineError(e)) OfflinePack.markOffline();
          }
        } else if (mounted) {
          setState(() {
            _selectedTemplate = scanTemplate;
            _snapshotResultKey(scanTemplate);
          });
        }
      } else if (mounted) {
        setState(() => _snapshotResultKey(scanTemplate));
      }
      if (jobId != _omrJobId || !mounted) return;

      if (!scanTemplate.hasLayoutItems) {
        _isCapturing = false;
        if (mounted) {
          setState(() {
            _resultProcessing = false;
            _resultStatus = 'Regenerate PDF first';
            _uploadStatus = 'rejected';
          });
        }
        return;
      }

      if (scanTemplate.answerKey.isEmpty) {
        _isCapturing = false;
        if (mounted) {
          setState(() {
            _resultProcessing = false;
            _resultStatus = 'No answer key for this assessment';
            _uploadStatus = 'rejected';
          });
        }
        return;
      }

      if (mounted) {
        setState(() => _resultStatus = 'Aligning sheet…');
      }

      final omrService = OmrService();
      var result = await omrService.scanImage(
        imagePath,
        scanTemplate,
        gradeSnapshot: snapshot,
        onProgress: (status) {
          if (!mounted || jobId != _omrJobId) return;
          _resultStatusTimer?.cancel();
          setState(() => _resultStatus = status);
        },
      );
      if (jobId != _omrJobId || !mounted) return;

      // Hard gate: never save/upload unaligned (direct) captures.
      if (!result.isAlignmentUsable) {
        _resultStatusTimer?.cancel();
        if (mounted) {
          setState(() {
            _bindOmrResult(result);
            _isCapturing = false;
            _resultProcessing = false;
            _uploadStatus = 'rejected';
            _resultStatus =
                'Sheet not aligned — fit all 4 black squares in frame and rescan';
          });
        }
        return;
      }

      _resultStatusTimer?.cancel();
      final String gatedId;
      if (scanTemplate.isQuickExam) {
        // Quick exams have no class list: record whatever ID the sheet shows.
        setState(() => _bindOmrResult(result));
        gatedId = (result.studentIdentifier ?? '').trim().isEmpty
            ? 'Unknown'
            : result.studentIdentifier!;
      } else {
        // Only students already on a section may be recorded.
        setState(() {
          _bindOmrResult(result);
          _resultStatus = 'Checking student section…';
        });
        final sectioned =
            await _gateStudentSection(result.studentIdentifier, scanTemplate);
        if (jobId != _omrJobId || !mounted) return;
        if (sectioned == null) {
          _scanNext();
          return;
        }
        gatedId = sectioned;
      }
      if (gatedId != result.studentIdentifier) {
        result = result.withStudentIdentifier(gatedId);
      }

      final finalStudentId = gatedId;
      final finalAssessmentId =
          result.assessmentId ?? _qrKeyOf(scanTemplate);

      // Rescan lock: must be the same student + assessment sheet.
      if (_isRescanSession) {
        final studentOk = _rescanExpectedStudentId == null ||
            _sameId(_rescanExpectedStudentId, finalStudentId);
        final assessmentOk = _rescanExpectedAssessmentId == null ||
            _sameId(_rescanExpectedAssessmentId, finalAssessmentId);
        if (!studentOk || !assessmentOk) {
          _resultStatusTimer?.cancel();
          if (mounted) {
            setState(() {
              _bindOmrResult(result);
              _isCapturing = true;
              _resultProcessing = true;
              _uploadStatus = 'idle';
              _resultStatus =
                  'Rescanning aborted — new answer sheet detected.';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Rescanning aborted — new answer sheet detected.',
                ),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 4),
              ),
            );
          }

          // Hold abort message, then countdown, then save as a new record.
          await Future<void>.delayed(const Duration(seconds: 5));
          if (jobId != _omrJobId || !mounted) return;

          for (var n = 3; n >= 1; n--) {
            if (!mounted || jobId != _omrJobId) return;
            setState(() {
              _resultStatus = 'Scanning new paper… in $n';
            });
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          if (jobId != _omrJobId || !mounted) return;

          // Drop rescan lock so this sheet is saved as a new record.
          _clearRescanLock();
        }
      }

      if (mounted) {
        setState(() {
          _bindOmrResult(result);
          _resultStatus = 'Saving on this device…';
          _uploadStatus = 'uploading';
        });
      }

      // Check for duplicate scan (same student + same assessment)
      final allRecords = await ScanHistory.getAll();
      if (jobId != _omrJobId || !mounted) return;
      final canMatchStudent =
          !scanTemplate.isQuickExam || isUsableStudentId(finalStudentId);
      final duplicate = allRecords.where(
        (r) =>
            canMatchStudent &&
            r.studentIdentifier == finalStudentId &&
            r.templateId == scanTemplate.templateId &&
            r.id != _rescanReplaceRecordId,
      );
      // Intentional rescan of a known record: replace it without dialog.
      if (_rescanReplaceRecordId != null) {
        await ScanHistory.removeRecord(_rescanReplaceRecordId!);
        if (mounted) {
          setState(() {
            _scanRecords.removeWhere((r) => r.id == _rescanReplaceRecordId);
          });
        }
      } else if (duplicate.isNotEmpty && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Already Recorded',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text(
              '$finalStudentId has already been scanned for this assessment.\n\nContinuing will overwrite the previous record.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: grayText)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Rescan',
                    style:
                        TextStyle(color: primaryRed, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (jobId != _omrJobId || !mounted) return;
        if (confirmed != true) {
          if (jobId != _omrJobId) return;
          if (mounted) {
            setState(() {
              _resultProcessing = false;
              _isCapturing = false;
              _uploadStatus = 'rejected';
            });
          }
          return;
        }
        for (final old in duplicate) {
          await ScanHistory.removeRecord(old.id);
          if (mounted) {
            setState(() {
              _scanRecords.removeWhere((r) => r.id == old.id);
            });
          }
        }
      }

      final record = ScanRecord(
        id: 'scan_${DateTime.now().millisecondsSinceEpoch}',
        templateId: scanTemplate.templateId,
        templateName: scanTemplate.name,
        studentIdentifier: finalStudentId,
        responses: result.responses,
        answerKey: Map<String, String>.from(scanTemplate.answerKey),
        scorePercent: result.scorePercent,
        scoreRaw: result.scoreRaw,
        maxScore: result.maxScore.toDouble(),
        isFlagged: result.isFlagged,
        flagReason: result.flagReason,
        flaggedItems: result.flaggedItems,
        imagePath: imagePath,
        createdAt: DateTime.now(),
        isQuickExam: scanTemplate.isQuickExam,
      );

      await ScanHistory.addRecord(record);
      unawaited(OfflinePack.refreshLocalAttention());
      if (jobId != _omrJobId) {
        await ScanHistory.removeRecord(record.id);
        unawaited(OfflinePack.refreshLocalAttention());
        return;
      }
      _pendingUploadRecord = record;
      _clearRescanLock();

      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);

      _resultStatusTimer?.cancel();
      if (mounted) {
        setState(() {
          _scanRecords.insert(0, record);
          _isCapturing = false;
          _resultProcessing = false;
          _bindOmrResult(result);
          _resultStatus = _uploadingLabel(record);
          _uploadStatus = 'uploading';
        });
      }
      if (await OfflinePack.probe()) {
        await _attemptBackgroundUpload(record);
      } else if (mounted) {
        setState(() {
          _uploadStatus = 'queued';
          _resultStatus =
              'Saved on this device. It will sync when you are back online.';
        });
      }
    } catch (e) {
      debugPrint("OMR processing error: $e");
      _resultStatusTimer?.cancel();
      if (jobId != _omrJobId || !mounted) return;
      setState(() {
        _isCapturing = false;
        _resultProcessing = false;
        _resultStatus = 'Scan error — try again';
        _uploadStatus = 'rejected';
      });
    }
  }

  String _uploadingLabel(ScanRecord record) => record.isQuickExam
      ? 'Saving to exam records…'
      : 'Uploading to grading results…';

  void _markUploadQueued(Object error) {
    final offline = isOfflineError(error);
    if (offline) OfflinePack.markOffline();
    setState(() {
      _uploadStatus = offline ? 'queued' : 'failed';
      _resultStatus = offline
          ? 'Saved on this device. It will sync when you are back online.'
          : friendlyError(
              error,
              fallback: 'Saved on this device. Tap retry to sync.',
            );
    });
  }

  Future<void> _attemptBackgroundUpload(
    ScanRecord record, {
    bool allowRetry = true,
  }) async {
    final track = _pendingUploadRecord?.id == record.id;
    if (mounted && track) {
      setState(() {
        _uploadStatus = 'uploading';
        _resultStatus = _uploadingLabel(record);
      });
    }
    try {
      final synced = await OfflineSync.instance.upload(record);
      if (!mounted) return;
      setState(() {
        final idx = _scanRecords.indexWhere((r) => r.id == record.id);
        if (idx >= 0) {
          _scanRecords[idx] =
              _scanRecords[idx].copyWith(serverScanId: synced.serverScanId);
        }
        if (_detailRecord?.id == record.id) {
          _detailRecord =
              _detailRecord!.copyWith(serverScanId: synced.serverScanId);
        }
        if (track && _pendingUploadRecord?.id == record.id) {
          _pendingUploadRecord =
              record.copyWith(serverScanId: synced.serverScanId);
          _uploadStatus = 'uploaded';
          _resultStatus = synced.replaced
              ? 'Replaced earlier exam record'
              : (record.isQuickExam
                  ? 'Saved to exam records'
                  : 'Saved to grading results');
        }
      });
    } on StudentNotInSectionException catch (e) {
      debugPrint('Upload refused: $e');
      await _resolveUnsectionedRecord(record, allowRetry: allowRetry);
    } catch (e) {
      debugPrint('Upload graded scan failed: $e');
      if (!mounted || !track || _pendingUploadRecord?.id != record.id) return;
      _markUploadQueued(e);
    }
  }

  /// Server refused the paper because its student is not on a section:
  /// add the student and re-upload, or discard the local paper.
  Future<void> _resolveUnsectionedRecord(
    ScanRecord record, {
    required bool allowRetry,
  }) async {
    _sectionedBlocks.remove(record.studentIdentifier);
    final template = _templates.cast<BubbleTemplate?>().firstWhere(
          (t) => t?.templateId == record.templateId,
          orElse: () => null,
        ) ??
        _selectedTemplate;
    final gatedId = (allowRetry && template != null && mounted)
        ? await _gateStudentSection(record.studentIdentifier, template)
        : null;

    if (gatedId == null) {
      await ScanHistory.removeRecord(record.id);
      if (!mounted) return;
      setState(() => _scanRecords.removeWhere((r) => r.id == record.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scan of ${record.studentIdentifier} disregarded — student is not on any section.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (_mode == _ScreenMode.result && _pendingUploadRecord?.id == record.id) {
        _scanNext();
      }
      return;
    }

    final updated = record.copyWith(studentIdentifier: gatedId);
    await ScanHistory.updateRecord(record.id, {'student_identifier': gatedId});
    if (!mounted) return;
    setState(() {
      final idx = _scanRecords.indexWhere((r) => r.id == record.id);
      if (idx >= 0) _scanRecords[idx] = updated;
      if (_pendingUploadRecord?.id == record.id) {
        _pendingUploadRecord = updated;
        final last = _lastOmrResult;
        if (last != null) _lastOmrResult = last.withStudentIdentifier(gatedId);
      }
    });
    await _attemptBackgroundUpload(updated, allowRetry: false);
  }

  Future<void> _retryUpload() async {
    final record = _pendingUploadRecord;
    if (record == null) return;
    await _attemptBackgroundUpload(record);
  }

  Future<void> _loadScanRecords() async {
    setState(() => _isLoadingRecords = true);
    try {
      final records = await ScanHistory.getRecent();
      if (mounted) setState(() { _scanRecords = records; _isLoadingRecords = false; });
    } catch (_) { if (mounted) setState(() => _isLoadingRecords = false); }
  }

  void _openReview() {
    _stopImageStream();
    _applyTorch(false); // leave live cam dark; preference kept for return
    setState(() => _mode = _ScreenMode.review);
  }
  void _closeReview() { setState(() => _mode = _ScreenMode.scanning); _startImageStream(); }

  BubbleTemplate? _matchQr(List<BubbleTemplate> list, String qr) {
    final quickId = quickExamIdFromQr(qr);
    for (final t in list) {
      if (_sameId(_qrKeyOf(t), qr) ||
          _sameId(t.assessmentId, qr) ||
          _sameId(t.templateId, qr) ||
          (quickId != null && _sameId(t.templateId, quickId))) {
        return t;
      }
    }
    return null;
  }

  Future<BubbleTemplate?> _templateForQr(String assessmentId) async {
    final inMemory = _matchQr(_templates, assessmentId);
    if (inMemory != null) return inMemory;
    final disk = await TemplateCache.load();
    final saved = disk == null ? null : _matchQr(disk, assessmentId);
    if (saved != null) return saved;
    if (!await OfflinePack.probe()) return null;
    final quickId = quickExamIdFromQr(assessmentId);
    if (quickId != null) return _fetchQuickTemplate(quickId);
    return _repository.fetchTemplateByAssessment(assessmentId);
  }

  Future<void> _identifyAssessmentFromQr(String assessmentId) async {
    if (_isIdentifying) return;
    _isIdentifying = true;
    if (mounted) setState(() => _identifyError = null);

    try {
      final seed = await _templateForQr(assessmentId);
      if (seed == null) {
        final online = await OfflinePack.probe();
        if (mounted) {
          setState(() {
            _identifyError = online
                ? 'Assessment QR not found in system'
                : 'This answer sheet is not on this device yet. Connect once so it can download.';
            _assessmentIdentified = false;
          });
        }
        return;
      }
      await _bindTemplateFromQr(seed);
    } catch (e) {
      debugPrint('Failed to identify assessment via QR: $e');
      if (mounted) {
        final offline = isOfflineError(e);
        if (offline) OfflinePack.markOffline();
        setState(() {
          _identifyError = offline
              ? 'This answer sheet is not on this device yet. Connect once so it can download.'
              : 'Assessment QR not found in system';
          _assessmentIdentified = false;
        });
      }
    } finally {
      _isIdentifying = false;
    }
  }

  Future<void> _deleteRecord(ScanRecord record) async {
    await ScanHistory.removeRecord(record.id);
    if (mounted) {
      setState(() {
        _scanRecords.removeWhere((r) => r.id == record.id);
        if (_detailRecord?.id == record.id) _detailRecord = null;
      });
    }
  }

  Future<void> _openPaperDetail(ScanRecord record) async {
    setState(() {
      _detailRecord = record;
      _mode = _ScreenMode.detail;
    });
    // Prefer the key snapped at scan time; still refresh template for edits/rescan.
    if (record.answerKey.isEmpty) {
      await _ensureTemplateForRecord(record);
    } else {
      _ensureTemplateForRecord(record);
    }
  }

  bool _treatRecordAsQuickExam(ScanRecord record) {
    if (record.isQuickExam) return true;
    if (_selectedTemplate?.templateId == record.templateId &&
        _selectedTemplate!.isQuickExam) {
      return true;
    }
    return _templates.any(
      (t) => t.templateId == record.templateId && t.isQuickExam,
    );
  }

  /// Review detail needs the full answer key for correct/incorrect coloring.
  Future<void> _ensureTemplateForRecord(ScanRecord record) async {
    BubbleTemplate? current = _selectedTemplate;
    if (current?.templateId == record.templateId &&
        current!.answerKey.isNotEmpty) {
      // Backfill older local records that lacked a snapped key.
      if (record.answerKey.isEmpty && _detailRecord?.id == record.id) {
        final filled = record.copyWith(
          answerKey: Map<String, String>.from(current.answerKey),
        );
        await ScanHistory.updateRecord(record.id, filled.toJson());
        if (mounted) {
          setState(() {
            _detailRecord = filled;
            final idx = _scanRecords.indexWhere((r) => r.id == record.id);
            if (idx >= 0) _scanRecords[idx] = filled;
          });
        }
      }
      return;
    }
    final cachedIdx =
        _templates.indexWhere((t) => t.templateId == record.templateId);
    final cached = cachedIdx >= 0 ? _templates[cachedIdx] : null;
    if (cached != null && cached.answerKey.isNotEmpty) {
      if (mounted) setState(() => _selectedTemplate = cached);
      if (record.answerKey.isEmpty && _detailRecord?.id == record.id) {
        final filled = record.copyWith(
          answerKey: Map<String, String>.from(cached.answerKey),
        );
        await ScanHistory.updateRecord(record.id, filled.toJson());
        if (mounted) {
          setState(() {
            _detailRecord = filled;
            final idx = _scanRecords.indexWhere((r) => r.id == record.id);
            if (idx >= 0) _scanRecords[idx] = filled;
          });
        }
      }
      return;
    }
    final disk = await TemplateCache.find(record.templateId);
    if (disk != null && disk.answerKey.isNotEmpty) {
      if (mounted) setState(() => _selectedTemplate = disk);
      if (record.answerKey.isEmpty && _detailRecord?.id == record.id) {
        final filled = record.copyWith(
          answerKey: Map<String, String>.from(disk.answerKey),
        );
        await ScanHistory.updateRecord(record.id, filled.toJson());
        if (mounted) {
          setState(() {
            _detailRecord = filled;
            final idx = _scanRecords.indexWhere((r) => r.id == record.id);
            if (idx >= 0) _scanRecords[idx] = filled;
          });
        }
      }
      return;
    }
    if (!await OfflinePack.probe()) return;
    try {
      final asQuick = _treatRecordAsQuickExam(record);
      late BubbleTemplate bound;
      if (asQuick) {
        bound = await _fetchQuickTemplate(record.templateId);
      } else {
        try {
          bound = await _repository.fetchTemplateDetail(record.templateId);
        } catch (_) {
          // Older quick-exam scans may lack isQuickExam; fall back to quick API.
          bound = await _fetchQuickTemplate(record.templateId);
        }
      }
      if (!bound.isQuickExam &&
          bound.answerKey.isEmpty &&
          bound.assessmentId != null) {
        bound = await _repository.syncKeyFromAssessment(bound.templateId);
      }
      if (!mounted) return;
      setState(() {
        _selectedTemplate = bound;
        final idx =
            _templates.indexWhere((t) => t.templateId == bound.templateId);
        if (idx >= 0) {
          _templates[idx] = bound;
        } else {
          _templates.add(bound);
        }
      });
      _updateCachedTemplate(bound);
      if (record.answerKey.isEmpty &&
          bound.answerKey.isNotEmpty &&
          _detailRecord?.id == record.id) {
        final filled = record.copyWith(
          answerKey: Map<String, String>.from(bound.answerKey),
        );
        await ScanHistory.updateRecord(record.id, filled.toJson());
        if (mounted) {
          setState(() {
            _detailRecord = filled;
            final idx = _scanRecords.indexWhere((r) => r.id == record.id);
            if (idx >= 0) _scanRecords[idx] = filled;
          });
        }
      }
    } catch (e) {
      debugPrint('Detail template fetch failed: $e');
    }
  }

  void _closePaperDetail() {
    setState(() { _detailRecord = null; _mode = _ScreenMode.review; });
  }

  void _editAnswers(ScanRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditAnswersSheet(
        record: record,
        template: _selectedTemplate,
        onSave: (updatedResponses) => _onSaveEditedAnswers(record, updatedResponses),
      ),
    );
  }

  Future<void> _onSaveEditedAnswers(ScanRecord record, Map<String, String> updatedResponses) async {
    int correct = 0;
    final key = record.answerKey.isNotEmpty
        ? record.answerKey
        : (_selectedTemplate?.answerKey ?? {});
    final total = key.isNotEmpty
        ? key.length
        : (_selectedTemplate?.totalItems ?? updatedResponses.length);
    final flagged = <int>[];
    for (var i = 1; i <= total; i++) {
      final item = i.toString();
      final resp = (updatedResponses[item] ?? '?').trim();
      final expected = key[item] ?? key[item.padLeft(2, '0')];
      final ambiguous = resp.isEmpty ||
          resp == '?' ||
          resp.replaceAll(RegExp(r'[^A-Za-z]'), '').length > 1;
      if (isBonusKey(expected)) {
        correct++;
      } else if (ambiguous) {
        flagged.add(i);
      } else if (isKeyCorrect(resp, expected)) {
        correct++;
      }
    }
    final pct = total > 0 ? (correct / total) * 100.0 : 0.0;
    final updated = record.copyWith(
      responses: updatedResponses,
      scorePercent: pct,
      scoreRaw: correct.toDouble(),
      maxScore: total.toDouble(),
      isFlagged: flagged.isNotEmpty,
      flagReason: flagged.isEmpty ? null : '${flagged.length} invalid item(s)',
      clearFlagReason: flagged.isEmpty,
      flaggedItems: flagged,
    );
    await ScanHistory.updateRecord(record.id, updated.toJson());
    if (mounted) {
      setState(() {
        final idx = _scanRecords.indexWhere((r) => r.id == record.id);
        if (idx >= 0) _scanRecords[idx] = updated;
        if (_detailRecord?.id == record.id) _detailRecord = updated;
      });
    }
  }

  Future<void> _reScanPaper(ScanRecord record) async {
    await _ensureTemplateForRecord(record);
    final assessmentId = _qrKeyOf(_selectedTemplate);
    _beginRescanSession(
      expectedStudentId: record.studentIdentifier,
      expectedAssessmentId: assessmentId,
      replaceRecordId: record.id,
    );
  }

  Future<void> _uploadRecord(ScanRecord record) async {
    await _attemptBackgroundUpload(record);
    _loadScanRecords();
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _ScreenMode.scanning) {
      _updateROI(MediaQuery.of(context).size);
    }

    if (_mode == _ScreenMode.detail && _detailRecord != null) {
      return PaperDetailView(
        record: _detailRecord!,
        template: _selectedTemplate,
        passingScore: _selectedTemplate?.passingScore ?? 50,
        onBack: _closePaperDetail,
        onEditAnswers: () => _editAnswers(_detailRecord!),
        onReScan: () => _reScanPaper(_detailRecord!),
        onUpload: () => _uploadRecord(_detailRecord!),
      );
    }

    if (_mode == _ScreenMode.result) {
      final resultKey = _resultAnswerKey.isNotEmpty
          ? _resultAnswerKey
          : (_selectedTemplate?.answerKey ?? const {});
      final resultTotal = _resultTotalItems > 0
          ? _resultTotalItems
          : (_selectedTemplate?.totalItems ?? 0);
      return ScanResultView(
        previewBytes: _resultPreviewBytes,
        fallbackImagePath: _resultCapturePath,
        isProcessing: _resultProcessing,
        statusMessage: _resultStatus,
        result: _lastOmrResult,
        uploadStatus: _uploadStatus,
        passingScore: _selectedTemplate?.passingScore ?? 50,
        answerKey: resultKey,
        totalItems: resultTotal,
        onScanNext: _scanNext,
        onRescan: _rescanCurrent,
        onRetryUpload: _uploadStatus == 'failed' || _uploadStatus == 'queued'
            ? _retryUpload
            : null,
        onClose: _scanNext,
      );
    }

    if (_mode == _ScreenMode.review) {
      return ReviewPapersView(
        records: _scanRecords,
        isLoading: _isLoadingRecords,
        onBack: _closeReview,
        onRefresh: _loadScanRecords,
        onTapRecord: _openPaperDetail,
        onReScan: _reScanPaper,
        onUpload: _uploadRecord,
        onDelete: _deleteRecord,
      );
    }

    // Live camera always — assessment comes from the sheet QR.
    return LiveScanningView(
      controller: _controller,
      isReady: _isCameraReady,
      templateName: _selectedTemplate?.name,
      assessmentIdentified: _assessmentIdentified,
      identifyHint: _identifyError ??
          (_isIdentifying
              ? 'Loading answer key…'
              : 'Point camera at Assessment QR'),
      fiducialLock: _fiducialLock,
      diagnostics: _diagnostics,
      scoreFlashText: _scoreFlashText,
      scoreFlashAnimation: _scoreFlashAnimation,
      readyToCapture: _readyToCapture,
      alignedPreviewBytes: _alignedPreviewBytes,
      torchOn: _torchHardwareOn,
      onToggleTorch: _toggleTorch,
      onCapture: _manualCapture,
      onBack: () => Navigator.pop(context),
      onReviewPapers: _openReview,
    );
  }
}
