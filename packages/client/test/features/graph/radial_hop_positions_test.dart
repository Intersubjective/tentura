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

    test('focus path pins first hop upward', () {
      final withoutFocus = radialHopPositions(
        nodeIds: {'root', 'first', 'second'},
        edges: {('root', 'first'), ('first', 'second')},
        rootId: 'root',
        canvasSize: canvasSize,
        ringGap: ringGap,
      );
      final withFocus = radialHopPositions(
        nodeIds: {'root', 'first', 'second'},
        edges: {('root', 'first'), ('first', 'second')},
        rootId: 'root',
        canvasSize: canvasSize,
        focusPath: ['root', 'first', 'second'],
        ringGap: ringGap,
      );

      final first = withFocus['first']!;
      expect(first.dy, lessThan(centre.dy));
      expect(withFocus['first']!.dx, closeTo(centre.dx, 1));
      expect(withoutFocus['first'], isNot(withFocus['first']));
    });
  });
}
