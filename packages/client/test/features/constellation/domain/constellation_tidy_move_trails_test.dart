import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_tidy_move_trails.dart';

/// After «Tidy up» each moved person leaves a trail from where they were to
/// where they are; the trails fade out over 1.5 seconds.

void main() {
  const trail = (from: (x: 0.0, y: 0.0), to: (x: 30.0, y: 0.0));

  group('tidy move trails', () {
    test('are fully visible when the tidy up has just happened', () {
      const trails = ConstellationMoveTrails({'A': trail});

      expect(trails.opacityAt(Duration.zero), 1.0);
      expect(trails.isVisibleAt(Duration.zero), isTrue);
    });

    test('fade steadily and are gone after 1.5 seconds', () {
      const trails = ConstellationMoveTrails({'A': trail});

      final early = trails.opacityAt(const Duration(milliseconds: 300));
      final late = trails.opacityAt(const Duration(milliseconds: 1200));

      expect(early, inInclusiveRange(0.0, 1.0));
      expect(late, lessThan(early));
      expect(trails.opacityAt(const Duration(milliseconds: 1500)), 0.0);
      expect(trails.isVisibleAt(const Duration(milliseconds: 1500)), isFalse);
      expect(trails.opacityAt(const Duration(seconds: 5)), 0.0);
    });

    test('remember where each person came from and went to', () {
      const trails = ConstellationMoveTrails({'A': trail});

      expect(trails.trails['A'], trail);
    });

    test('with reduced motion nodes jump but the trails still show and fade', () {
      expect(
        ConstellationMoveTrails.nodeAnimationDuration(reducedMotion: true),
        Duration.zero,
      );
      expect(
        ConstellationMoveTrails.nodeAnimationDuration(reducedMotion: false),
        greaterThan(Duration.zero),
      );
      const trails = ConstellationMoveTrails({'A': trail});
      expect(trails.opacityAt(Duration.zero), 1.0);
      expect(trails.opacityAt(const Duration(milliseconds: 1500)), 0.0);
    });
  });
}
