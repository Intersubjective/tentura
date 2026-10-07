import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/graph/domain/layout/radial_hop_positions.dart';

/// Radial-hop layout speaks domain geometry records (`LPoint`/`LSize`) and
/// keeps the numeric output it had when it spoke `dart:ui` `Offset`/`Size`.
void main() {
  const LSize canvas = (w: 4096, h: 4096);

  void expectPoint(LPoint? actual, double x, double y) {
    expect(actual, isNotNull);
    expect(actual!.x, closeTo(x, 1e-6));
    expect(actual.y, closeTo(y, 1e-6));
  }

  group('computeRadialHopLayout with domain geometry', () {
    test('seats rings, parents and depths exactly as before the swap', () {
      final layout = computeRadialHopLayout(
        nodeIds: {'r', 'a', 'b', 'c', 'd', 'e'},
        edges: {
          ('r', 'a'),
          ('r', 'b'),
          ('r', 'c'),
          ('a', 'd'),
          ('a', 'e'),
          ('b', 'e'),
        },
        rootId: 'r',
        canvasSize: canvas,
        ringGap: 170,
      );

      final Map<String, LPoint> positions = layout.positions;
      expectPoint(positions['r'], 2048, 2048);
      expectPoint(positions['a'], 2217.0687222126066, 2065.769838755501);
      expectPoint(positions['b'], 1910.467110956259, 2147.9234928897204);
      expectPoint(positions['c'], 1934.247796918994, 1921.6653796688431);
      expectPoint(positions['d'], 2300.669240662314, 1820.4955938379883);
      expectPoint(positions['e'], 2247.8469857794407, 2323.065778087482);
      expect(layout.depth, {'r': 0, 'a': 1, 'b': 1, 'c': 1, 'd': 2, 'e': 2});
      expect(layout.parent, {'a': 'r', 'b': 'r', 'c': 'r', 'd': 'a', 'e': 'a'});
    });

    test('radialHopPositions returns the same seats as the full layout', () {
      final nodeIds = {'r', 'a', 'b', 'c', 'd', 'e'};
      final edges = {
        ('r', 'a'),
        ('r', 'b'),
        ('r', 'c'),
        ('a', 'd'),
        ('a', 'e'),
        ('b', 'e'),
      };

      final Map<String, LPoint> seats = radialHopPositions(
        nodeIds: nodeIds,
        edges: edges,
        rootId: 'r',
        canvasSize: canvas,
        ringGap: 170,
      );
      final Map<String, LPoint> full = computeRadialHopLayout(
        nodeIds: nodeIds,
        edges: edges,
        rootId: 'r',
        canvasSize: canvas,
        ringGap: 170,
      ).positions;

      expect(seats.keys.toSet(), nodeIds);
      expectPoint(seats['r'], 2048, 2048);
      expectPoint(seats['a'], 2217.0687222126066, 2065.769838755501);
      expectPoint(seats['e'], 2247.8469857794407, 2323.065778087482);
      for (final id in nodeIds) {
        expectPoint(seats[id], full[id]!.x, full[id]!.y);
      }
    });
  });

  group('clampLayoutPosition with domain geometry', () {
    test('pulls a point inside the canvas margin on both axes', () {
      final LPoint clamped = clampLayoutPosition(
        (x: 10, y: 5000),
        (w: 400, h: 300),
      );

      expect(clamped, (x: kLayoutClampMargin, y: 300 - kLayoutClampMargin));
    });

    test('leaves a point already inside the margin untouched', () {
      expect(
        clampLayoutPosition((x: 200, y: 150), (w: 400, h: 300)),
        (x: 200.0, y: 150.0),
      );
    });
  });

  group('branchUnitDirection with domain geometry', () {
    test('continues the grandparent-to-parent heading as a unit vector', () {
      final LPoint direction = branchUnitDirection(
        parentPos: (x: 100, y: 100),
        grandparentPos: (x: 40, y: 20),
      );

      expectPoint(direction, 0.6, 0.8);
    });

    test('points canvas-down when every anchor coincides or is missing', () {
      expect(
        branchUnitDirection(parentPos: (x: 100, y: 100)),
        (x: 0.0, y: 1.0),
      );
      expect(
        branchUnitDirection(
          parentPos: (x: 100, y: 100),
          rootPos: (x: 100, y: 100),
        ),
        (x: 0.0, y: 1.0),
      );
    });
  });

  group('localFanPositions with domain geometry', () {
    test('fans three children forward of the parent as before the swap', () {
      final Map<String, LPoint> fan = localFanPositions(
        parentPos: (x: 1000, y: 1000),
        direction: (x: 1, y: 0),
        childIds: ['x', 'y', 'z'],
        canvasSize: canvas,
        ringGap: 170,
      );

      expectPoint(fan['x'], 1147.2243186433545, 915);
      expectPoint(fan['y'], 1170, 1000);
      expectPoint(fan['z'], 1147.2243186433545, 1085);
    });
  });
}
