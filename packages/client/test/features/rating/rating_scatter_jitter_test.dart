import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/rating/ui/util/stable_scatter_jitter.dart';

/// Regression for alloy:lesson:golden_tests_need_deterministic_fixtures… and
/// bead_source scatter-view jitter (must not depend on Object.hash).
void main() {
  const profileId = 'rating-scatter-jitter-fixture-7f3a';

  test('stable scatter jitter returns identical offsets for the same profile id', () {
    final first = scatterPlotJitterOffsetForId(profileId);
    final second = scatterPlotJitterOffsetForId(profileId);
    expect(first, equals(second));
  });
}
