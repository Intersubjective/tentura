import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_gather.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

// «Gather»: the selected nodes become a compact cluster around the centroid of
// where they are now. Pure and deterministic, so the same selection always
// gathers to the same places whatever order it was picked in.

const double _spacing = 60;

typedef _Member = ({String id, LPoint position});

/// [count] nodes scattered over the field, ids `m0`...
List<_Member> _scattered(int count) => [
  for (var i = 0; i < count; i++)
    (
      id: 'm$i',
      position: (
        x: 2048 + math.cos(i * 2.399963) * (200 + 37.0 * i),
        y: 2048 + math.sin(i * 2.399963) * (200 + 37.0 * i),
      ),
    ),
];

LPoint _centroid(Iterable<LPoint> points) {
  var x = 0.0;
  var y = 0.0;
  var n = 0;
  for (final p in points) {
    x += p.x;
    y += p.y;
    n++;
  }
  return (x: x / n, y: y / n);
}

double _distance(LPoint a, LPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

void main() {
  group('gather arrangement', () {
    test('gives every selected node a place', () {
      final members = _scattered(40);

      final targets = arrangeConstellationGather(
        members: members,
        spacing: _spacing,
      );

      expect(targets.keys, unorderedEquals([for (final m in members) m.id]));
    });

    test('centres the cluster on the centroid of the current positions', () {
      final members = _scattered(40);

      final targets = arrangeConstellationGather(
        members: members,
        spacing: _spacing,
      );

      final before = _centroid([for (final m in members) m.position]);
      final after = _centroid(targets.values);
      expect(after.x, closeTo(before.x, 1e-6));
      expect(after.y, closeTo(before.y, 1e-6));
    });

    for (final spacing in [40.0, 90.0]) {
      test(
        'keeps every pair of nodes at least a spacing of $spacing apart',
        () {
          final targets = arrangeConstellationGather(
            members: _scattered(40),
            spacing: spacing,
          );

          final points = targets.values.toList();
          for (var a = 0; a < points.length; a++) {
            for (var b = a + 1; b < points.length; b++) {
              expect(
                _distance(points[a], points[b]),
                greaterThanOrEqualTo(spacing - 1e-6),
              );
            }
          }
        },
      );
    }

    test('pulls the nodes closer to their centroid than they were', () {
      final members = _scattered(40);
      final centre = _centroid([for (final m in members) m.position]);

      final targets = arrangeConstellationGather(
        members: members,
        spacing: _spacing,
      );

      final farthestBefore = members
          .map((m) => _distance(m.position, centre))
          .reduce(math.max);
      final farthestAfter = targets.values
          .map((p) => _distance(p, centre))
          .reduce(math.max);
      expect(farthestAfter, lessThan(farthestBefore));
    });

    test('does not depend on the order the nodes were picked in', () {
      final members = _scattered(40);

      final forward = arrangeConstellationGather(
        members: members,
        spacing: _spacing,
      );
      final backward = arrangeConstellationGather(
        members: members.reversed.toList(),
        spacing: _spacing,
      );

      expect(backward, forward);
    });

    test('has nothing to gather for fewer than two nodes', () {
      expect(
        arrangeConstellationGather(members: const [], spacing: _spacing),
        isEmpty,
      );
      expect(
        arrangeConstellationGather(
          members: _scattered(1),
          spacing: _spacing,
        ),
        isEmpty,
      );
    });
  });
}
