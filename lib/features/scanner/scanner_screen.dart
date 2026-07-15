import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../grading/grading_repository.dart';
import '../grading/models.dart';
import 'omr_engine.dart';
import 'omr_models.dart';
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

enum ScannerStep { selectTemplate, capture, processing, result }

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;

  final GradingRepository _repository = GradingRepository();

  List<BubbleTemplate> _templates = [];
  BubbleTemplate? _selectedTemplate;
  bool _isLoadingTemplates = false;
  String? _templatesError;

  ScannerStep _step = ScannerStep.selectTemplate;
  bool _isUploading = false;
  bool _isProcessingLocally = false;
  String? _processingStage;

  // Local OMR results
  BubbleScan? _scanResult;
  OmrResult? _omrResult;
  String? _resultError;
  String? _capturedImagePath;

  final Color primaryRed = const Color(0xFF8B1515);
  final Color goldBorder = const Color(0xFFE5C07B);
  final Color darkText = const Color(0xFF1E232C);
  final Color grayText = const Color(0xFF8391A1);
  final Color borderColor = const Color(0xFFE8ECF4);
  final Color bgGrey = const Color(0xFFF4F6F9);

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoadingTemplates = true;
      _templatesError = null;
    });

    try {
      // Try cache first for instant display
      final cached = await TemplateCache.load();
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _templates = cached;
          _isLoadingTemplates = false;
        });
        if (_templates.length == 1) _selectedTemplate = _templates.first;
        // Refresh from network in background
        _refreshTemplatesFromNetwork();
        return;
      }

      // No cache: fetch from network
      await _fetchFromNetwork();
    } catch (e) {
      setState(() {
        _isLoadingTemplates = false;
        _templatesError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _refreshTemplatesFromNetwork() async {
    try {
      await _fetchFromNetwork();
    } catch (_) {
      // Keep cached data on network failure
    }
  }

  Future<void> _fetchFromNetwork() async {
    if (widget.preSelectedCourseId != null) {
      final templates =
          await _repository.fetchTemplates(widget.preSelectedCourseId!);
      await TemplateCache.store(templates);
      if (mounted) {
        setState(() {
          _templates = templates;
          _isLoadingTemplates = false;
        });
        if (_templates.length == 1) _selectedTemplate = _templates.first;
      }
    } else {
      final courses = await _repository.fetchFacultyCourses();
      if (courses.isNotEmpty) {
        final templates =
            await _repository.fetchTemplates(courses.first['course_id']!);
        await TemplateCache.store(templates);
        if (mounted) {
          setState(() {
            _templates = templates;
            _isLoadingTemplates = false;
          });
          if (_templates.length == 1) _selectedTemplate = _templates.first;
        }
      } else {
        setState(() {
          _templates = [];
          _isLoadingTemplates = false;
          _templatesError = 'No courses found in your teaching load.';
        });
      }
    }
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (mounted) setState(() => _isCameraReady = true);
      }
    } catch (e) {
      debugPrint("Camera init error: $e");
    }
  }

  bool _isLoadingDetail = false;

  // ...

  Future<void> _onTemplateSelected(BubbleTemplate t) async {
    setState(() {
      _selectedTemplate = t;
      _templatesError = null;
    });

    // Preload answer_key + layout_metadata immediately on selection
    if (t.answerKey.isEmpty && t.hasAnswerKey) {
      setState(() => _isLoadingDetail = true);
      try {
        final detail = await _repository.fetchTemplateDetail(t.templateId);
        if (mounted) {
          setState(() {
            _selectedTemplate = detail;
            _isLoadingDetail = false;
          });
          _updateCachedTemplate(detail);
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingDetail = false);
      }
    } else if (t.answerKey.isEmpty && t.assessmentId != null) {
      setState(() => _isLoadingDetail = true);
      try {
        final synced = await _repository.syncKeyFromAssessment(t.templateId);
        if (mounted) {
          setState(() {
            _selectedTemplate = synced;
            _isLoadingDetail = false;
          });
          _updateCachedTemplate(synced);
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingDetail = false);
      }
    }
  }

  void _updateCachedTemplate(BubbleTemplate updated) {
    final all = List<BubbleTemplate>.from(_templates);
    final idx = all.indexWhere((t) => t.templateId == updated.templateId);
    if (idx >= 0) all[idx] = updated;
    _templates = all;
    TemplateCache.store(all);
  }

  void _startCapture() async {
    if (_selectedTemplate == null) return;
    setState(() => _step = ScannerStep.capture);
    _setupCamera();
  }

  Future<void> _onCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_selectedTemplate == null) return;

    try {
      setState(() {
        _step = ScannerStep.processing;
        _isProcessingLocally = true;
        _processingStage = 'Capturing image…';
      });

      final image = await _controller!.takePicture();
      _capturedImagePath = image.path;

      setState(() => _processingStage = 'Scanning QR code…');
      final result = await OmrEngine.processScan(image.path, _selectedTemplate!);

      if (!mounted) return;

      // Build a BubbleScan-like result for the UI
      final scan = BubbleScan(
        scanId: '',
        templateId: _selectedTemplate!.templateId,
        studentIdentifier: result.studentIdentifier ?? 'Unknown',
        responses: result.responses,
        scoreRaw: result.scoreRaw,
        scorePercent: result.scorePercent,
        maxScore: result.maxScore.toDouble(),
        isFlagged: result.isFlagged,
        flagReason: result.flagReason,
        createdAt: DateTime.now().toIso8601String(),
      );

      setState(() {
        _isProcessingLocally = false;
        _omrResult = result;
        _scanResult = scan;
        _resultError = null;
        _step = ScannerStep.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessingLocally = false;
        _resultError = e.toString().replaceAll('Exception: ', '');
        _step = ScannerStep.result;
      });
    }
  }

  Future<void> _uploadToServer() async {
    if (_omrResult == null || _capturedImagePath == null || _selectedTemplate == null) return;

    setState(() => _isUploading = true);
    try {
      final scan = await _repository.uploadGradedScan(
        templateId: _selectedTemplate!.templateId,
        imagePath: _capturedImagePath!,
        studentId: _omrResult!.studentIdentifier,
        responses: _omrResult!.responses,
      );
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _scanResult = scan;
        _resultError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _resultError = 'Upload failed: ${e.toString().replaceAll('Exception: ', '')}';
      });
    }
  }

  void _reset() {
    setState(() {
      _step = ScannerStep.selectTemplate;
      _scanResult = null;
      _omrResult = null;
      _resultError = null;
      _capturedImagePath = null;
      _isUploading = false;
      _isCameraReady = false;
      _controller?.dispose();
      _controller = null;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case ScannerStep.selectTemplate:
        return TemplateSelectionView(
          templates: _templates,
          selectedTemplate: _selectedTemplate,
          isLoading: _isLoadingTemplates,
          isLoadingDetail: _isLoadingDetail,
          error: _templatesError,
          courseName: widget.preSelectedCourseName,
          onTemplateSelected: _onTemplateSelected,
          onRetry: _loadTemplates,
          onRefresh: _loadTemplates,
          onStartScan: _startCapture,
          onBack: () => Navigator.pop(context),
          primaryRed: primaryRed,
          darkText: darkText,
          grayText: grayText,
          borderColor: borderColor,
          bgGrey: bgGrey,
        );
      case ScannerStep.capture:
        return CaptureView(
          controller: _controller,
          isReady: _isCameraReady,
          templateName: _selectedTemplate?.name ?? '',
          onBack: () {
            _controller?.dispose();
            _controller = null;
            setState(() {
              _isCameraReady = false;
              _step = ScannerStep.selectTemplate;
            });
          },
          onCapture: _onCapture,
          primaryRed: primaryRed,
          goldBorder: goldBorder,
        );
      case ScannerStep.processing:
        return ProcessingView(
          isUploading: _isUploading,
          isProcessingLocally: _isProcessingLocally,
          stage: _processingStage,
          darkText: darkText,
          grayText: grayText,
          bgGrey: bgGrey,
          primaryRed: primaryRed,
        );
      case ScannerStep.result:
        return ResultView(
          scan: _scanResult,
          error: _resultError,
          selectedTemplate: _selectedTemplate,
          isUploading: _isUploading,
          omrResult: _omrResult,
          onScanAnother: _reset,
          onDone: () => Navigator.pop(context),
          onUpload: _uploadToServer,
          primaryRed: primaryRed,
          darkText: darkText,
          grayText: grayText,
          bgGrey: bgGrey,
        );
    }
  }
}
