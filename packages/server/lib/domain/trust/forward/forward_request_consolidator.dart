import 'package:tentura_server/domain/trust/trust_bin.dart';

import 'forward_mass_propagator.dart';
import 'forward_outcome_policy.dart';

typedef PairBinKey = (
  String sender,
  String recipient,
  TrustBin bin,
  ForwardOutcomeProvenance provenance,
);

/// Vector consolidation across commitments per sender.
final class ForwardRequestConsolidator {
  Map<PairBinKey, double> accumulate(
    List<(
      TrustBin bin,
      ForwardOutcomeProvenance provenance,
      Map<ForwardPair, double> sharesByPair,
    )> perCommitmentShares, {
    double observationWeight = kForwardObservationWeight,
  }) {
    final support = <PairBinKey, double>{};
    for (final entry in perCommitmentShares) {
      final (bin, provenance, shares) = entry;
      for (final share in shares.entries) {
        final key = (share.key.$1, share.key.$2, bin, provenance);
        support[key] = (support[key] ?? 0) + observationWeight * share.value;
      }
    }
    return support;
  }

  Map<PairBinKey, double> normalizePerSender(
    Map<PairBinKey, double> support, {
    double budget = kForwardEvaluatedOutcomeBudget,
  }) {
    final bySender = <String, List<PairBinKey>>{};
    for (final key in support.keys) {
      bySender.putIfAbsent(key.$1, () => []).add(key);
    }

    final deltas = <PairBinKey, double>{};
    for (final entry in bySender.entries) {
      final keys = entry.value;
      final z = keys.fold<double>(0, (s, k) => s + (support[k] ?? 0));
      if (z <= 0) continue;
      for (final key in keys) {
        final r = support[key] ?? 0;
        if (r <= 0) continue;
        deltas[key] = budget * r / z;
      }
    }
    return deltas;
  }
}
