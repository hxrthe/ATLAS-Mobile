import 'package:atlas_mobile/features/scanner/omr_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OmrEngine bubble selection', () {
    test('accepts a clear marked bubble with a moderate fill gap', () {
      final result = OmrEngine.evaluateBubbleSelection(
        bestChoice: 'A',
        bestFill: 0.24,
        secondFill: 0.08,
        globalThr: 0.20,
        effectiveThr: 0.20,
        maxGap: 0.12,
        lowConfidence: false,
        noOutliers: false,
        aboveEffective: true,
        aboveGlobal: true,
        passesHysteresis: true,
        goodFill: 0.42,
      );

      expect(result.detectedAnswer, 'A');
      expect(result.isAmbiguous, isFalse);
      expect(result.isConfirmed, isTrue);
    });

    test('keeps a bubble ambiguous when the top two fills are too close', () {
      final result = OmrEngine.evaluateBubbleSelection(
        bestChoice: 'B',
        bestFill: 0.16,
        secondFill: 0.14,
        globalThr: 0.20,
        effectiveThr: 0.20,
        maxGap: 0.03,
        lowConfidence: true,
        noOutliers: true,
        aboveEffective: false,
        aboveGlobal: false,
        passesHysteresis: false,
        goodFill: 0.42,
      );

      expect(result.detectedAnswer, '?');
      expect(result.isAmbiguous, isTrue);
      expect(result.isConfirmed, isFalse);
    });
  });
}
