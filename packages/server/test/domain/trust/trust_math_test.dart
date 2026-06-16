import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/dirichlet_counts.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_math.dart';

void main() {
  group('expectedWeight', () {
    test('prior-only is neutral', () {
      expect(expectedWeight(DirichletCounts.zero), closeTo(0, 1e-9));
    });

    test('friend vote +3 good is ~0.375', () {
      final counts = DirichletCounts.zero.withAdded(
        TrustBin.good,
        kTrustVoteEvidenceCount,
      );
      expect(expectedWeight(counts), closeTo(0.375, 1e-9));
    });

    test('one good review is ~0.167', () {
      final counts = DirichletCounts.zero.withAdded(
        TrustBin.good,
        kTrustReviewEvidenceCount,
      );
      expect(expectedWeight(counts), closeTo(1 / 6, 1e-9));
    });

    test('one very_bad review is strongly negative', () {
      final counts = DirichletCounts.zero.withAdded(
        TrustBin.veryBad,
        kTrustReviewEvidenceCount,
      );
      expect(expectedWeight(counts), lessThan(-0.5));
    });
  });

  group('decayCounts', () {
    test('composes toward zero weight', () {
      final initial = DirichletCounts.zero.withAdded(
        TrustBin.good,
        kTrustVoteEvidenceCount,
      );
      final w0 = expectedWeight(initial);
      final half = decayCounts(
        counts: initial,
        elapsed: const Duration(days: 182),
        halfLife: const Duration(days: 182),
      );
      final w1 = expectedWeight(half);
      expect(w1, lessThan(w0));
      expect(w1, greaterThan(0));
    });

    test('zero elapsed is identity', () {
      final counts = DirichletCounts.zero.withAdded(TrustBin.bad, 2);
      expect(
        decayCounts(
          counts: counts,
          elapsed: Duration.zero,
          halfLife: const Duration(days: 182),
        ),
        counts,
      );
    });
  });

  group('mappers', () {
    test('vote amount maps to mild bins', () {
      expect(voteAmountToBin(1), TrustBin.good);
      expect(voteAmountToBin(-1), TrustBin.bad);
      expect(voteAmountToBin(0), TrustBin.noEffect);
    });

    test('NO_BASIS review value is skipped', () {
      expect(reviewValueToBin(0), isNull);
    });
  });
}
