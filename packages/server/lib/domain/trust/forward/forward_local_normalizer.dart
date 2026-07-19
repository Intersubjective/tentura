import 'forward_mass_propagator.dart';

/// Per-sender local normalization of raw causal masses.
final class ForwardLocalNormalizer {
  Map<ForwardPair, double> normalize(Map<ForwardPair, double> rawMass) {
    final bySender = <String, List<ForwardPair>>{};
    for (final key in rawMass.keys) {
      bySender.putIfAbsent(key.$1, () => []).add(key);
    }

    final shares = <ForwardPair, double>{};
    for (final entry in bySender.entries) {
      final keys = entry.value;
      final sum = keys.fold<double>(0, (s, k) => s + (rawMass[k] ?? 0));
      if (sum <= 0) continue;
      for (final key in keys) {
        shares[key] = (rawMass[key] ?? 0) / sum;
      }
    }
    return shares;
  }
}
