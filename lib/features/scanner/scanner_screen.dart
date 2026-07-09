import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      // Fetch available hardware cameras
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        // Initialize the first available camera (usually the rear camera)
        _controller = CameraController(
          _cameras!.first,
          ResolutionPreset.high,
          enableAudio: false, // Audio not needed for scanning documents
        );

        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isReady = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading spinner while the hardware boots up
    if (!_isReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF8B1515)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full Screen Live Camera Feed
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: CameraPreview(_controller!),
          ),

          // 2. UI Overlay (Targeting Box & Buttons)
          SafeArea(
            child: Column(
              children: [
                // Top Toolbar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Align Exam Sheet',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(width: 48), // Invisible spacer to center the text
                    ],
                  ),
                ),

                // Alignment Box Outline
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5C07B), width: 3.0),
                      borderRadius: BorderRadius.circular(12.0),
                      // Adds a subtle dark tint outside the box (optional)
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          spreadRadius: 10000,
                        ),
                      ],
                    ),
                  ),
                ),

                // Capture Button
                Padding(
                  padding: const EdgeInsets.only(bottom: 32.0),
                  child: FloatingActionButton.large(
                    backgroundColor: const Color(0xFF8B1515),
                    onPressed: () {
                      // TODO: Capture image and process via ML Kit
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Capturing sheet for analysis...')),
                      );
                    },
                    child: const Icon(Icons.camera, color: Colors.white, size: 36),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}