import 'trust_bin.dart';

/// Evidence counts `c_k` (excess over Laplace prior) per semantic bin.
final class DirichletCounts {
  const DirichletCounts({
    this.veryBad = 0,
    this.bad = 0,
    this.noEffect = 0,
    this.good = 0,
    this.veryGood = 0,
  });

  final double veryBad;
  final double bad;
  final double noEffect;
  final double good;
  final double veryGood;

  double countFor(TrustBin bin) => switch (bin) {
    TrustBin.veryBad => veryBad,
    TrustBin.bad => bad,
    TrustBin.noEffect => noEffect,
    TrustBin.good => good,
    TrustBin.veryGood => veryGood,
  };

  DirichletCounts withAdded(TrustBin bin, double delta) => switch (bin) {
    TrustBin.veryBad => copyWith(veryBad: veryBad + delta),
    TrustBin.bad => copyWith(bad: bad + delta),
    TrustBin.noEffect => copyWith(noEffect: noEffect + delta),
    TrustBin.good => copyWith(good: good + delta),
    TrustBin.veryGood => copyWith(veryGood: veryGood + delta),
  };

  DirichletCounts copyWith({
    double? veryBad,
    double? bad,
    double? noEffect,
    double? good,
    double? veryGood,
  }) => DirichletCounts(
    veryBad: veryBad ?? this.veryBad,
    bad: bad ?? this.bad,
    noEffect: noEffect ?? this.noEffect,
    good: good ?? this.good,
    veryGood: veryGood ?? this.veryGood,
  );

  static const zero = DirichletCounts();
}
