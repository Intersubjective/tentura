import 'dart:math' as math;

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

/// Reference scale [R_ego] from the ego's top peers (architecture §5.2).
///
/// Fewer than three peers → maximum score; three or more → median of the top
/// three by `forward_mr` (not the average of two).
double computeREgo(List<RawPeerFact> topPeers) {
  if (topPeers.isEmpty) {
    return 0;
  }
  if (topPeers.length < 3) {
    return topPeers
        .map((p) => p.forwardMr)
        .reduce(math.max);
  }
  final topThree = topPeers.take(3).map((p) => p.forwardMr).toList()
    ..sort();
  return topThree[1];
}

/// 33rd-percentile floor over the ego's explicitly-trusted peers with
/// `forward_mr > 0`. Empty trusted set → no floor.
double? computeFloor(List<double> trustedScores) {
  if (trustedScores.isEmpty) {
    return null;
  }
  return continuousPercentile(trustedScores, kCapFloorPercentile);
}

/// Witness weight `m = min(1, forward_mr / R_ego)`; guards `R_ego = 0`.
double computeM({required double forwardMr, required double rEgo}) {
  if (rEgo <= 0) {
    return 0;
  }
  return math.min(1, forwardMr / rEgo);
}

/// Admission: explicit trust, or meets the ego's revealed floor when present.
bool computeAdmitted({
  required bool explicitlyTrusted,
  required double forwardMr,
  required double? floor,
}) {
  if (explicitlyTrusted) {
    return true;
  }
  return floor != null && forwardMr >= floor;
}

/// Pure admission policy over [facts] returned by [WitnessWindowPort.rawWindowFacts].
List<WitnessWeight> computeWitnessWeights(RawWindowFacts facts) {
  final rEgo = computeREgo(facts.topPeers);
  final floor = computeFloor(facts.trustedScores);

  return [
    for (final peer in facts.topPeers)
      WitnessWeight(
        witnessUserId: peer.peerId,
        m: computeM(forwardMr: peer.forwardMr, rEgo: rEgo),
        admitted: computeAdmitted(
          explicitlyTrusted: peer.explicitlyTrusted,
          forwardMr: peer.forwardMr,
          floor: floor,
        ),
      ),
  ];
}

/// Continuous percentile matching PostgreSQL `percentile_cont(p)`.
double continuousPercentile(List<double> values, double p) {
  assert(p >= 0 && p <= 1);
  if (values.isEmpty) {
    throw StateError('continuousPercentile requires a non-empty list');
  }
  final sorted = List<double>.from(values)..sort();
  if (sorted.length == 1) {
    return sorted.first;
  }
  final pos = p * (sorted.length - 1);
  final lower = pos.floor();
  final upper = pos.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  final fraction = pos - lower;
  return sorted[lower] +
      fraction * (sorted[upper] - sorted[lower]);
}
