import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/graph/domain/layout/layered_dag_positions.dart';

void main() {
  const canvasSize = Size(4096, 4096);
  const layerGap = 150.0;
  const columnGap = 130.0;

  group('layeredDagPositions', () {
    test('ranks become rows for a chain', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('b', 'c')},
        rootIds: {'a'},
        canvasSize: canvasSize,
        layerGap: layerGap,
        columnGap: columnGap,
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
        layerGap: layerGap,
        columnGap: columnGap,
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
        layerGap: layerGap,
        columnGap: columnGap,
      );
      final fromB = layeredDagPositions(
        nodeIds: nodesB,
        edges: edgesB,
        rootIds: {'a'},
        canvasSize: canvasSize,
        layerGap: layerGap,
        columnGap: columnGap,
      );

      expect(fromA, fromB);
    });

    test('no overlap within a layer', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c', 'd'},
        edges: {('a', 'b'), ('a', 'c'), ('a', 'd')},
        rootIds: {'a'},
        canvasSize: canvasSize,
        layerGap: layerGap,
        columnGap: columnGap,
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
        layerGap: layerGap,
        columnGap: columnGap,
      );

      final ys = ['root', 'a', 'b', 'ego']
          .map((id) => positions[id]!.dy)
          .toList();
      expect(ys.toSet().length, 4);
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i - 1], lessThan(ys[i]));
      }
      final xs = positions.values.map((offset) => offset.dx).toSet();
      expect(xs.length, 1);
    });

    test('cycle safety', () {
      final positions = layeredDagPositions(
        nodeIds: {'a', 'b', 'c'},
        edges: {('a', 'b'), ('b', 'c'), ('c', 'a')},
        rootIds: const {},
        canvasSize: canvasSize,
        layerGap: layerGap,
        columnGap: columnGap,
      );

      expect(positions.length, 3);
      for (final offset in positions.values) {
        expect(offset.dx.isFinite, isTrue);
        expect(offset.dy.isFinite, isTrue);
      }
    });
  });
}
