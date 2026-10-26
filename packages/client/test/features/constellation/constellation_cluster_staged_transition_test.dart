import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_transition_stages.dart';

String _id(int i) => 'p${i.toString().padLeft(3, '0')}';

/// [communityCount] communities of [size] people each: `c00` holds p000.., etc.
Map<String, Set<String>> _communities({
  required int communityCount,
  required int size,
}) => {
  for (var c = 0; c < communityCount; c++)
    'c${c.toString().padLeft(2, '0')}': {
      for (var i = 0; i < size; i++) _id(c * size + i),
    },
};

void main() {
  group('cluster-staged bulk transition', () {
    final communities = _communities(communityCount: 20, size: 20);
    final everyone = {for (final members in communities.values) ...members};

    test('every person gets exactly one stage', () {
      final stages = stageConstellationTransition(communities: communities);

      expect(stages.keys.toSet(), everyone);
      expect(everyone, hasLength(400));
    });

    test('people of one community move together', () {
      final stages = stageConstellationTransition(communities: communities);

      for (final members in communities.values) {
        expect({for (final id in members) stages[id]}, hasLength(1));
      }
    });

    test('400 people share a handful of stages, not 400 timings', () {
      final stages = stageConstellationTransition(
        communities: communities,
        maxStages: 5,
      );

      expect(stages.values.toSet().length, lessThanOrEqualTo(5));
      expect(stages.values.toSet().length, greaterThan(1));
    });

    test('the earliest stage starts at the first instant', () {
      final stages = stageConstellationTransition(communities: communities);

      final earliest = stages.values
          .map((stage) => stage.delay)
          .reduce((a, b) => a < b ? a : b);
      expect(earliest, Duration.zero);
    });

    test('the whole transition fits the total duration', () {
      const total = Duration(milliseconds: 600);
      final stages = stageConstellationTransition(
        communities: communities,
        totalDuration: total,
      );

      for (final stage in stages.values) {
        expect(stage.duration, greaterThan(Duration.zero));
        expect(stage.delay + stage.duration, lessThanOrEqualTo(total));
      }
      expect(
        stages.values
            .map((stage) => stage.delay + stage.duration)
            .reduce((a, b) => a > b ? a : b),
        total,
      );
    });

    test('a single community is one stage that starts at once', () {
      final stages = stageConstellationTransition(
        communities: _communities(communityCount: 1, size: 30),
      );

      expect(stages.values.toSet(), hasLength(1));
      expect(stages.values.first.delay, Duration.zero);
    });

    test('the same communities stage identically', () {
      expect(
        stageConstellationTransition(communities: communities),
        stageConstellationTransition(communities: communities),
      );
    });

    test('reduced motion lands every person at once', () {
      final stages = stageConstellationTransition(
        communities: communities,
        reducedMotion: true,
      );

      expect(stages.keys.toSet(), everyone);
      for (final stage in stages.values) {
        expect(stage.delay, Duration.zero);
        expect(stage.duration, Duration.zero);
      }
    });
  });
}
