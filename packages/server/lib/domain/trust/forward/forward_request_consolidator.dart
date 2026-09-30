import 'forward_mass_propagator.dart';

const kForwardObservationWeight = 1.0;

/// Vector consolidation across seeds, keyed by `(sender, recipient)` only.
final class ForwardRequestConsolidator {
  Map<ForwardPair, double> accumulate(
    List<Map<ForwardPair, double>> perSeedShares, {
    double observationWeight = kForwardObservationWeight,
  }) {
    final support = <ForwardPair, double>{};
    for (final shares in perSeedShares) {
      for (final share in shares.entries) {
        support[share.key] =
            (support[share.key] ?? 0) + observationWeight * share.value;
      }
    }
    return support;
  }

  Map<ForwardPair, double> normalizePerSender(
    Map<ForwardPair, double> support, {
    required double budget,
  }) {
    final bySender = <String, List<ForwardPair>>{};
    for (final key in support.keys) {
      bySender.putIfAbsent(key.$1, () => []).add(key);
    }

    final deltas = <ForwardPair, double>{};
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
