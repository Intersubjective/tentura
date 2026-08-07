import 'package:test/test.dart';

import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/evaluation/evaluation_received_trust_tone.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_received_result.dart';

void main() {
  group('evaluationReceivedTrustToneFromValue', () {
    test('noBasis maps to noBasis sentinel, not noChange', () {
      expect(
        evaluationReceivedTrustToneFromValue(BeaconEvaluationValue.noBasis),
        EvaluationReceivedTrustTone.noBasis,
      );
    });

    test('zero maps to noChange', () {
      expect(
        evaluationReceivedTrustToneFromValue(BeaconEvaluationValue.zero),
        EvaluationReceivedTrustTone.noChange,
      );
    });

    test('positive values map to up', () {
      expect(
        evaluationReceivedTrustToneFromValue(BeaconEvaluationValue.pos1),
        EvaluationReceivedTrustTone.up,
      );
      expect(
        evaluationReceivedTrustToneFromValue(BeaconEvaluationValue.pos2),
        EvaluationReceivedTrustTone.up,
      );
    });

    test('negative values map to down', () {
      expect(
        evaluationReceivedTrustToneFromValue(BeaconEvaluationValue.neg1),
        EvaluationReceivedTrustTone.down,
      );
      expect(
        evaluationReceivedTrustToneFromValue(BeaconEvaluationValue.neg2),
        EvaluationReceivedTrustTone.down,
      );
    });
  });
}
