import 'dart:async';
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
  final BubbleTemplate? preselectedTemplate;

  const ScannerScreen({
    super.key,
    this.preSelectedCourseId,
    this.preSelectedCourseName,
    this.preselectedTemplate,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _ScreenMode { scanning, review, detail }

class _ScannerScreenState extends State<ScannerScreen> with TickerProviderStateMixin {

  

  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isStreaming = false;
  int _frameCount = 0;
  static const int _frameSkip = 3;
  int _lastQrCheckFrame = 0;
  int _lastDiagnosticsFrame = 0;
  int _lastOverlayFrame = 0;

  final GradingRepository _repository = GradingRepository();
  List<BubbleTemplate> _templates = [];
  BubbleTemplate? _selectedTemplate;
  bool _isLoadingTemplates = false;
  String? _templatesError;

  FiducialLockState _fiducialLock = FiducialLockState.initial();
  ScannerDiagnostics _diagnostics = ScannerDiagnostics.ok();
  // List<BubbleOverlayData> _liveBubbles = []; // Removed
  bool _assessmentIdentified = false;
  bool _isCapturing = false;
  bool _isFrameProcessing = false;
  static const int _lockThresholdFrames = 10;

  AnimationController? _scoreFlashController;
  Animation<double>? _scoreFlashAnimation;
  String? _scoreFlashText;

  Timer? _torchTimer;
  Timer? _focusTimer;

  List<ScanRecord> _scanRecords = [];
  bool _isLoadingRecords = false;

  _ScreenMode _mode = _ScreenMode.scanning;
  ScanRecord? _detailRecord;

  Rect? _roi;
  Size? _lastScreenSize;

  void _showScoreDialog(String studentId, double scoreRaw, double maxScore, double percent) {
    showDialog(
      context: context,
      barrierDismissible: false, // Forces the user to tap the button to close
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Scan Complete', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(studentId, style: const TextStyle(fontSize: 18, color: grayText, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text(
              '${percent.toStringAsFixed(1)}%', 
              style: TextStyle(
                fontSize: 48, 
                fontWeight: FontWeight.w900, 
                color: percent >= 60 ? Colors.green.shade700 : primaryRed
              )
            ),
            const SizedBox(height: 4),
            Text('${scoreRaw.toStringAsFixed(0)} / ${maxScore.toStringAsFixed(0)} correct', style: const TextStyle(fontSize: 16, color: darkText)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Scan Next Paper', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

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
    await _loadTemplates();
    await _setupCamera();
    _loadScanRecords();
  }

  @override
  void dispose() {
    _torchTimer?.cancel();
    _focusTimer?.cancel();
    _stopImageStream();
    _controller?.dispose();
    _scoreFlashController?.dispose();
    OmrImaging.disposeScanner();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() { _isLoadingTemplates = true; _templatesError = null; });
    try {
      final cached = await TemplateCache.load();
      if (cached != null && cached.isNotEmpty) {
        setState(() { _templates = cached; _isLoadingTemplates = false; });
        _autoSelectTemplate();
        _refreshTemplatesFromNetwork();
        return;
      }
      await _fetchFromNetwork();
    } catch (e) {
      setState(() { _isLoadingTemplates = false; _templatesError = e.toString().replaceAll('Exception: ', ''); });
    }
  }

  Future<void> _refreshTemplatesFromNetwork() async {
    try { await _fetchFromNetwork(); } catch (_) {}
  }

  Future<void> _fetchFromNetwork() async {
    final courseId = widget.preSelectedCourseId;
    if (courseId != null && courseId.isNotEmpty) {
      final templates = await _repository.fetchTemplates(courseId);
      await TemplateCache.store(templates);
      if (mounted) {
        setState(() { _templates = templates; _isLoadingTemplates = false; });
        _autoSelectTemplate();
      }
    } else {
      final courses = await _repository.fetchFacultyCourses();
      if (courses.isNotEmpty) {
        final templates = await _repository.fetchTemplates(courses.first['course_id']!);
        await TemplateCache.store(templates);
        if (mounted) {
          setState(() { _templates = templates; _isLoadingTemplates = false; });
          _autoSelectTemplate();
        }
      } else {
        setState(() { _templates = []; _isLoadingTemplates = false; _templatesError = 'No courses found.'; });
      }
    }
  }

  void _autoSelectTemplate() {
    if (widget.preselectedTemplate != null) {
      final match = _templates.where(
        (t) => t.templateId == widget.preselectedTemplate!.templateId,
      );
      if (match.isNotEmpty) {
        _onTemplateSelected(match.first);
        return;
      }
    }
    if (_templates.length == 1) _onTemplateSelected(_templates.first);
  }

  Future<void> _onTemplateSelected(BubbleTemplate t) async {
    setState(() { _selectedTemplate = t; _templatesError = null; });
    if (t.answerKey.isEmpty && t.hasAnswerKey) {
      setState(() => _isLoadingTemplates = true);
      try {
        final detail = await _repository.fetchTemplateDetail(t.templateId);
        if (mounted) { setState(() { _selectedTemplate = detail; _isLoadingTemplates = false; }); _updateCachedTemplate(detail); }
      } catch (_) { if (mounted) setState(() => _isLoadingTemplates = false); }
    } else if (t.answerKey.isEmpty && t.assessmentId != null) {
      setState(() => _isLoadingTemplates = true);
      try {
        final synced = await _repository.syncKeyFromAssessment(t.templateId);
        if (mounted) { setState(() { _selectedTemplate = synced; _isLoadingTemplates = false; }); _updateCachedTemplate(synced); }
      } catch (_) { if (mounted) setState(() => _isLoadingTemplates = false); }
    }
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
          cameras.first, 
          ResolutionPreset.max, // FIX: Changed from 'low' to 'max' for sharp focus
          enableAudio: false,
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
              ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
        );
        await _controller!.initialize();
        await _applyCenterFocus();
        _startTorchAutoToggle();
        _startFocusLoop();
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

  void _startFocusLoop() {
    _focusTimer?.cancel();
    _focusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!mounted || _controller == null || !_controller!.value.isInitialized || _isCapturing) return;
      await _applyCenterFocus();
    });
  }

  Future<void> _applyCenterFocus() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      await _controller!.setFocusPoint(const Offset(0.5, 0.5));
      await _controller!.setExposurePoint(const Offset(0.5, 0.5));
    } catch (_) {}
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
    if (_isCapturing || _isFrameProcessing) return;

    _isFrameProcessing = true;
    try {
      final shouldCheckQr = _frameCount - _lastQrCheckFrame >= 18;
      if (shouldCheckQr) {
        _lastQrCheckFrame = _frameCount;
        final qr = await OmrImaging.decodeQRFromFrame(frame);
        if (qr != null && qr.isNotEmpty) {
          final parts = qr.split('|');
          if (parts.isNotEmpty) {
            final assessmentId = parts[0].trim();

            if (_selectedTemplate?.assessmentId != assessmentId) {
              final match = _templates.where((t) => t.assessmentId == assessmentId);
              if (match.isNotEmpty) {
                _onTemplateSelected(match.first);
                if (mounted) setState(() => _assessmentIdentified = true);
              } else {
                _identifyNewAssessment(assessmentId);
              }
            } else if (!_assessmentIdentified && mounted) {
              setState(() => _assessmentIdentified = true);
            }
          }
        }
      }

      if (_selectedTemplate == null) return;

      if (_frameCount - _lastDiagnosticsFrame >= 36) {
        _lastDiagnosticsFrame = _frameCount;
        final diag = OmrImaging.runDiagnostics(frame, lockedCorners: _fiducialLock.corners.where((c) => c.detected).length);
        if (mounted) setState(() => _diagnostics = diag);
      }

      final det = OmrImaging.detectFiducialsFast(frame, scaleDown: 4, roi: _roi);

      final newLock = _fiducialLock.update(
        tl: det.tl, tr: det.tr, bl: det.bl, br: det.br,
        tlPos: det.tlx != null && det.tly != null ? Offset(det.tlx!, det.tly!) : null,
        trPos: det.trx != null && det.tryv != null ? Offset(det.trx!, det.tryv!) : null,
        blPos: det.blx != null && det.bly != null ? Offset(det.blx!, det.bly!) : null,
        brPos: det.brx != null && det.bry != null ? Offset(det.brx!, det.bry!) : null,
        lockThresholdFrames: _lockThresholdFrames,
      );

      _fiducialLock = newLock;

      final shouldRefreshOverlay = _frameCount - _lastOverlayFrame >= 12 || _fiducialLock.allLocked != newLock.allLocked;
      if (shouldRefreshOverlay) {
        _lastOverlayFrame = _frameCount;
        if (mounted) setState(() {});
      }
    } finally {
      _isFrameProcessing = false;
    }
  }

 bool get _readyToCapture =>
      _fiducialLock.allLocked && _assessmentIdentified && !_isCapturing;

  Future<void> _manualCapture() async {
    if (_isCapturing) return;
    if (_controller == null || !_controller!.value.isInitialized) return;
    _isCapturing = true;
    try {
      HapticFeedback.mediumImpact();
      await _stopImageStream();
      await _applyCenterFocus();
      _showScanFeedback('Scanning in progress…');
      final image = await _controller!.takePicture();
      _processScanInBackground(image.path);
      await _startImageStream();
      // Re-apply torch after capture (takePicture kills flash on Android)
      _syncTorch();
    } catch (e) {
      debugPrint("Capture error: $e");
      _isCapturing = false;
      if (mounted) _showScanFeedback('Scan failed. Please try again.', isSuccess: false, long: true);
    }
  }

  Future<void> _processScanInBackground(String imagePath) async {
    try {
      final template = _selectedTemplate;
      if (template == null) {
        _isCapturing = false;
        return;
      }

      // Primary: Python OpenCV OMR service. Falls back to on-device if unreachable.
      final omrService = OmrService();
      final result = await omrService.scanImage(imagePath, template);
      final finalStudentId = result.studentIdentifier ?? 'Unknown';

      // Check for duplicate scan (same student + same assessment)
      final allRecords = await ScanHistory.getAll();
      final duplicate = allRecords.where(
        (r) => r.studentIdentifier == finalStudentId && r.templateId == template.templateId,
      );
      if (duplicate.isNotEmpty && mounted) {
        _isCapturing = false;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Already Recorded', style: TextStyle(fontWeight: FontWeight.bold)),
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
                child: const Text('Rescan', style: TextStyle(color: primaryRed, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        // Remove the old duplicate record
        for (final old in duplicate) {
          await ScanHistory.removeRecord(old.id);
          if (mounted) {
            setState(() { _scanRecords.removeWhere((r) => r.id == old.id); });
          }
        }
        _isCapturing = true;
      }

      final record = ScanRecord(
        id: 'scan_${DateTime.now().millisecondsSinceEpoch}',
        templateId: template.templateId,
        templateName: template.name,
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

      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);

      if (mounted) {
        setState(() { 
          _scanRecords.insert(0, record); 
          _isCapturing = false; 
        });
        
        // FIX: Trigger the strict pop-up instead of a fast snackbar
        _showScoreDialog(
          finalStudentId, 
          result.scoreRaw, 
          result.maxScore.toDouble(), 
          result.scorePercent
        );
      }
      
      _attemptBackgroundUpload(record);

    // FIX: The missing catch block is restored here!
    } catch (e) {
      debugPrint("OMR processing error: $e");
      if (mounted) {
        setState(() => _isCapturing = false);
        _showScoreFlash('Scan error');
        _showScanFeedback('Scan failed. Please try again.', isSuccess: false, long: true);
      }
    }
  }

  void _showScanFeedback(String message, {bool isSuccess = true, bool long = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isSuccess ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
        duration: Duration(seconds: long ? 3 : 2),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  void _showScoreFlash(String text) {
    if (!mounted) return;
    setState(() => _scoreFlashText = text);
    _scoreFlashController?.forward(from: 0.0);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _scoreFlashText = null);
    });
  }

  Future<void> _attemptBackgroundUpload(ScanRecord record) async {
    try {
      final scan = await _repository.uploadGradedScan(
        templateId: record.templateId,
        imagePath: record.imagePath!,
        studentId: record.studentIdentifier,
        responses: record.responses,
      );
      
      await ScanHistory.updateRecord(record.id, {'server_scan_id': scan.scanId});
      
      if (mounted) {
        setState(() {
          final idx = _scanRecords.indexWhere((r) => r.id == record.id);
          if (idx >= 0) { 
            _scanRecords[idx] = _scanRecords[idx].copyWith(serverScanId: scan.scanId); 
          }
        });
        // Success feedback
        _showScanFeedback('Scan successfully synced to the system.');
      }
    } catch (e) {
      if (mounted) {
        // Let the user know the scan is safe locally, but the system sync failed
        _showScanFeedback('Saved locally. Network error prevented system sync.', isSuccess: false, long: true);
      }
    }
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

  Future<void> _identifyNewAssessment(String assessmentId) async {
    try {
      final template = await _repository.fetchTemplateByAssessment(assessmentId);
      if (mounted) {
        setState(() {
          // Add to local list if not there
          if (!_templates.any((t) => t.templateId == template.templateId)) {
            _templates.add(template);
          }
          _onTemplateSelected(template);
          _assessmentIdentified = true;
        });
      }
    } catch (e) {
      debugPrint("Failed to identify assessment via QR: $e");
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
    setState(() { _detailRecord = record; _mode = _ScreenMode.detail; });
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
    for (final entry in key.entries) {
      if (updatedResponses[entry.key] == entry.value) correct++;
    }
    final pct = key.isNotEmpty ? (correct / key.length) * 100.0 : 0.0;
    final updated = record.copyWith(
      responses: updatedResponses,
      scorePercent: pct,
      scoreRaw: correct.toDouble(),
      maxScore: key.length.toDouble(),
      isFlagged: false,
      flagReason: null,
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
    await ScanHistory.removeRecord(record.id);
    setState(() {
      _scanRecords.removeWhere((r) => r.id == record.id);
      _detailRecord = null;
      _mode = _ScreenMode.scanning;
    });
    _startImageStream();
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

    if (_templates.isEmpty || _selectedTemplate == null) {
      return TemplateSelectionView(
        templates: _templates,
        selectedTemplate: _selectedTemplate,
        isLoading: _isLoadingTemplates,
        isLoadingDetail: false,
        error: _templatesError,
        courseName: widget.preSelectedCourseName,
        onTemplateSelected: _onTemplateSelected,
        onRetry: _loadTemplates,
        onRefresh: _loadTemplates,
        onStartScan: () { if (_selectedTemplate != null) _setupCamera(); },
        onBack: () => Navigator.pop(context),
        primaryRed: primaryRed,
        darkText: darkText,
        grayText: grayText,
        borderColor: borderColor,
        bgGrey: bgGrey,
      );
    }

    if (_mode == _ScreenMode.detail && _detailRecord != null) {
      return PaperDetailView(
        record: _detailRecord!,
        template: _selectedTemplate,
        onBack: _closePaperDetail,
        onEditAnswers: () => _editAnswers(_detailRecord!),
        onReScan: () => _reScanPaper(_detailRecord!),
        onUpload: () => _uploadRecord(_detailRecord!),
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

    return LiveScanningView(
      controller: _controller,
      isReady: _isCameraReady,
      templateName: _selectedTemplate!.name,
      assessmentIdentified: _assessmentIdentified,
      fiducialLock: _fiducialLock,
      diagnostics: _diagnostics,
      scoreFlashText: _scoreFlashText,
      scoreFlashAnimation: _scoreFlashAnimation,
      readyToCapture: _readyToCapture,
      onCapture: _manualCapture,
      onFocusRequest: (point) async {
        if (_controller == null || !_controller!.value.isInitialized) return;
        await _controller!.setFocusPoint(point);
        await _controller!.setExposurePoint(point);
      },
      onBack: () => Navigator.pop(context),
      onReviewPapers: _openReview,
    );
  }
}
