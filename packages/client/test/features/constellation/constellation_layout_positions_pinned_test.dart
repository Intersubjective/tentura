import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

/// Moving the layout domain onto `LPoint`/`LSize` must not move a single seat:
/// these coordinates were captured from the `dart:ui`-based implementation.
void main() {
  group('computeConstellationLayout seats as domain geometry points', () {
    test('keeps ring seats, satellite fans and residual ring unchanged', () {
      final paths = resolveConstellationPaths(
        egoId: 'ego',
        visiblePeerIds: {'a', 'b', 'q', 'r'},
        holderIds: {'b', 'r'},
        edges: [
          (src: 'ego', dst: 'a', tier: 1),
          (src: 'a', dst: 'b', tier: 1),
          (src: 'b', dst: 'q', tier: 1),
          (src: 'ego', dst: 'q', tier: 2),
          (src: 'q', dst: 'r', tier: 2),
        ],
        maxHops: 3,
      );

      final layout = computeConstellationLayout(
        egoId: 'ego',
        paths: paths,
        keptPeerIds: {'a', 'b', 'r'},
        visibleRequestsByAuthor: {
          'a': ['req1', 'req2'],
          'b': ['req3'],
        },
        egoOwnRequestIds: {'reqE1', 'reqE2'},
      );

      const c = kConstellationCanvasCentre;
      final expected = <String, LPoint>{
        'ego': (x: c, y: c),
        'a': (x: c, y: c + 170.0),
        'b': (x: c, y: c + 340.0),
        'r': (x: c, y: c - 782.0),
        'req1': (x: c - 57.2864111347958, y: c + 259.41311095759),
        'req2': (x: c + 57.286411134796, y: c + 259.41311095759),
        'req3': (x: c, y: c + 476.0),
        'reqE1': (x: c - 35.1993901339429, y: c - 131.3659123753134),
        'reqE2': (x: c + 63.1947808464383, y: c - 117.5601134954867),
      };
      final Map<String, LPoint> actual = layout.positions;

      expect(actual.keys.toSet(), expected.keys.toSet());
      for (final entry in expected.entries) {
        expect(
          actual[entry.key]!.x,
          closeTo(entry.value.x, 1e-6),
          reason: entry.key,
        );
        expect(
          actual[entry.key]!.y,
          closeTo(entry.value.y, 1e-6),
          reason: entry.key,
        );
      }
      expect(layout.ring['a'], 1);
      expect(layout.ring['b'], 2);
      expect(layout.ring['r'], 4);
    });
  });
}
