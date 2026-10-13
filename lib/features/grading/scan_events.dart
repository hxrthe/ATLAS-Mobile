import 'dart:async';

/// A scan that was just saved from this device.
class ScanSavedEvent {
  final String templateId;
  final String studentId;
  final String? section;
  final double? score;
  final double? maxScore;

  const ScanSavedEvent({
    required this.templateId,
    required this.studentId,
    this.section,
    this.score,
    this.maxScore,
  });
}

/// In-app broadcast of locally saved scans, so screens can update instantly
/// without asking the backend.
class ScanEvents {
  ScanEvents._();

  static final StreamController<ScanSavedEvent> _controller =
      StreamController<ScanSavedEvent>.broadcast();

  static Stream<ScanSavedEvent> get stream => _controller.stream;

  static void emit(ScanSavedEvent event) => _controller.add(event);
}
