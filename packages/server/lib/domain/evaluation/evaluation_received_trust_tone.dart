import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_received_result.dart';

/// Maps a review value to receiver-facing trust tone (D6: `noBasis` ≠ `noEffect`).
EvaluationReceivedTrustTone evaluationReceivedTrustToneFromValue(int value) {
  if (value == BeaconEvaluationValue.noBasis) {
    return EvaluationReceivedTrustTone.noBasis;
  }
  return switch (value) {
    BeaconEvaluationValue.neg2 ||
    BeaconEvaluationValue.neg1 => EvaluationReceivedTrustTone.down,
    BeaconEvaluationValue.zero => EvaluationReceivedTrustTone.noChange,
    BeaconEvaluationValue.pos1 ||
    BeaconEvaluationValue.pos2 => EvaluationReceivedTrustTone.up,
    _ => EvaluationReceivedTrustTone.noBasis,
  };
}
