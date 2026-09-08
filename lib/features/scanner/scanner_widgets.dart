import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter/services.dart';
import '../grading/models.dart';
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
            child: _ShutterButton(
              ready: readyToCapture,
              onTap: onCapture,
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
  const _FiducialOverlay({required this.lockState, this.readyToCapture = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _FiducialPainter(lockState: lockState, readyToCapture: readyToCapture),
      ),
    );
  }
}

class _FiducialPainter extends CustomPainter {
  final FiducialLockState lockState;
  final bool readyToCapture;
  _FiducialPainter({required this.lockState, this.readyToCapture = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Paper clear zone (long bond 8.5" × 13") — fills most of the preview.
    const topMargin = 24.0;
    const bottomMargin = 24.0;
    const paperAspectRatio = 13.0 / 8.5; // height / width
    const pageWmm = 215.9;
    const pageHmm = 330.2;
    // Printed fiducials (bubble_sheet_generator.py) — NOT at paper corners.
    const fidInset = 8.0;
    const fidW = 10.0;
    const headerMm = 50.8; // 2" — top fiducials start here
    const contentBotMm = 294.8; // bottom fiducial top edge

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
    final detectedCount = corners.where((c) {
      final p = c.position;
      if (!c.detected || p == null) return false;
      return clearRect.inflate(fidPx).contains(
            Offset(p.dx * size.width, p.dy * size.height),
          );
    }).length;
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

    // Tracking boxes: follow last-known detected positions (move + turn green).
    // Only draw when the hit lies inside the paper guide — never on the floor.
    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      final Offset center;
      final Color color;
      final double box = fidPx.clamp(22.0, 40.0);

      final pos = c.position;
      final insideGuide = pos != null &&
          clearRect.inflate(fidPx).contains(
                Offset(pos.dx * size.width, pos.dy * size.height),
              );

      if (pos != null && insideGuide) {
        center = Offset(
          pos.dx.clamp(0.0, 1.0) * size.width,
          pos.dy.clamp(0.0, 1.0) * size.height,
        );
        color = c.locked
            ? const Color(0xFF00E676)
            : (c.detected ? Colors.white : Colors.white70);
      } else {
        center = expectedFidRects[i].center;
        color = Colors.white.withValues(alpha: 0.35);
      }

      final rect =
          Rect.fromCenter(center: center, width: box + 10, height: box + 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = c.locked && insideGuide ? 4.0 : 2.5,
      );
      if (pos != null && insideGuide) {
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
      msg = '\u2713 ALIGNED \u2014 tap to grade';
      msgColor = Colors.greenAccent;
    } else if (lockState.allLocked) {
      msg = 'Sheet locked \u2014 scan Assessment QR';
      msgColor = Colors.greenAccent;
    } else if (detectedCount >= 2) {
      msg = 'Tracking fiducials ($detectedCount/4) \u2014 hold steady';
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
      lockState != o.lockState || readyToCapture != o.readyToCapture;
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
// PaperDetailView — detailed view for editing or re-scanning
// ═══════════════════════════════════════════════════════════════════════════

class PaperDetailView extends StatelessWidget {
  final ScanRecord record;
  final BubbleTemplate? template;
  final VoidCallback onBack;
  final VoidCallback onEditAnswers;
  final VoidCallback onReScan;
  final VoidCallback? onUpload;

  const PaperDetailView({
    super.key,
    required this.record,
    this.template,
    required this.onBack,
    required this.onEditAnswers,
    required this.onReScan,
    this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final sp = record.scorePercent;
    final score = sp != null ? '${sp.toStringAsFixed(1)}%' : 'N/A';
    final raw = record.scoreRaw != null ? '${record.scoreRaw!.toStringAsFixed(0)} / ${record.maxScore?.toStringAsFixed(0) ?? "?"}' : null;
    final isPass = sp != null && sp >= 60;
    final isUploaded = record.serverScanId != null && record.serverScanId!.isNotEmpty;

    return Scaffold(
      backgroundColor: bgGrey,
      appBar: AppBar(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        title: Text(record.studentIdentifier, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Score card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  Text(score,
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900,
                          color: isPass ? Colors.green.shade700 : primaryRed)),
                  if (raw != null) ...[
                    const SizedBox(height: 4),
                    Text(raw, style: const TextStyle(fontSize: 14, color: grayText)),
                  ],
                  if (record.isFlagged) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade300)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag, color: Colors.orange.shade700, size: 14),
                          const SizedBox(width: 4),
                          Text(record.flagReason ?? 'Flagged for review',
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Responses grid
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Item Responses', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: darkText)),
                  const SizedBox(height: 14),
                  if (template != null && template!.answerKey.isNotEmpty)
                    _buildResponsesGrid(record, template!)
                  else
                    Text('${record.responses.length} items scanned', style: const TextStyle(fontSize: 13, color: grayText)),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEditAnswers,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit Answers'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryRed,
                      side: const BorderSide(color: primaryRed),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReScan,
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Re-scan Paper'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      side: BorderSide(color: Colors.orange.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsesGrid(ScanRecord r, BubbleTemplate t) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: r.responses.entries.map((entry) {
        final item = entry.key;
        final resp = entry.value;
        final correct = t.answerKey[item];
        final ok = resp == correct;
        final amb = resp == '?';

        Color bg, bd, fg;
        if (amb) {
          bg = Colors.orange.shade50; bd = Colors.orange.shade300; fg = Colors.orange.shade700;
        } else if (ok) {
          bg = Colors.green.shade50; bd = Colors.green.shade300; fg = Colors.green.shade700;
        } else {
          bg = Colors.red.shade50; bd = Colors.red.shade300; fg = Colors.red.shade700;
        }

        return Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bd),
          ),
          child: Column(
            children: [
              Text(item, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: grayText)),
              const SizedBox(height: 2),
              Text(resp, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: fg)),
            ],
          ),
        );
      }).toList(),
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
                final isSelected = _selectedItem == itemNum;
                final correct = widget.template?.answerKey[itemNum];

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
                        Text(current,
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold,
                                color: current == correct ? Colors.green.shade700 : darkText)),
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
                    final active = _editable[_selectedItem] == ch;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ElevatedButton(
                          onPressed: () => setState(() => _editable[_selectedItem!] = ch),
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
  final VoidCallback onScanNext;
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
    required this.onScanNext,
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
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant ScanResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isProcessing && !_scanController.isAnimating) {
      _scanController.repeat(reverse: true);
    } else if (!widget.isProcessing && _scanController.isAnimating) {
      _scanController.stop();
      _scanController.value = 0;
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Uint8List? get _imageBytes =>
      widget.result?.alignedImageBytes ?? widget.previewBytes;

  @override
  Widget build(BuildContext context) {
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
    final showMarkers = scored && result.scoredMarkers.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose ?? widget.onScanNext,
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                  const Expanded(
                    child: Text(
                      'Scan result',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (scored)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: pct >= 60
                            ? const Color(0xFF00E676).withValues(alpha: 0.15)
                            : primaryRed.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: pct >= 60
                              ? const Color(0xFF00E676)
                              : const Color(0xFFFF8A80),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.white,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Long-bond warped sheet ≈ 8.5 × 13 — match marker space.
                        const pageAspect = 8.5 / 13.0;
                        var boxW = constraints.maxWidth;
                        var boxH = boxW / pageAspect;
                        if (boxH > constraints.maxHeight) {
                          boxH = constraints.maxHeight;
                          boxW = boxH * pageAspect;
                        }
                        return Center(
                          child: SizedBox(
                            width: boxW,
                            height: boxH,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildSheetImage(boxW, boxH),
                                if (widget.isProcessing)
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
                                    painter: _ScoredMarkersPainter(
                                      markers: result.scoredMarkers,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  if (widget.isProcessing) ...[
                    Text(
                      widget.statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white70,
                      ),
                    ),
                  ] else if (rejected) ...[
                    Text(
                      widget.statusMessage.isNotEmpty
                          ? widget.statusMessage
                          : 'Scan rejected — please rescan',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFB74D),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Not saved to grading results',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ] else if (result != null) ...[
                    Text(
                      'Student ID  $studentId',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Score  $raw / $max   ·   ${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    if (result.isFlagged && result.flagReason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        result.flagReason!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
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
                          'uploaded' => const Color(0xFF81C784),
                          'failed' => const Color(0xFFFF8A80),
                          'uploading' => Colors.white70,
                          _ => Colors.white54,
                        },
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  if (widget.uploadStatus == 'failed' &&
                      widget.onRetryUpload != null) ...[
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: widget.onRetryUpload,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
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
                          backgroundColor: primaryRed,
                          disabledBackgroundColor: Colors.white12,
                          foregroundColor: Colors.white,
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
                                  ? 'Rescan'
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

  Widget _buildSheetImage(double width, double height) {
    final bytes = _imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.fill,
        width: width,
        height: height,
        gaplessPlayback: true,
      );
    }
    final path = widget.fallbackImagePath;
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => const Center(
          child: Text('Capturing…', style: TextStyle(color: grayText)),
        ),
      );
    }
    return const Center(
      child: CircularProgressIndicator(color: primaryRed),
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
      final c = Offset(m.nx * size.width, m.ny * size.height);
      final color =
          m.isCorrect ? const Color(0xFF00C853) : const Color(0xFFE53935);
      final r = (size.shortestSide * 0.022).clamp(10.0, 18.0);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
      canvas.drawCircle(
        c,
        r,
        Paint()..color = color.withValues(alpha: 0.14),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScoredMarkersPainter old) =>
      old.markers != markers;
}