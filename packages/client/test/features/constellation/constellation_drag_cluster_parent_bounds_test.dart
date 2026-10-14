import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';

/// Canvas centre and one envelope unit in scene pixels (10 units = 1700 px).
const _centre = 2048.0;
const _unit = 170.0;

void main() {
  group('constellationLimitClusterDelta parent bounds', () {
    test(
      'a companion resting against the top wall does not limit how far the '
      'parent travels up',
      () {
        // Companion 17 px inside the top envelope edge (y = 348).
        const companionStart = (x: _centre, y: _centre - 9.9 * _unit);
        final limited = constellationLimitClusterDelta(
          parentStart: (x: _centre, y: _centre),
          proposedParent: (x: _centre, y: 600),
          companionStarts: const [companionStart],
        );

        expect(limited.x, closeTo(0, 1e-6));
        expect(limited.y, closeTo(600 - _centre, 1e-6));
      },
    );

    test(
      'a companion resting against the right wall does not limit the '
      'parent on either axis',
      () {
        const companionStart = (x: _centre + 9.95 * _unit, y: _centre);
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
        const companionStart = (x: _centre, y: _centre - 9.9 * _unit);
        final limited = constellationLimitClusterDelta(
          parentStart: (x: _centre, y: _centre),
          proposedParent: (x: _centre, y: 0),
          companionStarts: const [companionStart],
        );

        // The parent centre may reach the envelope top (y = 348), no further.
        expect(limited.y, closeTo(_centre - 10 * _unit - _centre, 1e-3));
      },
    );

    test(
      'a person without companions slides along the top wall instead of '
      'stopping when the pointer moves past it diagonally',
      () {
        const parentStart = (x: _centre, y: 360.0);
        final limited = constellationLimitClusterDelta(
          parentStart: parentStart,
          proposedParent: (x: _centre + 400, y: 100),
          companionStarts: const [],
        );

        expect(limited.x, closeTo(400, 1e-6));
        expect(limited.y, closeTo(348 - 360, 1e-3));
      },
    );
  });
}
