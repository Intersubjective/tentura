import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_outcome_policy.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';

void main() {
  group('mapAuthorEvaluationToForwardOutcome', () {
    test('noBasis returns null', () {
      expect(mapAuthorEvaluationToForwardOutcome(0), isNull);
    });

    test('negative evaluations map to negativeRoute no_effect', () {
      for (final value in [1, 2]) {
        final outcome = mapAuthorEvaluationToForwardOutcome(value)!;
        expect(outcome.forwardBin, TrustBin.noEffect);
        expect(outcome.provenance, ForwardOutcomeProvenance.negativeRoute);
      }
    });

    test('non-negative bins preserve evaluated provenance', () {
      final pos = mapAuthorEvaluationToForwardOutcome(5)!;
      expect(pos.forwardBin, TrustBin.veryGood);
      expect(pos.provenance, ForwardOutcomeProvenance.evaluated);
    });
  });
}
