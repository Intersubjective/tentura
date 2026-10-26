import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/graph/domain/layout/layered_dag_positions.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import '../constellation/layout_point_vector_ext.dart';

void main() {
  const LSize canvasSize = (w: 4096, h: 4096);
  const layerGap = 150.0;
  const columnGap = 130.0;

  group('layeredDagPositions', () {
    test('ranks become rows for a chain', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('b', 'c')},
        rootIds: {'a'},
        canvasSize: canvasSize,
      );

      final a = positions['a']!;
      final b = positions['b']!;
      final c = positions['c']!;

      expect(a.dx, closeTo(b.dx, 0.01));
      expect(b.dx, closeTo(c.dx, 0.01));
      expect(a.dy, isNot(b.dy));
      expect(b.dy, isNot(c.dy));
      expect(a.dy, lessThan(b.dy));
      expect(b.dy, lessThan(c.dy));
    });

    test('siblings share a row', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('a', 'c')},
        rootIds: {'a'},
        canvasSize: canvasSize,
      );

      final b = positions['b']!;
      final c = positions['c']!;

      expect(b.dy, closeTo(c.dy, 0.01));
      expect(b.dx, isNot(closeTo(c.dx, 0.01)));
    });

    test('order independence', () {
      final nodesA = {'a', 'b', 'c'};
      final edgesA = {('a', 'b'), ('b', 'c')};
      final nodesB = {'c', 'a', 'b'};
      final edgesB = {('b', 'c'), ('a', 'b')};

      final fromA = layeredDagPositions(
        nodeIds: nodesA,
        edges: edgesA,
        rootIds: {'a'},
        canvasSize: canvasSize,
      );
      final fromB = layeredDagPositions(
        nodeIds: nodesB,
        edges: edgesB,
        rootIds: {'a'},
        canvasSize: canvasSize,
      );

      expect(fromA, fromB);
    });

    test('no overlap within a layer', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c', 'd'},
        edges: {('a', 'b'), ('a', 'c'), ('a', 'd')},
        rootIds: {'a'},
        canvasSize: canvasSize,
      );

      final siblings = [positions['b']!, positions['c']!, positions['d']!];
      for (var i = 0; i < siblings.length; i++) {
        for (var j = i + 1; j < siblings.length; j++) {
          final gap = (siblings[i].dx - siblings[j].dx).abs();
          expect(gap, greaterThanOrEqualTo(columnGap));
        }
      }
    });

    test('genealogy ancestor chain ranks top-down without explicit roots', () {
      // Genealogy edges run ancestor -> descendant, so the viewer ("ego") is a
      // leaf. Passing no roots must rank from the topmost ancestor instead of
      // flattening the whole chain into one row.
      final positions = layeredDagPositions(
        nodeIds: {'root', 'a', 'b', 'ego'},
        edges: {('root', 'a'), ('a', 'b'), ('b', 'ego')},
        rootIds: const {},
        canvasSize: canvasSize,
      );

      final ys = [
        'root',
        'a',
        'b',
        'ego',
      ].map((id) => positions[id]!.dy).toList();
      expect(ys.toSet().length, 4);
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i - 1], lessThan(ys[i]));
      }
      final xs = positions.values.map((offset) => offset.dx).toSet();
      expect(xs.length, 1);
    });

    test('horizontal: ranks become columns, root on the left (#464)', () {
      final positions = layeredDagPositions(
        nodeIds: {'root', 'a', 'b', 'ego'},
        edges: {('root', 'a'), ('a', 'b'), ('b', 'ego')},
        rootIds: const {},
        canvasSize: canvasSize,
        horizontal: true,
      );

      final xs = [
        'root',
        'a',
        'b',
        'ego',
      ].map((id) => positions[id]!.dx).toList();
      for (var i = 1; i < xs.length; i++) {
        expect(xs[i] - xs[i - 1], closeTo(layerGap, 0.01));
      }
      final ys = positions.values.map((offset) => offset.dy).toSet();
      expect(ys.length, 1);
    });

    test('horizontal: siblings share a column, a column gap apart', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('a', 'c')},
        rootIds: {'a'},
        canvasSize: canvasSize,
        horizontal: true,
      );

      final b = positions['b']!;
      final c = positions['c']!;
      expect(b.dx, closeTo(c.dx, 0.01));
      expect(b.dx, greaterThan(positions['a']!.dx));
      expect((b.dy - c.dy).abs(), closeTo(columnGap, 0.01));
    });

    test('horizontal is the vertical layout transposed about the centre', () {
      const nodeIds = {'a', 'b', 'c', 'd'};
      const edges = {('a', 'b'), ('a', 'c'), ('c', 'd')};
      final vertical = layeredDagPositions(
        nodeIds: nodeIds,
        edges: edges,
        rootIds: {'a'},
        canvasSize: canvasSize,
      );
      final horizontal = layeredDagPositions(
        nodeIds: nodeIds,
        edges: edges,
        rootIds: {'a'},
        canvasSize: canvasSize,
        horizontal: true,
      );

      for (final id in nodeIds) {
        expect(horizontal[id]!.x, closeTo(vertical[id]!.y, 0.01));
        expect(horizontal[id]!.y, closeTo(vertical[id]!.x, 0.01));
      }
    });

    test('cycle safety', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('b', 'c'), ('c', 'a')},
        rootIds: const {},
        canvasSize: canvasSize,
      );

      expect(positions.length, 3);
      for (final offset in positions.values) {
        expect(offset.dx.isFinite, isTrue);
        expect(offset.dy.isFinite, isTrue);
      }
    });
  });
}
