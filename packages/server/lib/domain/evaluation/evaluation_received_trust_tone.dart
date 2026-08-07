import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';
import 'package:tentura_server/domain/entity/gql_public/evaluation_received_result.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_math.dart';

/// Maps a review value to receiver-facing trust tone (D6: `noBasis` ≠ `noEffect`).
EvaluationReceivedTrustTone evaluationReceivedTrustToneFromValue(int value) {
  if (value == BeaconEvaluationValue.noBasis) {
    return EvaluationReceivedTrustTone.noBasis;
  }
  final bin = reviewValueToBin(value);
  if (bin == null) {
    return EvaluationReceivedTrustTone.noBasis;
  }
  return switch (bin) {
    TrustBin.veryBad || TrustBin.bad => EvaluationReceivedTrustTone.down,
    TrustBin.noEffect => EvaluationReceivedTrustTone.noChange,
    TrustBin.good || TrustBin.veryGood => EvaluationReceivedTrustTone.up,
  };
}
