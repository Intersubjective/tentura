import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_nearest_ring.dart';

/// Nearest trust ring around the viewer (used by Tidy up placement).

const _gap = kConstellationRingUnitPixels;
const ({double x, double y}) _ego = (x: 100, y: -40);

({double x, double y}) _at(double distance, [double angle = 0]) => (
  x: _ego.x + math.cos(angle) * distance,
  y: _ego.y + math.sin(angle) * distance,
);

void main() {
  group('nearest ring while dragging', () {
    test('a point on a ring snaps to that ring', () {
      final ring = constellationNearestRing(centre: _ego, point: _at(2 * _gap));

      expect(ring.steps, 2);
      expect(ring.radius, closeTo(2 * _gap, 1e-9));
    });

    test('a point between two rings snaps to the closer one', () {
      expect(
        constellationNearestRing(centre: _ego, point: _at(2.4 * _gap)).steps,
        2,
      );
      expect(
        constellationNearestRing(centre: _ego, point: _at(2.6 * _gap)).steps,
        3,
      );
    });

    test('the direction from the viewer does not matter', () {
      for (final angle in [0.0, 1.0, 2.5, -2.0, math.pi]) {
        final ring = constellationNearestRing(
          centre: _ego,
          point: _at(3 * _gap, angle),
        );
        expect(ring.steps, 3, reason: 'angle $angle');
      }
    });

    test(
      'a point on the viewer snaps to the first ring, never to step zero',
      () {
        expect(constellationNearestRing(centre: _ego, point: _ego).steps, 1);
        expect(
          constellationNearestRing(centre: _ego, point: _at(0.2 * _gap)).steps,
          1,
        );
      },
    );
  });
}
