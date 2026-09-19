import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../grading/models.dart';
import 'omr_constants.dart';
import 'omr_models.dart';

const Color primaryRed = Color(0xFF8B1515);
const Color darkText = Color(0xFF1E232C);
const Color grayText = Color(0xFF8391A1);
const Color borderColor = Color(0xFFE8ECF4);
const Color bgGrey = Color(0xFFF4F6F9);

// ═══════════════════════════════════════════════════════════════════════════
// LiveScanningView — continuous camera with real-time fiducial overlay
// ═══════════════════════════════════════════════════════════════════════════

class LiveScanningView extends StatelessWidget {
  final CameraController? controller;
  final bool isReady;
  final String? templateName;
  final bool assessmentIdentified;
  final String? identifyHint;
  final FiducialLockState fiducialLock;
  final ScannerDiagnostics diagnostics;
  final String? scoreFlashText;
  final Animation<double>? scoreFlashAnimation;
  final bool readyToCapture;
  final Uint8List? alignedPreviewBytes;
  final bool torchOn;
  final VoidCallback? onToggleTorch;
  final VoidCallback? onCapture;
  final VoidCallback onBack;
  final VoidCallback onReviewPapers;

  const LiveScanningView({
    super.key,
    required this.controller,
    required this.isReady,
    this.templateName,
    this.assessmentIdentified = false,
    this.identifyHint,
    required this.fiducialLock,
    required this.diagnostics,
    this.scoreFlashText,
    this.scoreFlashAnimation,
    this.readyToCapture = false,
    this.alignedPreviewBytes,
    this.torchOn = false,
    this.onToggleTorch,
    this.onCapture,
    required this.onBack,
    required this.onReviewPapers,
  });

  @override
  Widget build(BuildContext context) {
    if (!isReady || controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: primaryRed)),
      );
    }

    final topTitle = assessmentIdentified && templateName != null
        ? templateName!
        : (identifyHint ?? 'Point camera at Assessment QR');

    // Letterbox the preview to the camera's portrait aspect ratio.
    // Filling the phone screen stretches the feed (bubbles → ovals).
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cam = controller!;
                  // previewSize is landscape (w>h); portrait display = 1/aspectRatio
                  final displayAspect = cam.value.aspectRatio > 0
                      ? 1.0 / cam.value.aspectRatio
                      : 9.0 / 16.0;

                  var previewW = constraints.maxWidth;
                  var previewH = previewW / displayAspect;
                  if (previewH > constraints.maxHeight) {
                    previewH = constraints.maxHeight;
                    previewW = previewH * displayAspect;
                  }

                  return Center(
                    child: SizedBox(
                      width: previewW,
                      height: previewH,
                      child: CameraPreview(
                        cam,
                        child: _FiducialOverlay(
                          lockState: fiducialLock,
                          readyToCapture: readyToCapture,
                          assessmentIdentified: assessmentIdentified,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: _TopBar(
              templateName: topTitle,
              onBack: onBack,
              onReview: onReviewPapers,
            ),
          ),
          // Live bird's-eye sheet (aligned) — shown once fiducials lock.
          if (alignedPreviewBytes != null && fiducialLock.allLocked)
            Positioned(
              right: 12,
              top: 100,
              child: _AlignedPreviewPip(bytes: alignedPreviewBytes!),
            ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _DiagnosticBar(diagnostics: diagnostics),
          ),
          if (scoreFlashText != null && scoreFlashAnimation != null)
            Positioned(
              bottom: 120, left: 0, right: 0,
              child: _ScoreFlash(text: scoreFlashText!, animation: scoreFlashAnimation!),
            ),
          Positioned(
            bottom: 48, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TorchToggleButton(
                  isOn: torchOn,
                  onTap: onToggleTorch,
                ),
                const SizedBox(width: 28),
                _ShutterButton(
                  ready: readyToCapture,
                  onTap: onCapture,
                ),
                // Balance the row so the shutter stays visually centered.
                const SizedBox(width: 28 + 52),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live aligned (bird's-eye) preview pip ─────────────────────────────────

class _AlignedPreviewPip extends StatelessWidget {
  final Uint8List bytes;
  const _AlignedPreviewPip({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.greenAccent, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'ALIGNED',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Image.memory(
            bytes,
            width: 96,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
          ),
        ],
      ),
    );
  }
}

// ── Fiducial bracket overlay ─────────────────────────────────────────────

class _FiducialOverlay extends StatelessWidget {
  final FiducialLockState lockState;
  final bool readyToCapture;
  final bool assessmentIdentified;
  const _FiducialOverlay({
    required this.lockState,
    this.readyToCapture = false,
    this.assessmentIdentified = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _FiducialPainter(
          lockState: lockState,
          readyToCapture: readyToCapture,
          assessmentIdentified: assessmentIdentified,
        ),
      ),
    );
  }
}

class _FiducialPainter extends CustomPainter {
  final FiducialLockState lockState;
  final bool readyToCapture;
  final bool assessmentIdentified;
  _FiducialPainter({
    required this.lockState,
    this.readyToCapture = false,
    this.assessmentIdentified = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Paper clear zone (long bond 8.5" × 13") — fills most of the preview.
    const topMargin = 24.0;
    const bottomMargin = 24.0;
    const paperAspectRatio = 13.0 / 8.5; // height / width
    const pageWmm = 215.9;
    const pageHmm = 330.2;
    // Printed ArUco fiducials (bubble_sheet_generator.py) — NOT at paper corners.
    const fidInset = 5.0;
    const fidW = 15.0;
    const headerMm = 50.8; // 2" — top fiducials start here
    const contentBotMm = 289.8; // bottom fiducial top edge

    final availableHeight = size.height - topMargin - bottomMargin;
    var clearWidth = size.width * 0.94;
    var clearHeight = clearWidth * paperAspectRatio;
    if (clearHeight > availableHeight) {
      clearHeight = availableHeight;
      clearWidth = clearHeight / paperAspectRatio;
    }

    final centerY = topMargin + availableHeight / 2;
    final clearRect = Rect.fromCenter(
      center: Offset(size.width / 2, centerY),
      width: clearWidth,
      height: clearHeight,
    );

    // Dim outside the paper guide only
    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;
    final hole = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(clearRect, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(hole, dimPaint);

    // Paper outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(clearRect, const Radius.circular(8)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    Offset fidTopLeft(double xMm, double yMm) => Offset(
          clearRect.left + (xMm / pageWmm) * clearRect.width,
          clearRect.top + (yMm / pageHmm) * clearRect.height,
        );

    final fidPx = (fidW / pageWmm) * clearRect.width;
    // Expected guide positions (ghost) — printed fiducial mm on long-bond sheet.
    final expectedFidRects = [
      Rect.fromLTWH(
        fidTopLeft(fidInset, headerMm).dx,
        fidTopLeft(fidInset, headerMm).dy,
        fidPx,
        fidPx,
      ),
      Rect.fromLTWH(
        fidTopLeft(pageWmm - fidInset - fidW, headerMm).dx,
        fidTopLeft(pageWmm - fidInset - fidW, headerMm).dy,
        fidPx,
        fidPx,
      ),
      Rect.fromLTWH(
        fidTopLeft(fidInset, contentBotMm).dx,
        fidTopLeft(fidInset, contentBotMm).dy,
        fidPx,
        fidPx,
      ),
      Rect.fromLTWH(
        fidTopLeft(pageWmm - fidInset - fidW, contentBotMm).dx,
        fidTopLeft(pageWmm - fidInset - fidW, contentBotMm).dy,
        fidPx,
        fidPx,
      ),
    ];

    final corners = lockState.corners;
    final detectedCount = corners.where((c) => c.detected && c.position != null).length;
    final allDetected = detectedCount == 4;

    // Ghost guides (where fiducials should be when paper fills the frame)
    if (!allDetected) {
      final ghost = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final r in expectedFidRects) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(3), const Radius.circular(4)),
          ghost,
        );
      }
    }

    // Tracking boxes ride the live ArUco centres (scale with the sheet).
    final liveCenters = <int, Offset>{};
    for (var i = 0; i < 4; i++) {
      final pos = corners[i].position;
      if (pos == null) continue;
      if (corners[i].detected || corners[i].locked || corners[i].fresh) {
        liveCenters[i] = Offset(
          pos.dx.clamp(0.0, 1.0) * size.width,
          pos.dy.clamp(0.0, 1.0) * size.height,
        );
      }
    }
    double liveBox = fidPx.clamp(20.0, 48.0);
    if (liveCenters[0] != null && liveCenters[1] != null) {
      final span = (liveCenters[0]! - liveCenters[1]!).distance;
      liveBox = (span * 15.0 / 190.9).clamp(18.0, 56.0);
    }

    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      final Offset center;
      final Color color;
      final tracked = liveCenters.containsKey(i);

      if (tracked) {
        center = liveCenters[i]!;
        color = c.locked || c.fresh
            ? const Color(0xFF00E676)
            : Colors.white;
      } else {
        center = expectedFidRects[i].center;
        color = Colors.white.withValues(alpha: 0.35);
      }

      final rect =
          Rect.fromCenter(center: center, width: liveBox + 8, height: liveBox + 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = tracked ? 3.5 : 2.0,
      );
      if (tracked) {
        canvas.drawCircle(center, 3.5, Paint()..color = color);
      }
    }

    // Sheet quadrilateral when all 4 are found
    if (allDetected) {
      Offset ui(int i) => Offset(
            corners[i].position!.dx * size.width,
            corners[i].position!.dy * size.height,
          );
      final path = Path()
        ..moveTo(ui(0).dx, ui(0).dy)
        ..lineTo(ui(1).dx, ui(1).dy)
        ..lineTo(ui(3).dx, ui(3).dy)
        ..lineTo(ui(2).dx, ui(2).dy)
        ..close();

      final outlineColor = lockState.allLocked ? Colors.greenAccent : Colors.orange;
      canvas.drawPath(
        path,
        Paint()
          ..color = outlineColor.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = outlineColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // Center status text
    final String msg;
    final Color msgColor;
    if (readyToCapture) {
      msg = 'Hold still \u2014 capturing';
      msgColor = Colors.greenAccent;
    } else if (lockState.allLocked && assessmentIdentified) {
      msg = 'Markers locked \u2014 hold still';
      msgColor = Colors.greenAccent;
    } else if (lockState.allLocked) {
      msg = 'Sheet locked \u2014 scan Assessment QR';
      msgColor = Colors.greenAccent;
    } else if (detectedCount >= 2) {
      msg = 'Tracking corner markers ($detectedCount/4)';
      msgColor = Colors.orange;
    } else {
      msg = 'Fit entire sheet in frame';
      msgColor = Colors.white70;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: msg,
        style: TextStyle(
          color: msgColor,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(blurRadius: 8, color: Colors.black87)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.9);
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, size.height * 0.48),
    );
  }

  @override
  bool shouldRepaint(covariant _FiducialPainter o) =>
      lockState != o.lockState ||
      readyToCapture != o.readyToCapture ||
      assessmentIdentified != o.assessmentIdentified;
}

// ── Top bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String templateName;
  final VoidCallback onBack;
  final VoidCallback onReview;
  const _TopBar({required this.templateName, required this.onBack, required this.onReview});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 8, right: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.75), Colors.black.withValues(alpha: 0.0)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
              onPressed: onBack, padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(templateName,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              height: 36,
              child: TextButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.assignment, color: Colors.white, size: 16),
                label: const Text('Review Papers',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Diagnostic status bar ─────────────────────────────────────────────────

class _DiagnosticBar extends StatelessWidget {
  final ScannerDiagnostics diagnostics;
  const _DiagnosticBar({required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    if (diagnostics.message.isEmpty) return const SizedBox.shrink();

    // User requirement: Styling as a contextual orange/alert bar
    final bgColor = const Color(0xFFFB8C00); // Material Orange 600

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: bgColor,
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                diagnostics.message,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            if (diagnostics.isBlurry)
              const Text('Pull back', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
            if (diagnostics.hasGlare)
              const Text('Tilt paper', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Score flash overlay ───────────────────────────────────────────────────

class _ScoreFlash extends StatelessWidget {
  final String text;
  final Animation<double> animation;
  const _ScoreFlash({required this.text, required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        final opacity = v < 0.15
            ? (v / 0.15) : v > 0.70 ? (1.0 - (v - 0.70) / 0.30).clamp(0.0, 1.0) : 1.0;
        return Opacity(
          opacity: opacity,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 80),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: primaryRed.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Text(text, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
          ),
        );
      },
    );
  }
}

// ── Torch toggle (live scanning only) ─────────────────────────────────────

class _TorchToggleButton extends StatelessWidget {
  final bool isOn;
  final VoidCallback? onTap;
  const _TorchToggleButton({required this.isOn, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOn
                ? Colors.amber.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.18),
            border: Border.all(
              color: isOn
                  ? Colors.amber.shade200
                  : Colors.white.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Icon(
            isOn ? Icons.flashlight_on : Icons.flashlight_off,
            color: isOn ? Colors.black87 : Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

// ── Shutter Button ───────────────────────────────────────────────────────

class _ShutterButton extends StatefulWidget {
  final bool ready;
  final VoidCallback? onTap;
  const _ShutterButton({required this.ready, this.onTap});

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;
  Animation<double>? _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulse!, curve: Curves.easeInOut),
    );
    _pulse!.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.ready || widget.onTap == null) return;
    HapticFeedback.mediumImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.ready;

    return AnimatedBuilder(
      animation: _pulseAnim!,
      builder: (context, _) {
        return GestureDetector(
          onTap: _handleTap,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: ready ? 1.0 : 0.35),
              boxShadow: ready
                  ? [
                      BoxShadow(
                        color: Colors.green.withValues(
                            alpha: 0.4 + 0.3 * _pulseAnim!.value),
                        blurRadius: 12 + 8 * _pulseAnim!.value,
                        spreadRadius: 2 + 2 * _pulseAnim!.value,
                      ),
                    ]
                  : [],
              border: Border.all(
                color: ready
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.4),
                width: 4,
              ),
            ),
            child: Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ReviewPapersView — list of recently scanned answer sheets
// ═══════════════════════════════════════════════════════════════════════════

class ReviewPapersView extends StatelessWidget {
  final List<ScanRecord> records;
  final bool isLoading;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final void Function(ScanRecord) onTapRecord;
  final void Function(ScanRecord) onReScan;
  final void Function(ScanRecord) onUpload;
  final void Function(ScanRecord) onDelete;

  const ReviewPapersView({
    super.key,
    required this.records,
    this.isLoading = false,
    this.error,
    required this.onBack,
    required this.onRefresh,
    required this.onTapRecord,
    required this.onReScan,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      appBar: AppBar(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        title: const Text('Review Papers', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh)],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (isLoading) return const Center(child: CircularProgressIndicator(color: primaryRed));
    if (error != null && records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: primaryRed),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: primaryRed, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    if (records.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: grayText),
            SizedBox(height: 12),
            Text('No papers scanned yet', style: TextStyle(color: grayText, fontSize: 15)),
            SizedBox(height: 4),
            Text('Return to scanner and start scanning', style: TextStyle(color: grayText, fontSize: 12)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final r = records[i];
          return Dismissible(
            key: ValueKey(r.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(ctx, r),
            onDismissed: (_) => onDelete(r),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
            ),
            child: _ScanRecordCard(
              record: r,
              onTap: () => onTapRecord(r),
              onReScan: () => onReScan(r),
              onUpload: () => onUpload(r),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, ScanRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Scan?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Delete the scan for ${record.studentIdentifier}?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: grayText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: primaryRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

class _ScanRecordCard extends StatelessWidget {
  final ScanRecord record;
  final VoidCallback onTap;
  final VoidCallback onReScan;
  final VoidCallback onUpload;
  const _ScanRecordCard({required this.record, required this.onTap, required this.onReScan, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final sp = record.scorePercent;
    final scoreStr = sp != null ? '${sp.toStringAsFixed(0)}%' : '\u2014';
    final isUploaded = record.serverScanId != null && record.serverScanId!.isNotEmpty;
    final scoreColor = sp != null && sp >= 60 ? Colors.green.shade700 : primaryRed;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: isUploaded ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isUploaded ? Icons.cloud_done : Icons.phone_android,
                  color: isUploaded ? Colors.green.shade700 : Colors.blue.shade700,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.studentIdentifier,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: darkText)),
                    const SizedBox(height: 2),
                    Text(
                      '${record.templateName} \u00b7 ${_formatTime(record.createdAt)}',
                      style: const TextStyle(fontSize: 11, color: grayText),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(scoreStr,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: scoreColor)),
                  if (record.isFlagged)
                    const Icon(Icons.flag, color: Colors.orange, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared OMR result helpers (scan result + review detail)
// ═══════════════════════════════════════════════════════════════════════════

bool _isAmbiguousResponse(String? resp) {
  final v = (resp ?? '').trim();
  if (v.isEmpty || v == '?') return true;
  final letters = v.replaceAll(RegExp(r'[^A-Za-z]'), '');
  return letters.length > 1;
}

String _displayResponse(String? resp) {
  final v = (resp ?? '').trim();
  if (v.isEmpty || v == '?') return '?';
  final letters = v
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z]'), '')
      .split('')
      .toSet()
      .toList()
    ..sort();
  if (letters.isEmpty) return '?';
  if (letters.length == 1) return letters.first;
  return letters.join(',');
}

String? _answerKeyForItem(Map<String, String> answerKey, String item) {
  final direct = answerKey[item];
  if (direct != null && direct.isNotEmpty) return direct.trim().toUpperCase();
  final n = int.tryParse(item);
  if (n == null) return null;
  final padded = n.toString().padLeft(2, '0');
  final alt = answerKey[padded] ?? answerKey[n.toString()];
  if (alt == null || alt.isEmpty) return null;
  return alt.trim().toUpperCase();
}

bool _responseMatchesKey(String? resp, String? expected) {
  if (resp == null || expected == null) return false;
  if (_isAmbiguousResponse(resp)) return false;
  return resp.trim().toUpperCase() == expected.trim().toUpperCase();
}

({int correct, int incorrect, int ambiguous, int max}) _scoreBreakdown({
  required Map<String, String> responses,
  required Map<String, String> answerKey,
  required int totalItems,
  List<int> flaggedItems = const [],
  int? storedCorrect,
  int? storedMax,
}) {
  final flagged = flaggedItems.toSet();
  final maxFromKey = answerKey.isNotEmpty
      ? answerKey.keys
          .map((k) => int.tryParse(k) ?? 0)
          .fold<int>(0, (a, b) => a > b ? a : b)
      : 0;
  final max = storedMax ??
      (maxFromKey > 0
          ? maxFromKey
          : (totalItems > 0 ? totalItems : responses.length));

  var correct = 0;
  var incorrect = 0;
  var ambiguous = 0;

  if (answerKey.isNotEmpty) {
    for (var i = 1; i <= max; i++) {
      final key = i.toString();
      final resp = responses[key] ?? responses[key.padLeft(2, '0')] ?? '?';
      final expected = _answerKeyForItem(answerKey, key);
      final amb = _isAmbiguousResponse(resp) || flagged.contains(i);
      if (amb) {
        ambiguous++;
      } else if (_responseMatchesKey(resp, expected)) {
        correct++;
      } else {
        incorrect++;
      }
    }
  } else {
    for (var i = 1; i <= max; i++) {
      final resp = responses[i.toString()] ?? '?';
      if (_isAmbiguousResponse(resp) || flagged.contains(i)) {
        ambiguous++;
      }
    }
    correct = storedCorrect ?? 0;
    incorrect = (max - correct - ambiguous).clamp(0, max);
  }

  // Prefer persisted scan grade when present (authoritative from OMR grade).
  if (storedCorrect != null && storedMax != null && storedMax > 0) {
    final amb = ambiguous;
    final c = storedCorrect.clamp(0, storedMax);
    final inc = (storedMax - c - amb).clamp(0, storedMax);
    return (correct: c, incorrect: inc, ambiguous: amb, max: storedMax);
  }

  return (
    correct: correct,
    incorrect: incorrect,
    ambiguous: ambiguous,
    max: max,
  );
}

void _showOmrFlaggedItemsSheet(
  BuildContext context, {
  required List<({int item, String reason})> items,
  VoidCallback? onEdit,
}) {
  final colors = context.atlas;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final c = ctx.atlas;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Flagged items (${items.length})',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Why each item was marked invalid',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                ),
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No invalid items',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            Divider(color: c.divider, height: 1),
                        itemBuilder: (_, i) {
                          final row = items[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.ambiguous.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${row.item}',
                                style: TextStyle(
                                  color: c.ambiguous,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            title: Text(
                              'Item ${row.item}',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              row.reason,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (onEdit != null) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onEdit();
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit Answers'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.primary,
                    foregroundColor: c.onPrimary,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Widget _omrTinyReviewFlaggedButton({
  required BuildContext context,
  required VoidCallback onPressed,
  required int count,
}) {
  if (count <= 0) return const SizedBox.shrink();
  final c = context.atlas;
  return Align(
    alignment: Alignment.centerRight,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: c.ambiguous,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: c.ambiguous.withValues(alpha: 0.7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: 13),
          SizedBox(width: 4),
          Text(
            'Review Flagged Items',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

Widget _omrScoreSummaryCard({
  required BuildContext context,
  required String studentId,
  required int correct,
  required int incorrect,
  required int ambiguous,
  required int max,
  required double pct,
  required Color scoreColor,
}) {
  final c = context.atlas;
  final progress = max > 0 ? (correct / max).clamp(0.0, 1.0) : 0.0;
  return Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: c.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.cardMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Student ID: $studentId',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Text(
              '$correct / $max',
              style: TextStyle(
                color: scoreColor,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _omrStatChip(
                label: '$correct Correct',
                bg: c.correct.withValues(alpha: 0.15),
                fg: c.correct,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _omrStatChip(
                label: '$incorrect Incorrect',
                bg: c.incorrect.withValues(alpha: 0.15),
                fg: c.incorrect,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _omrStatChip(
                label: '$ambiguous Invalid',
                bg: c.ambiguous.withValues(alpha: 0.15),
                fg: c.ambiguous,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'Score',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                color: scoreColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _omrStatChip({
  required String label,
  required Color bg,
  required Color fg,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

Widget _omrItemResponsesGrid({
  required BuildContext context,
  required Map<String, String> responses,
  required Map<String, String> answerKey,
  required int totalItems,
  List<int> flaggedItems = const [],
  VoidCallback? onTapItem,
}) {
  final c = context.atlas;
  final maxFromKey = answerKey.isNotEmpty
      ? answerKey.keys
          .map((k) => int.tryParse(k) ?? 0)
          .fold<int>(0, (a, b) => a > b ? a : b)
      : 0;
  final max = maxFromKey > 0
      ? maxFromKey
      : (totalItems > 0 ? totalItems : responses.length);
  final flagged = flaggedItems.toSet();
  final hasKey = answerKey.isNotEmpty;

  return Wrap(
    spacing: 6,
    runSpacing: 6,
    children: List.generate(max, (i) {
      final item = (i + 1).toString();
      final resp = responses[item] ?? responses[item.padLeft(2, '0')] ?? '?';
      final display = _displayResponse(resp);
      final expected = _answerKeyForItem(answerKey, item);
      final amb =
          _isAmbiguousResponse(resp) || flagged.contains(i + 1) || display == '?';
      final ok = hasKey && !amb && _responseMatchesKey(resp, expected);

      late final Color bg, bd, fg;
      if (amb) {
        bg = c.ambiguous.withValues(alpha: 0.12);
        bd = c.ambiguous;
        fg = c.ambiguous;
      } else if (!hasKey) {
        bg = c.cardMuted;
        bd = c.border;
        fg = c.textPrimary;
      } else if (ok) {
        bg = c.correct.withValues(alpha: 0.12);
        bd = c.correct;
        fg = c.correct;
      } else {
        bg = c.incorrect.withValues(alpha: 0.12);
        bd = c.incorrect;
        fg = c.incorrect;
      }

      return GestureDetector(
        onTap: onTapItem,
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bd),
          ),
          child: Column(
            children: [
              Text(item,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary)),
              const SizedBox(height: 2),
              Text(display,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: fg)),
            ],
          ),
        ),
      );
    }),
  );
}

void _openSheetZoomViewer(
  BuildContext context,
  Uint8List bytes, {
  List<ScoredBubbleMarker> markers = const [],
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Scored sheet'),
        ),
        body: InteractiveViewer(
          minScale: 0.8,
          maxScale: 6,
          child: Center(
            child: AspectRatio(
              aspectRatio: OmrConstants.cropAspect,
              child: ColoredBox(
                color: Colors.white,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          filterQuality: FilterQuality.high,
                        ),
                        if (markers.isNotEmpty)
                          CustomPaint(
                            painter: _ScoredMarkersPainter(markers: markers),
                          ),
                        if (markers.isNotEmpty)
                          _ScoredSheetLegend(
                            sheetWidth: constraints.maxWidth,
                            sheetHeight: constraints.maxHeight,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// PaperDetailView — review-papers student detail (summary + responses, no sheet)
// ═══════════════════════════════════════════════════════════════════════════

class PaperDetailView extends StatelessWidget {
  final ScanRecord record;
  final BubbleTemplate? template;
  final double passingScore;
  final VoidCallback onBack;
  final VoidCallback onEditAnswers;
  final VoidCallback onReScan;
  final VoidCallback? onUpload;

  const PaperDetailView({
    super.key,
    required this.record,
    this.template,
    this.passingScore = 50,
    required this.onBack,
    required this.onEditAnswers,
    required this.onReScan,
    this.onUpload,
  });

  List<({int item, String reason})> _flaggedRows() {
    final key = template?.answerKey ?? {};
    final total = key.isNotEmpty
        ? key.length
        : (template?.totalItems ?? record.responses.length);
    final flagged = record.flaggedItems.toSet();
    final out = <({int item, String reason})>[];
    for (var i = 1; i <= total; i++) {
      final resp = record.responses[i.toString()] ?? '?';
      if (!_isAmbiguousResponse(resp) && !flagged.contains(i)) continue;
      final display = _displayResponse(resp);
      String reason;
      if (display == '?') {
        reason = 'No answer';
      } else if (display.contains(',')) {
        reason = 'Multiple answers: $display';
      } else {
        reason = 'Invalid mark';
      }
      out.add((item: i, reason: reason));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    final key = template?.answerKey ?? {};
    final total = template?.totalItems ??
        (key.isNotEmpty ? key.length : record.responses.length);
    final storedMax = record.maxScore?.round();
    var storedCorrect = record.scoreRaw?.round();
    if (storedCorrect == null &&
        record.scorePercent != null &&
        storedMax != null &&
        storedMax > 0) {
      storedCorrect =
          ((record.scorePercent! / 100.0) * storedMax).round();
    }
    final breakdown = _scoreBreakdown(
      responses: record.responses,
      answerKey: key,
      totalItems: total,
      flaggedItems: record.flaggedItems,
      storedCorrect: storedCorrect,
      storedMax: storedMax,
    );
    final pct = record.scorePercent ??
        (breakdown.max > 0
            ? (breakdown.correct / breakdown.max) * 100.0
            : 0.0);
    final passed = pct >= passingScore;
    final scoreColor = passed ? colors.pass : colors.fail;
    final flagged = _flaggedRows();
    final isUploaded =
        record.serverScanId != null && record.serverScanId!.isNotEmpty;

    return Scaffold(
      backgroundColor: colors.scaffold,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        titleSpacing: 0,
        title: const Text(
          'Scan Result',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                _omrScoreSummaryCard(
                  context: context,
                  studentId: record.studentIdentifier,
                  correct: breakdown.correct,
                  incorrect: breakdown.incorrect,
                  ambiguous: breakdown.ambiguous,
                  max: breakdown.max,
                  pct: pct,
                  scoreColor: scoreColor,
                ),
                if (flagged.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _omrTinyReviewFlaggedButton(
                    context: context,
                    count: flagged.length,
                    onPressed: () => _showOmrFlaggedItemsSheet(
                      context,
                      items: flagged,
                      onEdit: onEditAnswers,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Item Responses',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: onEditAnswers,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Edit'),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.textSecondary,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _omrItemResponsesGrid(
                        context: context,
                        responses: record.responses,
                        answerKey: key,
                        totalItems: total,
                        flaggedItems: record.flaggedItems,
                        onTapItem: onEditAnswers,
                      ),
                    ],
                  ),
                ),
                if (!isUploaded && onUpload != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onUpload,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Upload to Server'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onReScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Rescan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AnswerEditableSheet — inline editing of bubble answers
// ═══════════════════════════════════════════════════════════════════════════

class EditAnswersSheet extends StatefulWidget {
  final ScanRecord record;
  final BubbleTemplate? template;
  final void Function(Map<String, String> updatedResponses) onSave;

  const EditAnswersSheet({
    super.key,
    required this.record,
    this.template,
    required this.onSave,
  });

  @override
  State<EditAnswersSheet> createState() => _EditAnswersSheetState();
}

class _EditAnswersSheetState extends State<EditAnswersSheet> {
  late Map<String, String> _editable;
  final int _columns = 5;
  String? _selectedItem;

  @override
  void initState() {
    super.initState();
    _editable = Map<String, String>.from(widget.record.responses);
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = widget.template?.totalItems ?? widget.record.responses.length;
    final numChoices = widget.template?.numChoices ?? 4;
    final choices = List.generate(numChoices, (i) => String.fromCharCode(65 + i));

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: bgGrey,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text('Edit Answers \u2014 ${widget.record.studentIdentifier}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                childAspectRatio: 1.2,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: totalItems,
              itemBuilder: (ctx, index) {
                final itemNum = (index + 1).toString();
                final current = _editable[itemNum] ?? '?';
                final display = _displayResponse(current);
                final isSelected = _selectedItem == itemNum;
                final correct = widget.template?.answerKey[itemNum];
                final amb = _isAmbiguousResponse(current);
                final ok = !amb && current == correct;
                final Color valueColor;
                if (amb) {
                  valueColor = Colors.orange.shade800;
                } else if (ok) {
                  valueColor = Colors.green.shade700;
                } else {
                  valueColor = primaryRed;
                }

                return GestureDetector(
                  onTap: () => setState(() => _selectedItem = isSelected ? null : itemNum),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? primaryRed.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? primaryRed : borderColor,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(itemNum, style: const TextStyle(fontSize: 10, color: grayText)),
                        Text(display,
                            style: TextStyle(
                                fontSize: display.length > 2 ? 12 : 16,
                                fontWeight: FontWeight.bold,
                                color: valueColor)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Choice picker for selected item
          if (_selectedItem != null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('Item $_selectedItem', style: const TextStyle(fontWeight: FontWeight.w600, color: darkText)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  ...choices.map((ch) {
                    final cur = _editable[_selectedItem] ?? '?';
                    final active = cur.toUpperCase().contains(ch);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ElevatedButton(
                          onPressed: () => setState(() {
                            final raw = (_editable[_selectedItem!] ?? '?').toUpperCase();
                            final letters = raw
                                .replaceAll(RegExp(r'[^A-Z]'), '')
                                .split('')
                                .where((c) => c.isNotEmpty)
                                .toSet();
                            if (letters.contains(ch)) {
                              letters.remove(ch);
                            } else {
                              letters.add(ch);
                            }
                            if (letters.isEmpty) {
                              _editable[_selectedItem!] = '?';
                            } else {
                              final sorted = letters.toList()..sort();
                              _editable[_selectedItem!] = sorted.join();
                            }
                          }),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: active ? primaryRed : Colors.white,
                            foregroundColor: active ? Colors.white : darkText,
                            side: BorderSide(color: active ? primaryRed : borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(ch, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    );
                  }),
                  SizedBox(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _editable[_selectedItem!] = '?'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade100,
                        foregroundColor: Colors.orange.shade800,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ElevatedButton.icon(
              onPressed: () {
                widget.onSave(_editable);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check),
              label: const Text('Save Answers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryRed,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TemplateSelectionView — preserved from original for init flow
// ═══════════════════════════════════════════════════════════════════════════

class TemplateSelectionView extends StatelessWidget {
  final List<BubbleTemplate> templates;
  final BubbleTemplate? selectedTemplate;
  final bool isLoading;
  final bool isLoadingDetail;
  final String? error;
  final String? courseName;
  final void Function(BubbleTemplate) onTemplateSelected;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;
  final VoidCallback onStartScan;
  final VoidCallback onBack;
  final Color _pRed;
  final Color _dText;
  final Color _gText;
  final Color _bColor;
  final Color _bGrey;

  const TemplateSelectionView({
    super.key,
    required this.templates,
    required this.selectedTemplate,
    required this.isLoading,
    this.isLoadingDetail = false,
    this.error,
    this.courseName,
    required this.onTemplateSelected,
    required this.onRetry,
    required this.onRefresh,
    required this.onStartScan,
    required this.onBack,
    required Color primaryRed,
    required Color darkText,
    required Color grayText,
    required Color borderColor,
    required Color bgGrey,
  })  : _pRed = primaryRed,
        _dText = darkText,
        _gText = grayText,
        _bColor = borderColor,
        _bGrey = bgGrey;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bGrey,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(icon: Icon(Icons.arrow_back, color: _dText), onPressed: onBack),
                const SizedBox(width: 8),
                Text('Select Assessment',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _dText)),
              ],
            ),
            if (courseName != null) ...[
              const SizedBox(height: 8),
              Text(courseName!, style: TextStyle(fontSize: 14, color: _gText)),
            ],
            const SizedBox(height: 24),
            if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            if (error != null && templates.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: _pRed),
                      const SizedBox(height: 12),
                      Text(error!, textAlign: TextAlign.center, style: TextStyle(color: _pRed, fontSize: 14)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            if (!isLoading && error == null && templates.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No bubble sheet templates found.\nCreate one from the web dashboard first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8391A1), fontSize: 14),
                  ),
                ),
              ),
            if (!isLoading && templates.isNotEmpty) ...[
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => onRefresh(),
                  child: ListView.separated(
                    itemCount: templates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final t = templates[index];
                      final isSelected = selectedTemplate?.templateId == t.templateId;
                      return GestureDetector(
                        onTap: () => onTemplateSelected(t),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? _pRed : _bColor,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: _pRed.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.assignment, color: _pRed, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(t.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${t.totalItems} items \u00b7 ${t.numChoices} choices \u00b7 ${t.hasAnswerKey ? "Key set" : "No key"}',
                                          style: TextStyle(fontSize: 12, color: _gText),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected && isLoadingDetail)
                                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _pRed)),
                                  if (!isLoadingDetail && isSelected)
                                    Icon(Icons.check_circle, color: _pRed, size: 24),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _buildKeyBadge(t),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: selectedTemplate != null && !isLoadingDetail ? onStartScan : null,
                icon: const Icon(Icons.camera_alt),
                label: isLoadingDetail
                    ? const Text('Loading answer key\u2026', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                    : const Text('Start Scanning', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pRed,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeyBadge(BubbleTemplate t) {
    if (t.hasAnswerKey && t.assessmentId != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 12, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Text('Assessment key \u2713',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
          ],
        ),
      );
    }
    if (t.hasAnswerKey) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Text('Manual key \u2713',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
      );
    }
    if (t.assessmentId != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: GestureDetector(
          onTap: () => onTemplateSelected(t),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sync, size: 12, color: Colors.orange.shade700),
              const SizedBox(width: 4),
              Text('No key \u2014 tap to sync',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text('No answer key',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red.shade600)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SectionSelectionSheet — bottom sheet for picking a section/template
// ═══════════════════════════════════════════════════════════════════════════

class SectionSelectionSheet extends StatelessWidget {
  final String courseId;
  final String courseName;
  final List<BubbleTemplate> templates;

  const SectionSelectionSheet({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.templates,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Text(
                  courseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: darkText,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Select an assessment',
                  style: TextStyle(fontSize: 13, color: grayText),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: borderColor),
          // Templates list
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // "Scan all sections" option
                _SelectionTile(
                  title: 'Scan All Sections',
                  subtitle: 'Capture all sections in one go',
                  icon: Icons.view_comfortable_outlined,
                  onTap: () {
                    Navigator.pop(context, {'template': null});
                  },
                ),
                // Individual templates
                ...templates.map((t) => _SelectionTile(
                      title: t.name,
                      subtitle: '${t.totalItems} items · ${t.numChoices} choices${t.hasAnswerKey ? ' · with key' : ''}',
                      icon: Icons.description_outlined,
                      onTap: () {
                        Navigator.pop(context, {'template': t});
                      },
                    )),
              ],
            ),
          ),
          // Cancel button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor),
                  ),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: grayText)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SelectionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primaryRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: primaryRed, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: darkText)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(fontSize: 12, color: grayText)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: grayText, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Post-capture: realigned sheet → scan animation → scored overlay → Scan next
// ═══════════════════════════════════════════════════════════════════════════

class ScanResultView extends StatefulWidget {
  final Uint8List? previewBytes;
  final String? fallbackImagePath;
  final bool isProcessing;
  final String statusMessage;
  final OmrResult? result;
  /// idle | uploading | uploaded | failed | rejected
  final String uploadStatus;
  /// Percent threshold for pass/fail score color (template default 50).
  final double passingScore;
  final VoidCallback onScanNext;
  final VoidCallback? onRescan;
  final VoidCallback? onRetryUpload;
  final VoidCallback? onClose;

  const ScanResultView({
    super.key,
    this.previewBytes,
    this.fallbackImagePath,
    required this.isProcessing,
    required this.statusMessage,
    this.result,
    this.uploadStatus = 'idle',
    this.passingScore = 50,
    required this.onScanNext,
    this.onRescan,
    this.onRetryUpload,
    this.onClose,
  });

  @override
  State<ScanResultView> createState() => _ScanResultViewState();
}

class _ScanResultViewState extends State<ScanResultView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didUpdateWidget(covariant ScanResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wantSweep = widget.isProcessing &&
        _statusIsBubbleScan(widget.statusMessage);
    if (wantSweep && !_scanController.isAnimating) {
      _scanController.repeat(reverse: true);
    } else if (!wantSweep && _scanController.isAnimating) {
      _scanController.stop();
      _scanController.value = 0;
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Uint8List? get _imageBytes => widget.previewBytes;

  /// Green sweep only while bubbles are actually being read — not during
  /// realign / scored-sheet JPEG / upload stages.
  bool _statusIsBubbleScan(String status) {
    final s = status.toLowerCase();
    return s.contains('reading student') ||
        s.contains('extracting') ||
        s.contains('scoring');
  }

  List<BubbleReading> _ambiguousReadings(OmrResult result) =>
      result.readings.where((r) => r.isAmbiguous).toList();

  String _ambiguousReason(BubbleReading r) {
    final note = (r.confidenceNote ?? '').trim();
    final lower = note.toLowerCase();
    if (lower.contains('blank') || lower.contains('no choice')) {
      return 'No answer';
    }
    if (lower.contains('double') || lower.contains('multiple')) {
      return 'Multiple answers marked';
    }
    if (lower.contains('row not detected') || lower.contains('not detected')) {
      return 'Not detected';
    }
    if (note.isNotEmpty) return note;
    if (r.detectedAnswer == '?' || r.detectedAnswer.isEmpty) {
      return 'Unclear or empty mark';
    }
    return 'Invalid mark';
  }

  void _showFlaggedItemsSheet(OmrResult result) {
    final items = _ambiguousReadings(result)
        .map((r) => (item: r.itemNumber, reason: _ambiguousReason(r)))
        .toList();
    _showOmrFlaggedItemsSheet(context, items: items);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    final result = widget.result;
    final rejected = widget.uploadStatus == 'rejected';
    final scored = result != null &&
        !widget.isProcessing &&
        !rejected &&
        result.isAlignmentUsable;
    final pct = result?.scorePercent ?? 0;
    final raw = result?.correctCount ?? 0;
    final max = result?.maxScore ?? 0;
    final studentId = result?.studentIdentifier ?? '—';
    final passed = pct >= widget.passingScore;
    final scoreColor = passed ? colors.pass : colors.fail;
    final ambiguousCount =
        result == null ? 0 : _ambiguousReadings(result).length;
    final incorrectCount =
        result == null ? 0 : (max - raw - ambiguousCount).clamp(0, max);
    final showMarkers = scored && result.scoredMarkers.isNotEmpty;

    return Scaffold(
      backgroundColor: colors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose ?? widget.onScanNext,
                    icon: Icon(Icons.close, color: colors.textSecondary),
                  ),
                  Text(
                    'Scan Result',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  if (widget.isProcessing) ...[
                    const SizedBox(height: 20),
                    Text(
                      widget.statusMessage.isNotEmpty
                          ? widget.statusMessage
                          : 'Processing sheet…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSheetCard(
                      showMarkers: false,
                      markers: const [],
                      processing: true,
                      showScanSweep: _statusIsBubbleScan(widget.statusMessage),
                    ),
                  ] else if (rejected) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.statusMessage.isNotEmpty
                          ? widget.statusMessage
                          : 'Scan rejected — please rescan',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.ambiguous,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Not saved to grading results',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    _buildSheetCard(
                      showMarkers: false,
                      markers: const [],
                      processing: false,
                    ),
                  ] else if (result != null) ...[
                    _omrScoreSummaryCard(
                      context: context,
                      studentId: studentId,
                      correct: raw,
                      incorrect: incorrectCount,
                      ambiguous: ambiguousCount,
                      max: max,
                      pct: pct,
                      scoreColor: scoreColor,
                    ),
                    if (ambiguousCount > 0) ...[
                      const SizedBox(height: 8),
                      _omrTinyReviewFlaggedButton(
                        context: context,
                        count: ambiguousCount,
                        onPressed: () => _showFlaggedItemsSheet(result),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildSheetCard(
                      showMarkers: showMarkers,
                      markers: result.scoredMarkers,
                      processing: false,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      switch (widget.uploadStatus) {
                        'uploading' => 'Uploading to grading results…',
                        'uploaded' => 'Saved to grading results',
                        'failed' => widget.statusMessage.isNotEmpty
                            ? widget.statusMessage
                            : 'Upload failed — tap retry',
                        _ => widget.statusMessage,
                      },
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: switch (widget.uploadStatus) {
                          'uploaded' => colors.correct,
                          'failed' => colors.incorrect,
                          'uploading' => colors.textSecondary,
                          _ => colors.textSecondary,
                        },
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else ...[
                    _buildSheetCard(
                      showMarkers: false,
                      markers: const [],
                      processing: false,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  if (widget.onRescan != null && scored) ...[
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: widget.onRescan,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Rescan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (widget.uploadStatus == 'failed' &&
                      widget.onRetryUpload != null) ...[
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: widget.onRetryUpload,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            side: BorderSide(color: colors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Retry upload',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            (!widget.isProcessing &&
                                    widget.uploadStatus != 'uploading')
                                ? widget.onScanNext
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          disabledBackgroundColor:
                              colors.border.withValues(alpha: 0.5),
                          foregroundColor: colors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          widget.isProcessing ||
                                  widget.uploadStatus == 'uploading'
                              ? 'Please wait…'
                              : (rejected
                                  ? 'Scan next'
                                  : (scored ? 'Scan next' : 'Try again')),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetCard({
    required bool showMarkers,
    required List<ScoredBubbleMarker> markers,
    required bool processing,
    bool showScanSweep = false,
  }) {
    final bytes = _imageBytes;
    final colors = context.atlas;
    final canZoom = bytes != null && !processing;
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canZoom)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => _openSheetZoomViewer(
                    context,
                    bytes,
                    markers: showMarkers ? markers : const [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in, color: Colors.blue.shade400, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Tap to zoom',
                        style: TextStyle(
                          color: Colors.blue.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          AspectRatio(
            aspectRatio: OmrConstants.cropAspect,
            child: GestureDetector(
              onTap: canZoom
                  ? () => _openSheetZoomViewer(
                        context,
                        bytes,
                        markers: showMarkers ? markers : const [],
                      )
                  : null,
              child: Container(
                color: Colors.white,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxW = constraints.maxWidth;
                    final boxH = constraints.maxHeight;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildSheetImage(boxW, boxH),
                        if (showScanSweep)
                          AnimatedBuilder(
                            animation: _scanController,
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _ScannerSweepPainter(
                                  progress: _scanController.value,
                                ),
                              );
                            },
                          ),
                        if (showMarkers)
                          CustomPaint(
                            painter: _ScoredMarkersPainter(markers: markers),
                          ),
                        if (showMarkers)
                          _ScoredSheetLegend(
                            sheetWidth: boxW,
                            sheetHeight: boxH,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetImage(double width, double height) {
    final bytes = _imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        width: width,
        height: height,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    }
    return const Center(
      child: Text('Aligning…', style: TextStyle(color: grayText)),
    );
  }
}

class _ScoredSheetLegend extends StatelessWidget {
  final double sheetWidth;
  final double sheetHeight;

  const _ScoredSheetLegend({
    required this.sheetWidth,
    required this.sheetHeight,
  });

  @override
  Widget build(BuildContext context) {
    // Empty white space on the lower-left of the ArUco crop, below the
    // student-ID bubble grid and above the bottom-left fiducial.
    return Positioned(
      left: (sheetWidth * 0.04).clamp(6.0, 20.0),
      bottom: (sheetHeight * 0.14).clamp(24.0, 80.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendRow(color: Color(0xFF00C853), label: 'Correct'),
            SizedBox(height: 3),
            _LegendRow(color: Color(0xFFE53935), label: 'Incorrect'),
            SizedBox(height: 3),
            _LegendRow(color: Color(0xFFFFB300), label: 'Invalid'),
            SizedBox(height: 3),
            _LegendRow(color: Color(0xFF9E9E9E), label: 'Student ID'),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ScannerSweepPainter extends CustomPainter {
  final double progress;
  _ScannerSweepPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final band = Rect.fromLTWH(0, y - 18, size.width, 36);
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0x0000E676),
          const Color(0x6600E676),
          const Color(0xCC00E676),
          const Color(0x6600E676),
          const Color(0x0000E676),
        ],
      ).createShader(band);
    canvas.drawRect(band, glow);
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = const Color(0xFF00E676)
        ..strokeWidth = 2.5,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerSweepPainter old) =>
      old.progress != progress;
}

class _ScoredMarkersPainter extends CustomPainter {
  final List<ScoredBubbleMarker> markers;
  _ScoredMarkersPainter({required this.markers});

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in markers) {
      final crop = OmrConstants.pageNormToCropNorm(m.nx, m.ny);
      final c = Offset(crop.$1 * size.width, crop.$2 * size.height);
      final r = (m.rMm / OmrConstants.cropWmm * size.width).clamp(4.0, 22.0);
      final color = switch (m.kind) {
        ScoredMarkerKind.studentId => const Color(0xFF9E9E9E),
        ScoredMarkerKind.correct => const Color(0xFF00C853),
        ScoredMarkerKind.wrong => const Color(0xFFE53935),
        ScoredMarkerKind.ambiguous => const Color(0xFFFFB300),
      };
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScoredMarkersPainter old) =>
      old.markers != markers;
}