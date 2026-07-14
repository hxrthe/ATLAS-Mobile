import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // Replaced camera with mobile_scanner
import 'package:image_picker/image_picker.dart';
import '../../repositories/grading_repository.dart';
import '../grading/services/local_omr_engine.dart';

class ScannerScreen extends StatefulWidget {
  // We ONLY need the accessToken now! The templateId is auto-detected.
  final String accessToken;

  const ScannerScreen({
    super.key,
    required this.accessToken,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // Setup the Mobile Scanner Controller
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    returnImage: true, // This allows us to grab the image frame when the QR is detected
  );

  final GradingRepository _gradingRepo = GradingRepository();
  final ImagePicker _picker = ImagePicker();

  bool _isFlashOn = false;
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    setState(() => _isFlashOn = !_isFlashOn);
    await _scannerController.toggleTorch();
  }

  // Unified upload function that now takes the auto-detected template ID
  Future<void> _processImage(String imagePath, String detectedTemplateId) async {
    setState(() => _isProcessing = true);

    bool success = false;
    String? scoreFeedback;

    try {
      final imageFile = File(imagePath);

      // Execute the upload using the dynamically scanned Template ID
      final result = await _gradingRepo.uploadExamScan(
        templateId: detectedTemplateId,
        imageFile: imageFile,
        accessToken: widget.accessToken,
      );

      success = true;
      scoreFeedback = 'Scored: ${result.scorePercent}%';

    } catch (e) {
      debugPrint("Scan Upload Error: $e");
      success = false;
    }

    if (mounted) {
      setState(() => _isProcessing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Theme.of(context).colorScheme.surfaceContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  success
                      ? 'Upload successful! $scoreFeedback'
                      : 'Upload failed. Try again.',
                ),
              ),
            ],
          ),
          backgroundColor: success ? const Color(0xFF198754) : const Color(0xFF8B1515),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );

      // Start the scanner back up for the next paper!
      _scannerController.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryRed = const Color(0xFF8B1515);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      body: Stack(
        children: [
          // 1. LIVE MOBILE SCANNER FEED
          Positioned.fill(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: (BarcodeCapture capture) async {
                if (_isProcessing) return;

                final List<Barcode> barcodes = capture.barcodes;

                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    final detectedTemplateId = barcode.rawValue!;

                    setState(() => _isProcessing = true);
                    _scannerController.stop();

                    try {
                      // 1. Fetch the Template Blueprint (Cache this later for true offline support)
                      final blueprint = await _gradingRepo.fetchTemplateBlueprint(
                        detectedTemplateId,
                        widget.accessToken,
                      );

                      // 2. Extract Answers using the Local Engine
                      File tempImageFile = File('path_to_temp_file'); // Placeholder
                      final extractedResponses = await LocalOmrEngine.extractResponsesFromImage(
                        tempImageFile,
                        blueprint.layoutMetadata,
                      );

                      // 3. Grade Instantly
                      final gradeResult = LocalOmrEngine.gradeSheet(
                        responses: extractedResponses,
                        answerKey: blueprint.answerKey,
                      );

                      // 4. Show Instant Feedback to Faculty
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Graded! Score: ${gradeResult['score_percent']}%'),
                          backgroundColor: const Color(0xFF198754),
                        ),
                      );

                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFF8B1515)),
                      );
                    } finally {
                      setState(() => _isProcessing = false);

                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) _scannerController.start();
                      });
                    }
                    break;
                  }
                }
              }, // <--- Closes onDetect
            ), // <--- MISSING: Closes MobileScanner
          ), // <--- MISSING: Closes Positioned.fill

          // 2. EXAM FRAMING GUIDE
          SafeArea(
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.65,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.4), width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          // 3. TOP HEADER
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.only(top: 60, bottom: 16, left: 16, right: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
                    border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.1))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).colorScheme.surfaceContainer), onPressed: () => Navigator.pop(context)),
                      Text('Auto-Scanner', style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: _isFlashOn ? const Color(0xFFD4811B) : Colors.white),
                        onPressed: _toggleFlash,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 4. BOTTOM CONTROLS (Updated for Auto-Scan)
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.only(bottom: 40, top: 24, left: 24, right: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                    border: Border(top: BorderSide(color: Theme.of(context).colorScheme.surfaceContainer.withOpacity(0.1))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.qr_code_scanner, color: Theme.of(context).colorScheme.surfaceContainer, size: 32),
                          const SizedBox(height: 8),
                          Text('Point at the Assessment QR to auto-scan', style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),


          // 5. PROCESSING OVERLAY
          if (_isProcessing)
            Positioned.fill(
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: primaryRed),
                          const SizedBox(height: 16),
                          Text('Grading Sheet...', style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}