import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import 'omr_imaging.dart';
import 'omr_models.dart';
import 'omr_service.dart';
import 'scan_history.dart';
import 'scanner_widgets.dart';
import 'template_cache.dart';

class ScannerScreen extends StatefulWidget {
  final String? preSelectedCourseId;
  final String? preSelectedCourseName;

  const ScannerScreen({
    super.key,
    this.preSelectedCourseId,
    this.preSelectedCourseName,
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

  Timer? _torchTimer;
  Timer? _resultStatusTimer;

  List<ScanRecord> _scanRecords = [];
  bool _isLoadingRecords = false;

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
    _initScanner();
  }

  Future<void> _initScanner() async {
    // Camera first — assessment is chosen by QR on the sheet, not by UI.
    await _setupCamera();
    _loadScanRecords();
    // Background cache of course templates (faster QR match when already known).
    _loadTemplates();
  }

  @override
  void dispose() {
    _torchTimer?.cancel();
    _resultStatusTimer?.cancel();
    _stopImageStream();
    _controller?.dispose();
    _scoreFlashController?.dispose();
    OmrImaging.disposeScanner();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final cached = await TemplateCache.load();
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() => _templates = cached);
      }
      await _fetchFromNetwork();
    } catch (e) {
      debugPrint('Template cache load failed: $e');
    }
  }

  Future<void> _fetchFromNetwork() async {
    final courseId = widget.preSelectedCourseId;
    if (courseId != null && courseId.isNotEmpty) {
      final templates = await _repository.fetchTemplates(courseId);
      await TemplateCache.store(templates);
      if (mounted) setState(() => _templates = templates);
      return;
    }
    final courses = await _repository.fetchFacultyCourses();
    if (courses.isNotEmpty) {
      final templates =
          await _repository.fetchTemplates(courses.first['course_id']!);
      await TemplateCache.store(templates);
      if (mounted) setState(() => _templates = templates);
    }
  }

  /// Bind the live template from assessment QR: layout + answer key.
  Future<void> _bindTemplateFromQr(BubbleTemplate seed) async {
    BubbleTemplate bound = seed;
    try {
      // Always pull full detail so layout_metadata.items is present.
      bound = await _repository.fetchTemplateDetail(seed.templateId);
    } catch (e) {
      debugPrint('Template detail fetch failed: $e');
    }

    if (bound.answerKey.isEmpty && bound.assessmentId != null) {
      try {
        bound = await _repository.syncKeyFromAssessment(bound.templateId);
      } catch (e) {
        debugPrint('Answer key sync failed: $e');
      }
    }

    if (!mounted) return;
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

  void _updateCachedTemplate(BubbleTemplate updated) {
    final all = List<BubbleTemplate>.from(_templates);
    final idx = all.indexWhere((t) => t.templateId == updated.templateId);
    if (idx >= 0) all[idx] = updated;
    _templates = all;
    TemplateCache.store(all);
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
        _startTorchAutoToggle();
        await _syncTorch(); // must complete before starting stream
        if (mounted) { setState(() => _isCameraReady = true); _startImageStream(); }
      }
    } catch (e) { debugPrint("Camera init error: $e"); }
  }

  /// Torch ON 6:00 PM – 4:59 AM, OFF 5:00 AM – 5:59 PM.
  void _startTorchAutoToggle() {
    _syncTorch(); // immediate
    _torchTimer = Timer.periodic(const Duration(minutes: 1), (_) => _syncTorch());
  }

  Future<void> _syncTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final hour = DateTime.now().hour;
    final shouldBeOn = hour >= 18 || hour < 5;
    try {
      await _controller!.setFlashMode(
        shouldBeOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (_) {}
  }

  Future<void> _startImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized || _isStreaming) return;
    try {
      await _controller!.startImageStream(_onFrame);
      _isStreaming = true;
      _syncTorch(); // re-apply flash after returning to scanner
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

      final det = OmrImaging.detectFiducialsLive(
        frame,
        previewSize: _controller?.value.previewSize,
        buildAlignedPreview: wantWarp,
        copyGradeSnapshot: wantWarp,
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
              if (_selectedTemplate?.assessmentId != assessmentId) {
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
      });
      _startResultStatusCycle(); // fallback labels until first milestone
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final image = await _controller!.takePicture();
      if (!mounted) return;
      setState(() => _resultCapturePath = image.path);
      final jobId = ++_omrJobId;
      _processScanInBackground(image.path, jobId, snapshot);
      _syncTorch();
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

  Future<void> _rescanCurrent() async {
    final expectedStudent = _lastOmrResult?.studentIdentifier ??
        _pendingUploadRecord?.studentIdentifier;
    final expectedAssessment = _lastOmrResult?.assessmentId ??
        _selectedTemplate?.assessmentId;
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
        try {
          if (!scanTemplate.hasLayoutItems) {
            scanTemplate =
                await _repository.fetchTemplateDetail(scanTemplate.templateId);
          }
          if (scanTemplate.answerKey.isEmpty &&
              scanTemplate.assessmentId != null) {
            scanTemplate =
                await _repository.syncKeyFromAssessment(scanTemplate.templateId);
          }
          if (mounted) {
            setState(() => _selectedTemplate = scanTemplate);
            _updateCachedTemplate(scanTemplate);
          }
        } catch (e) {
          debugPrint('Failed to load template layout/key: $e');
        }
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
      final result = await omrService.scanImage(
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

      final finalStudentId = result.studentIdentifier ?? 'Unknown';
      final finalAssessmentId =
          result.assessmentId ?? scanTemplate.assessmentId;

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
          _resultStatus = 'Saving to database…';
          _uploadStatus = 'uploading';
        });
      }

      // Check for duplicate scan (same student + same assessment)
      final allRecords = await ScanHistory.getAll();
      if (jobId != _omrJobId || !mounted) return;
      final duplicate = allRecords.where(
        (r) =>
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
        scorePercent: result.scorePercent,
        scoreRaw: result.scoreRaw,
        maxScore: result.maxScore.toDouble(),
        isFlagged: result.isFlagged,
        flagReason: result.flagReason,
        flaggedItems: result.flaggedItems,
        imagePath: imagePath,
        createdAt: DateTime.now(),
      );

      await ScanHistory.addRecord(record);
      if (jobId != _omrJobId) {
        await ScanHistory.removeRecord(record.id);
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
          _resultStatus = 'Uploading to grading results…';
          _uploadStatus = 'uploading';
        });
      }
      await _attemptBackgroundUpload(record);
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

  Future<void> _attemptBackgroundUpload(ScanRecord record) async {
    final path = record.imagePath;
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _uploadStatus = 'failed';
          _resultStatus = 'Upload failed — missing image';
        });
      }
      return;
    }

    if (mounted) {
        if (_pendingUploadRecord?.id != record.id) return;
        setState(() {
          _uploadStatus = 'uploading';
          _resultStatus = 'Uploading to grading results…';
        });
      }

    try {
      final scan = await _repository.uploadGradedScan(
        templateId: record.templateId,
        imagePath: path,
        studentId: record.studentIdentifier,
        responses: record.responses,
        isFlagged: record.isFlagged,
        flagReason: record.flagReason,
      );
      await ScanHistory.updateRecord(record.id, {'server_scan_id': scan.scanId});
      if (mounted) {
        if (_pendingUploadRecord?.id != record.id) return;
        setState(() {
          final idx = _scanRecords.indexWhere((r) => r.id == record.id);
          if (idx >= 0) {
            _scanRecords[idx] =
                _scanRecords[idx].copyWith(serverScanId: scan.scanId);
          }
          _pendingUploadRecord =
              record.copyWith(serverScanId: scan.scanId);
          _uploadStatus = 'uploaded';
          _resultStatus = 'Saved to grading results';
        });
      }
    } catch (e) {
      debugPrint('Upload graded scan failed: $e');
      if (!mounted || _pendingUploadRecord?.id != record.id) return;
      setState(() {
        _uploadStatus = 'failed';
        _resultStatus =
            'Saved on device — upload failed. Tap retry to sync.';
      });
    }
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

  void _openReview() { _stopImageStream(); setState(() => _mode = _ScreenMode.review); }
  void _closeReview() { setState(() => _mode = _ScreenMode.scanning); _startImageStream(); }

  Future<void> _identifyAssessmentFromQr(String assessmentId) async {
    if (_isIdentifying) return;
    _isIdentifying = true;
    if (mounted) setState(() => _identifyError = null);

    try {
      BubbleTemplate? seed;
      final cached = _templates.where((t) => t.assessmentId == assessmentId);
      if (cached.isNotEmpty) {
        seed = cached.first;
      } else {
        seed = await _repository.fetchTemplateByAssessment(assessmentId);
      }
      await _bindTemplateFromQr(seed);
    } catch (e) {
      debugPrint('Failed to identify assessment via QR: $e');
      if (mounted) {
        setState(() {
          _identifyError = 'Assessment QR not found in system';
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

  void _openPaperDetail(ScanRecord record) {
    setState(() {
      _detailRecord = record;
      _mode = _ScreenMode.detail;
    });
    _ensureTemplateForRecord(record);
  }

  /// Review detail needs the full answer key for correct/incorrect coloring.
  Future<void> _ensureTemplateForRecord(ScanRecord record) async {
    BubbleTemplate? current = _selectedTemplate;
    if (current?.templateId == record.templateId &&
        current!.answerKey.isNotEmpty) {
      return;
    }
    final cachedIdx =
        _templates.indexWhere((t) => t.templateId == record.templateId);
    final cached = cachedIdx >= 0 ? _templates[cachedIdx] : null;
    if (cached != null && cached.answerKey.isNotEmpty) {
      if (mounted) setState(() => _selectedTemplate = cached);
      return;
    }
    try {
      var bound = await _repository.fetchTemplateDetail(record.templateId);
      if (bound.answerKey.isEmpty && bound.assessmentId != null) {
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
    final key = _selectedTemplate?.answerKey ?? {};
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
      if (ambiguous) {
        flagged.add(i);
      } else if (expected != null &&
          resp.toUpperCase() == expected.trim().toUpperCase()) {
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
    final assessmentId = _selectedTemplate?.assessmentId;
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
      return ScanResultView(
        previewBytes: _resultPreviewBytes,
        fallbackImagePath: _resultCapturePath,
        isProcessing: _resultProcessing,
        statusMessage: _resultStatus,
        result: _lastOmrResult,
        uploadStatus: _uploadStatus,
        passingScore: _selectedTemplate?.passingScore ?? 50,
        onScanNext: _scanNext,
        onRescan: _rescanCurrent,
        onRetryUpload: _uploadStatus == 'failed' ? _retryUpload : null,
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
      onCapture: _manualCapture,
      onBack: () => Navigator.pop(context),
      onReviewPapers: _openReview,
    );
  }
}
