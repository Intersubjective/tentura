import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';

void main() {
  group('EvaluationReceivedTrustTone.fromWire', () {
    test('maps known server tone strings', () {
      expect(
        EvaluationReceivedTrustTone.fromWire('up'),
        EvaluationReceivedTrustTone.up,
      );
      expect(
        EvaluationReceivedTrustTone.fromWire('down'),
        EvaluationReceivedTrustTone.down,
      );
      expect(
        EvaluationReceivedTrustTone.fromWire('noChange'),
        EvaluationReceivedTrustTone.noChange,
      );
      expect(
        EvaluationReceivedTrustTone.fromWire('noBasis'),
        EvaluationReceivedTrustTone.noBasis,
      );
    });

    test('noBasis is distinct from noChange', () {
      expect(
        EvaluationReceivedTrustTone.fromWire('noBasis'),
        isNot(EvaluationReceivedTrustTone.noChange),
      );
    });

    test('unknown tone falls back to noChange', () {
      expect(
        EvaluationReceivedTrustTone.fromWire('unexpected'),
        EvaluationReceivedTrustTone.noChange,
      );
    });
  });
}
