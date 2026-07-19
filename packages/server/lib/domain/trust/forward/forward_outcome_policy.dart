import 'package:tentura_server/domain/trust/trust_bin.dart';

const kForwardObservationWeight = 1.0;
const kForwardEvaluatedOutcomeBudget = 1.0;
const kForwardAlgorithmVersion = 1;

/// Normative §3 mapping (sign-off S1).
({TrustBin forwardBin, ForwardOutcomeProvenance provenance})?
mapAuthorEvaluationToForwardOutcome(int value) {
  return switch (value) {
    0 => null,
    1 || 2 => (
      forwardBin: TrustBin.noEffect,
      provenance: ForwardOutcomeProvenance.negativeRoute,
    ),
    3 => (
      forwardBin: TrustBin.noEffect,
      provenance: ForwardOutcomeProvenance.evaluated,
    ),
    4 => (
      forwardBin: TrustBin.good,
      provenance: ForwardOutcomeProvenance.evaluated,
    ),
    5 => (
      forwardBin: TrustBin.veryGood,
      provenance: ForwardOutcomeProvenance.evaluated,
    ),
    _ => null,
  };
}

enum ForwardOutcomeProvenance { evaluated, negativeRoute }
