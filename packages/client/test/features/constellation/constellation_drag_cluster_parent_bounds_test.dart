import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';

/// Canvas centre, and the distance from it to each envelope edge in scene
/// pixels.
const _centre = kConstellationCanvasCentre;
const _edge = kConstellationCoordinateMaxUnits * kConstellationRingUnitPixels;

void main() {
  group('constellationLimitClusterDelta parent bounds', () {
    test(
      'a companion resting against the top wall does not limit how far the '
      'parent travels up',
      () {
        // Companion 17 px inside the top envelope edge.
        const companionStart = (x: _centre, y: _centre - _edge + 17);
        final limited = constellationLimitClusterDelta(
          parentStart: (x: _centre, y: _centre),
          proposedParent: (x: _centre, y: _centre - 1448),
          companionStarts: const [companionStart],
        );

        expect(limited.x, closeTo(0, 1e-6));
        expect(limited.y, closeTo(-1448, 1e-6));
      },
    );

    test(
      'a companion resting against the right wall does not limit the '
      'parent on either axis',
      () {
        const companionStart = (x: _centre + _edge - 8.5, y: _centre);
        final limited = constellationLimitClusterDelta(
          parentStart: (x: _centre, y: _centre),
          proposedParent: (x: _centre + 300, y: _centre - 500),
          companionStarts: const [companionStart],
        );

        expect(limited.x, closeTo(300, 1e-6));
        expect(limited.y, closeTo(-500, 1e-6));
      },
    );

    test(
      'the parent still stops at its own envelope edge when companions are '
      'present',
      () {
        const companionStart = (x: _centre, y: _centre - _edge + 17);
        final limited = constellationLimitClusterDelta(
          parentStart: (x: _centre, y: _centre),
          proposedParent: (x: _centre, y: _centre - _edge),
          companionStarts: const [companionStart],
        );

        // The parent centre may reach the envelope top, no further.
        expect(limited.y, closeTo(-_edge, 1e-3));
      },
    );

    test(
      'a person without companions slides along the top wall instead of '
      'stopping when the pointer moves past it diagonally',
      () {
        const parentStart = (x: _centre, y: _centre - _edge + 12);
        final limited = constellationLimitClusterDelta(
          parentStart: parentStart,
          proposedParent: (x: _centre + 400, y: _centre - _edge - 248),
          companionStarts: const [],
        );

        expect(limited.x, closeTo(400, 1e-6));
        expect(limited.y, closeTo(-12, 1e-3));
      },
    );
  });
}
