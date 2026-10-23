import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_sector_arrangement.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

// «Arrange in a sector» (#644): the selected nodes go evenly into rings
// inside a sector around any centre — inner rings first, equal steps along
// every ring, the last ring spread over the whole sector — the nearest nodes
// on the inner ring and everyone keeping their order around the centre.

const LPoint _centre = (x: 2048, y: 2048);
const double _spacing = 100;

LPoint _polar(double angle, double radius, [LPoint centre = _centre]) => (
  x: centre.x + math.cos(angle) * radius,
  y: centre.y + math.sin(angle) * radius,
);

double _radius(LPoint p, [LPoint centre = _centre]) =>
    math.sqrt(math.pow(p.x - centre.x, 2) + math.pow(p.y - centre.y, 2));

double _angle(LPoint p, [LPoint centre = _centre]) =>
    math.atan2(p.y - centre.y, p.x - centre.x);

double _distance(LPoint a, LPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Signed difference a - b in (-π, π].
double _diff(double a, double b) {
  var d = a - b;
  while (d <= -math.pi) {
    d += 2 * math.pi;
  }
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  return d;
}

/// [count] nodes scattered deterministically around [_centre].
List<ConstellationSectorMember> _scatter(int count, {int seed = 7}) {
  final random = math.Random(seed);
  return [
    for (var i = 0; i < count; i++)
      (
        id: 'n$i',
        position: _polar(
          random.nextDouble() * 2 * math.pi,
          50 + random.nextDouble() * 900,
        ),
      ),
  ];
}

ConstellationSectorLayout _arrange(
  List<ConstellationSectorMember> members, {
  LPoint centre = _centre,
  double direction = -math.pi / 2,
  double span = math.pi / 2,
  double innerRadius = 300,
  double minSpacing = _spacing,
  LRect? bounds,
}) => arrangeConstellationSector(
  centre: centre,
  members: members,
  direction: direction,
  span: span,
  innerRadius: innerRadius,
  minSpacing: minSpacing,
  bounds: bounds,
);

/// The targets grouped by ring (by radius), innermost first, each ring in
/// angle order from the sector's start.
List<List<LPoint>> _byRing(
  ConstellationSectorLayout layout, [
  LPoint centre = _centre,
]) => [
  for (final radius in layout.rings)
    [
      for (final point in layout.targets.values)
        if ((_radius(point, centre) - radius).abs() < 1e-6) point,
    ]..sort(
      (a, b) => ((_angle(a, centre) - layout.start) % (2 * math.pi)).compareTo(
        (_angle(b, centre) - layout.start) % (2 * math.pi),
      ),
    ),
];

void main() {
  group('constellationSectorRingCapacity', () {
    test('counts the places a ring holds with neighbours a spacing apart', () {
      // At radius r the step for chord d is 2·asin(d / 2r).
      final step = 2 * math.asin(_spacing / (2 * 300));
      expect(
        constellationSectorRingCapacity(
          radius: 300,
          span: math.pi / 2,
          minSpacing: _spacing,
        ),
        (math.pi / 2 / step).floor(),
      );
      expect(
        constellationSectorRingCapacity(
          radius: 300,
          span: 2 * math.pi,
          minSpacing: _spacing,
        ),
        (2 * math.pi / step).floor(),
      );
    });

    test('an exact fit counts: two across a diameter of one spacing', () {
      expect(
        constellationSectorRingCapacity(
          radius: _spacing / 2,
          span: 2 * math.pi,
          minSpacing: _spacing,
        ),
        2,
      );
      // Six around a circle whose radius is the spacing (a hexagon).
      expect(
        constellationSectorRingCapacity(
          radius: _spacing,
          span: 2 * math.pi,
          minSpacing: _spacing,
        ),
        6,
      );
    });

    test('always holds at least one', () {
      expect(
        constellationSectorRingCapacity(
          radius: 10,
          span: math.pi / 12,
          minSpacing: _spacing,
        ),
        1,
      );
    });
  });

  group('arrangeConstellationSector', () {
    test('a single ring: equal steps across the sector, centred on the '
        'direction, every target inside it', () {
      final members = [
        (id: 'a', position: _polar(0.1, 300)),
        (id: 'b', position: _polar(2, 300)),
        (id: 'c', position: _polar(-2.5, 300)),
      ];
      const direction = math.pi / 2;
      final layout = _arrange(members, direction: direction);

      expect(layout.targets.keys, unorderedEquals(['a', 'b', 'c']));
      expect(layout.rings, [300]);
      expect(layout.sweep, closeTo(math.pi / 2, 1e-12));
      expect(layout.start, closeTo(direction - math.pi / 4, 1e-12));
      final ring = _byRing(layout).single;
      final angles = ring.map(_angle).toList();
      // Three cells of π/6 each, a node in the middle of every cell.
      expect(_diff(angles[0], layout.start), closeTo(math.pi / 12, 1e-9));
      expect(_diff(angles[1], angles[0]), closeTo(math.pi / 6, 1e-9));
      expect(_diff(angles[2], angles[1]), closeTo(math.pi / 6, 1e-9));
      expect(_diff(angles[1], direction), closeTo(0, 1e-9));
      for (final point in ring) {
        expect(_radius(point), closeTo(300, 1e-9));
      }
    });

    test('fills inner rings first, then adds rings a spacing apart', () {
      final members = _scatter(40);
      final layout = _arrange(members);

      expect(layout.targets, hasLength(40));
      for (var i = 0; i < layout.rings.length; i++) {
        expect(layout.rings[i], closeTo(300 + i * _spacing, 1e-9));
      }
      final rings = _byRing(layout);
      expect(rings.fold<int>(0, (sum, ring) => sum + ring.length), 40);
      for (var i = 0; i < rings.length - 1; i++) {
        expect(
          rings[i].length,
          constellationSectorRingCapacity(
            radius: layout.rings[i],
            span: math.pi / 2,
            minSpacing: _spacing,
          ),
          reason: 'ring $i is full',
        );
      }
      expect(
        rings.last.length,
        lessThanOrEqualTo(
          constellationSectorRingCapacity(
            radius: layout.rings.last,
            span: math.pi / 2,
            minSpacing: _spacing,
          ),
        ),
      );
    });

    test('steps are equal along every ring, and the last ring is spread '
        'over the whole sector, centred', () {
      final layout = _arrange(_scatter(23));
      final rings = _byRing(layout);
      expect(rings.length, greaterThan(1));
      for (final ring in rings) {
        final cell = layout.sweep / ring.length;
        final angles = ring.map(_angle).toList();
        expect(_diff(angles.first, layout.start), closeTo(cell / 2, 1e-9));
        expect(
          _diff(layout.start + layout.sweep, angles.last),
          closeTo(cell / 2, 1e-9),
        );
        for (var i = 1; i < angles.length; i++) {
          expect(_diff(angles[i], angles[i - 1]), closeTo(cell, 1e-9));
        }
      }
    });

    for (final span in [math.pi / 12, math.pi / 3, math.pi, 2 * math.pi]) {
      for (final count in [1, 2, 7, 30, 64, 200]) {
        test(
          'no two targets closer than the spacing and all inside the '
          'sector: $count nodes, span ${(span * 180 / math.pi).round()}°',
          () {
            final layout = _arrange(
              _scatter(count, seed: count),
              span: span,
              innerRadius: 40,
              direction: 2.5,
            );
            final points = layout.targets.values.toList();
            expect(points, hasLength(count));
            for (var i = 0; i < points.length; i++) {
              for (var j = i + 1; j < points.length; j++) {
                expect(
                  _distance(points[i], points[j]),
                  greaterThanOrEqualTo(_spacing - 1e-6),
                );
              }
              // Never closer to the centre than one spacing.
              expect(_radius(points[i]), greaterThanOrEqualTo(_spacing - 1e-9));
              final along = (_angle(points[i]) - layout.start) % (2 * math.pi);
              expect(along, lessThanOrEqualTo(layout.sweep + 1e-9));
            }
          },
        );
      }
    }

    test('a full circle has no doubled place at its seam', () {
      final layout = _arrange(
        _scatter(12),
        span: 2 * math.pi,
        innerRadius: 400,
      );
      final ring = _byRing(layout).first;
      final step = 2 * math.pi / ring.length;
      final angles = ring.map(_angle).toList();
      for (var i = 0; i < angles.length; i++) {
        final next = angles[(i + 1) % angles.length];
        expect(_diff(next, angles[i]), closeTo(step, 1e-9));
      }
    });

    test('a radius too small for anyone gets rings outward instead of '
        'overlaps', () {
      final layout = _arrange(_scatter(5), innerRadius: 0, span: math.pi / 12);
      expect(layout.rings.first, _spacing);
      // A narrow sector holds one per ring here: a column outward.
      expect(layout.rings, hasLength(5));
    });

    test('the nearest go on the inner ring, and each ring keeps the order '
        'around the centre', () {
      final members = [
        (id: 'far-left', position: _polar(-math.pi / 2 - 0.5, 900)),
        (id: 'near-right', position: _polar(-math.pi / 2 + 0.4, 200)),
        (id: 'near-left', position: _polar(-math.pi / 2 - 0.4, 210)),
        (id: 'far-right', position: _polar(-math.pi / 2 + 0.5, 950)),
      ];
      // Two places on the first ring (r 200, 60°), the other two outside.
      final layout = _arrange(members, innerRadius: 200, span: math.pi / 3);

      expect(layout.rings, hasLength(2));
      final inner = layout.rings.first;
      expect(_radius(layout.targets['near-left']!), closeTo(inner, 1e-9));
      expect(_radius(layout.targets['near-right']!), closeTo(inner, 1e-9));
      expect(
        _angle(layout.targets['near-left']!),
        lessThan(_angle(layout.targets['near-right']!)),
      );
      expect(
        _angle(layout.targets['far-left']!),
        lessThan(_angle(layout.targets['far-right']!)),
      );
    });

    test('arranging an arrangement again changes nothing', () {
      for (final span in [math.pi / 4, math.pi, 2 * math.pi]) {
        final first = _arrange(_scatter(37), span: span, direction: 1);
        final again = _arrange(
          [
            for (final MapEntry(key: id, value: position)
                in first.targets.entries)
              (id: id, position: position),
          ],
          span: span,
          direction: 1,
        );
        for (final MapEntry(key: id, value: point) in first.targets.entries) {
          expect(again.targets[id]!.x, closeTo(point.x, 1e-6), reason: id);
          expect(again.targets[id]!.y, closeTo(point.y, 1e-6), reason: id);
        }
      }
    });

    test('is deterministic whatever order the members come in', () {
      final members = _scatter(25);
      final forward = _arrange(members);
      final backward = _arrange(members.reversed.toList());
      expect(backward.targets, forward.targets);
    });

    test('works around any centre, not only the viewer', () {
      const centre = (x: 900.0, y: 3100.0);
      final layout = _arrange(_scatter(9), centre: centre, innerRadius: 250);
      for (final point in layout.targets.values) {
        expect(_radius(point, centre), greaterThanOrEqualTo(250 - 1e-9));
      }
    });

    test('lists the targets that fall outside the bounds', () {
      const bounds = (left: 0.0, top: 1850.0, right: 4096.0, bottom: 4096.0);
      final layout = _arrange(
        _scatter(6),
        innerRadius: 200,
        bounds: bounds,
      );
      // Pointing up from y=2048: everything beyond 248 is above the top.
      expect(layout.outside, isNotEmpty);
      for (final MapEntry(key: id, value: point) in layout.targets.entries) {
        expect(layout.outside.contains(id), point.y < bounds.top);
      }
      expect(_arrange(_scatter(6)).outside, isEmpty);
    });

    test('clamps the width to its limits', () {
      final narrow = _arrange(_scatter(2), span: 0);
      expect(narrow.sweep, kConstellationSectorMinSpan);
      final wide = _arrange(_scatter(2), span: 10);
      expect(wide.sweep, kConstellationSectorMaxSpan);
    });

    test('nothing to arrange gives an empty layout', () {
      final layout = _arrange(const []);
      expect(layout.targets, isEmpty);
      expect(layout.rings, isEmpty);
    });
  });

  test('constellationSectorCentroidDirection points at the middle of the '
      'points', () {
    expect(
      constellationSectorCentroidDirection(
        centre: _centre,
        points: [_polar(0.2, 100), _polar(0.6, 900)],
      ),
      closeTo(0.4, 1e-9),
    );
    expect(
      constellationSectorCentroidDirection(centre: _centre, points: const []),
      -math.pi / 2,
    );
  });
}
