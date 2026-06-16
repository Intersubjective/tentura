import 'dart:math' as math;

import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';

import 'dirichlet_counts.dart';
import 'trust_bin.dart';

/// Multiplicative decay of evidence counts toward the Laplace prior.
DirichletCounts decayCounts({
  required DirichletCounts counts,
  required Duration elapsed,
  required Duration halfLife,
}) {
  if (elapsed <= Duration.zero || halfLife <= Duration.zero) {
    return counts;
  }
  final factor = math.pow(
    0.5,
    elapsed.inMicroseconds / halfLife.inMicroseconds,
  ).toDouble();
  return DirichletCounts(
    veryBad: counts.veryBad * factor,
    bad: counts.bad * factor,
    noEffect: counts.noEffect * factor,
    good: counts.good * factor,
    veryGood: counts.veryGood * factor,
  );
}

/// Posterior mean of bin values: w = Σ(α_k·v_k) / Σα_k with α_k = 1 + c_k.
double expectedWeight(DirichletCounts counts) {
  const bins = TrustBin.values;
  var weightedSum = 0.0;
  var alphaSum = 0.0;
  for (final bin in bins) {
    final alpha = kTrustLaplacePrior + counts.countFor(bin);
    weightedSum += alpha * bin.weight;
    alphaSum += alpha;
  }
  if (alphaSum == 0) return 0;
  return weightedSum / alphaSum;
}

TrustBin? reviewValueToBin(int value) => switch (value) {
  BeaconEvaluationValue.neg2 => TrustBin.veryBad,
  BeaconEvaluationValue.neg1 => TrustBin.bad,
  BeaconEvaluationValue.zero => TrustBin.noEffect,
  BeaconEvaluationValue.pos1 => TrustBin.good,
  BeaconEvaluationValue.pos2 => TrustBin.veryGood,
  _ => null,
};

TrustBin? voteAmountToBin(int amount) => switch (amount) {
  1 => TrustBin.good,
  -1 => TrustBin.bad,
  0 => TrustBin.noEffect,
  _ => null,
};
