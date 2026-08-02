import 'dart:math' as math;
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
    const parentPos = Offset(2000, 2000);
    const direction = Offset(0, 1);
    const defaultMinChord = 88.0; // amenity at ringGap=170

    double chordBetween(Offset a, Offset b) => (a - b).distance;

    double angularSpan(List<Offset> positions, Offset centre) {
      final angles = positions
          .map((p) => math.atan2(p.dy - centre.dy, p.dx - centre.dx))
          .toList()
        ..sort();
      return angles.last - angles.first;
    }

    test('single child continues straight along the branch', () {
      final fan = localFanPositions(
        parentPos: const Offset(100, 100),
        direction: direction,
        childIds: const ['c'],
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      expect(fan['c']!.dx, closeTo(100, 0.01));
      expect(fan['c']!.dy, closeTo(100 + ringGap, 0.01));
    });

    test('three siblings stay compact at ringGap (regression)', () {
      final fan = localFanPositions(
        parentPos: parentPos,
        direction: direction,
        childIds: const ['c', 'd', 'e'],
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      final positions = ['c', 'd', 'e'].map((id) => fan[id]!).toList();
      for (final pos in positions) {
        expect((pos - parentPos).distance, closeTo(ringGap, 0.01));
        expect(pos.dy, greaterThan(parentPos.dy));
      }
      expect(angularSpan(positions, parentPos), closeTo(math.pi / 3, 0.02));
      expect(
        chordBetween(positions[0], positions[1]),
        closeTo(defaultMinChord, 2),
      );
      expect(
        chordBetween(positions[1], positions[2]),
        closeTo(defaultMinChord, 2),
      );
    });

    test('five siblings expand sector to 120° at ringGap', () {
      final ids = List.generate(5, (i) => 'c$i');
      final fan = localFanPositions(
        parentPos: parentPos,
        direction: direction,
        childIds: ids,
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      final positions = ids.map((id) => fan[id]!).toList();
      for (final pos in positions) {
        expect((pos - parentPos).distance, closeTo(ringGap, 0.01));
      }
      expect(
        angularSpan(positions, parentPos),
        closeTo(kDefaultMaxFanRadians, 0.02),
      );
      for (var i = 0; i < positions.length - 1; i++) {
        expect(
          chordBetween(positions[i], positions[i + 1]),
          closeTo(defaultMinChord, 2),
        );
      }
    });

    test('seven siblings grow radius while keeping chord and forward projection',
        () {
      final ids = List.generate(7, (i) => 'c$i');
      final fan = localFanPositions(
        parentPos: parentPos,
        direction: direction,
        childIds: ids,
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      final positions = ids.map((id) => fan[id]!).toList();
      final radii = positions.map((p) => (p - parentPos).distance).toList();
      expect(radii.every((r) => r > ringGap + 1), isTrue);
      expect(radii.every((r) => (r - radii.first).abs() < 0.01), isTrue);
      expect(
        angularSpan(positions, parentPos),
        closeTo(kDefaultMaxFanRadians, 0.02),
      );
      for (var i = 0; i < positions.length - 1; i++) {
        expect(
          chordBetween(positions[i], positions[i + 1]),
          closeTo(defaultMinChord, 2),
        );
        final delta = positions[i] - parentPos;
        expect(delta.dx * direction.dx + delta.dy * direction.dy, greaterThan(0));
      }
    });

    test('large child count respects rMax and densifies gracefully', () {
      final ids = List.generate(25, (i) => 'c$i');
      final fan = localFanPositions(
        parentPos: parentPos,
        direction: direction,
        childIds: ids,
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      final positions = ids.map((id) => fan[id]!).toList();
      final radius = (positions.first - parentPos).distance;
      expect(radius, closeTo(ringGap * kFanRadiusMultiplier, 1));
      for (var i = 0; i < positions.length - 1; i++) {
        expect(chordBetween(positions[i], positions[i + 1]), greaterThan(0));
      }
    });

    test('minChord at least 2*ringGap clamps asin and uses radial mode', () {
      final geometry = computeLocalFanGeometry(
        childCount: 3,
        ringGap: ringGap,
        minChord: ringGap * 2.5,
      );
      expect(geometry.span, closeTo(kDefaultMaxFanRadians, 0.02));
      expect(geometry.radius, greaterThan(ringGap));
    });

    test('parent near canvas edge still yields finite clamped positions', () {
      final fan = localFanPositions(
        parentPos: const Offset(90, 90),
        direction: direction,
        childIds: List.generate(7, (i) => 'c$i'),
        canvasSize: canvasSize,
        ringGap: ringGap,
      );

      for (final pos in fan.values) {
        expect(pos.dx.isFinite, isTrue);
        expect(pos.dy.isFinite, isTrue);
        expect(pos.dx, greaterThanOrEqualTo(kLayoutClampMargin));
        expect(pos.dy, greaterThanOrEqualTo(kLayoutClampMargin));
      }
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
