import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/graph/domain/layout/radial_hop_positions.dart';

void main() {
  const canvasSize = Size(4096, 4096);
  const ringGap = 170.0;
  final centre = canvasSize.center(Offset.zero);

  group('radialHopPositions', () {
    test('root at centre', () {
      final positions = radialHopPositions(
        nodeIds: {'root', 'other'},
        edges: {('root', 'other')},
        rootId: 'root',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(positions['root'], centre);
    });

    test('ring by hop', () {
      final positions = radialHopPositions(
        nodeIds: {'root', 'mid', 'far'},
        edges: {('root', 'mid'), ('mid', 'far')},
        rootId: 'root',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      final far = positions['far']!;
      final distance = (far - centre).distance;
      expect(distance, closeTo(2 * ringGap, 0.01));
    });

    test('order independence', () {
      final nodesA = {'a', 'b', 'c'};
      final edgesA = {('a', 'b'), ('b', 'c')};
      final nodesB = {'c', 'a', 'b'};
      final edgesB = {('b', 'c'), ('a', 'b')};

      final fromA = radialHopPositions(
        nodeIds: nodesA,
        edges: edgesA,
        rootId: 'a',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );
      final fromB = radialHopPositions(
        nodeIds: nodesB,
        edges: edgesB,
        rootId: 'a',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(fromA, fromB);
    });

    test('stability when adding unrelated node', () {
      final ab = radialHopPositions(
        nodeIds: {'a', 'b'},
        edges: {('a', 'b')},
        rootId: 'a',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );
      final abc = radialHopPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('b', 'c')},
        rootId: 'a',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(abc['a'], ab['a']);
    });

    test('cycles produce distinct finite positions', () {
      final positions = radialHopPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('b', 'c'), ('c', 'a')},
        rootId: 'a',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(positions.length, 3);
      final coords = positions.values.toList();
      for (final offset in coords) {
        expect(offset.dx.isFinite, isTrue);
        expect(offset.dy.isFinite, isTrue);
      }
      expect(coords[0], isNot(coords[1]));
      expect(coords[1], isNot(coords[2]));
      expect(coords[0], isNot(coords[2]));
    });

    test('disconnected node gets outermost ring position', () {
      final positions = radialHopPositions(
        nodeIds: {'root', 'solo'},
        edges: const {},
        rootId: 'root',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(positions.containsKey('solo'), isTrue);
      final soloDistance = (positions['solo']! - centre).distance;
      expect(soloDistance, closeTo(ringGap, 0.01));
    });

    test('first-hop angle is fixed by sorted id, not rotated upward', () {
      final positions = radialHopPositions(
        nodeIds: {'root', 'alpha', 'zeta'},
        edges: {('root', 'alpha'), ('root', 'zeta')},
        rootId: 'root',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      // Children sorted by id: alpha then zeta → alpha owns [0, π), mid = π/2.
      // Angle 0 points up (-π/2 in coords), so π/2 is to the right of centre.
      final alpha = positions['alpha']!;
      expect(alpha.dx, greaterThan(centre.dx));
      expect(alpha.dy, closeTo(centre.dy, 1));
    });

    test('descendant stays put when an unrelated sibling branch is absent', () {
      // Stability holds for the root; sibling insertion redistributes sectors
      // (pinning across mutations is handled by RadialHopLayoutAlgorithm.relayout).
      final ab = radialHopPositions(
        nodeIds: {'a', 'b'},
        edges: {('a', 'b')},
        rootId: 'a',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );
      final abc = radialHopPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('b', 'c')},
        rootId: 'a',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(abc['a'], ab['a']);
      expect(abc['b'], ab['b']);
    });
  });

  group('localFanPositions', () {
    test('single child continues straight along the branch', () {
      final fan = localFanPositions(
        parentPos: const Offset(100, 100),
        direction: const Offset(0, 1),
        childIds: const ['c'],
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(fan['c']!.dx, closeTo(100, 0.01));
      expect(fan['c']!.dy, closeTo(100 + ringGap, 0.01));
    });

    test('siblings stay within a compact fan ahead of the parent', () {
      final fan = localFanPositions(
        parentPos: const Offset(2000, 2000),
        direction: const Offset(0, 1),
        childIds: const ['c', 'd', 'e'],
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      for (final id in ['c', 'd', 'e']) {
        final pos = fan[id]!;
        expect((pos - const Offset(2000, 2000)).distance, closeTo(ringGap, 0.01));
        expect(pos.dy, greaterThan(2000));
      }
      expect(
        (fan['c']! - fan['e']!).distance,
        lessThan(ringGap * 1.5),
      );
    });
  });

  group('branchUnitDirection', () {
    test('prefers parent minus grandparent', () {
      final dir = branchUnitDirection(
        parentPos: const Offset(10, 30),
        grandparentPos: const Offset(10, 10),
      );
      expect(dir.dx, closeTo(0, 1e-9));
      expect(dir.dy, closeTo(1, 1e-9));
    });
  });
}
