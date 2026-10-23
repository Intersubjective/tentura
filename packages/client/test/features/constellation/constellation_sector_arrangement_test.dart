import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_sector_arrangement.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

// «Arrange in a sector» (#644): the selected nodes go evenly into rings in
// the band of a sector, from its inner radius to its outer one, around any
// centre — equal steps along every ring, rings at equal steps from edge to
// edge, every ring spread over the whole sector — the nearest nodes on the
// inner ring and everyone keeping their order around the centre. The band is
// kept exactly as asked, however tight.

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

/// Arranges [members]; without [outerRadius], in the compact band a new
/// sector starts with.
ConstellationSectorLayout _arrange(
  List<ConstellationSectorMember> members, {
  LPoint centre = _centre,
  double direction = -math.pi / 2,
  double span = math.pi / 2,
  double innerRadius = 300,
  double? outerRadius,
  double minSpacing = _spacing,
  LRect? bounds,
}) => arrangeConstellationSector(
  centre: centre,
  members: members,
  direction: direction,
  span: span,
  innerRadius: innerRadius,
  outerRadius:
      outerRadius ??
      constellationSectorCompactOuterRadius(
        innerRadius: innerRadius,
        span: span,
        count: members.length,
        minSpacing: minSpacing,
      ),
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

double _minDistance(Iterable<LPoint> targets) {
  final points = targets.toList();
  var nearest = double.infinity;
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      nearest = math.min(nearest, _distance(points[i], points[j]));
    }
  }
  return nearest;
}

/// Every target is on a ring of [layout], inside the band and the sector,
/// and every ring's steps are equal and centred in the sector.
void _expectEvenInBand(ConstellationSectorLayout layout, int count) {
  expect(layout.targets, hasLength(count));
  final rings = _byRing(layout);
  expect(
    rings.fold<int>(0, (sum, ring) => sum + ring.length),
    count,
    reason: 'every target is on a ring',
  );
  for (final radius in layout.rings) {
    expect(radius, greaterThanOrEqualTo(layout.inner - 1e-9));
    expect(radius, lessThanOrEqualTo(layout.outer + 1e-9));
  }
  for (final ring in rings) {
    expect(ring, isNotEmpty, reason: 'no empty ring');
    final cell = layout.sweep / ring.length;
    final angles = ring.map(_angle).toList();
    // Counterclockwise distances, so a step of half the circle is one too.
    double turn(double to, double from) => (to - from) % (2 * math.pi);
    expect(turn(angles.first, layout.start), closeTo(cell / 2, 1e-9));
    for (var i = 1; i < angles.length; i++) {
      expect(turn(angles[i], angles[i - 1]), closeTo(cell, 1e-9));
    }
  }
  for (final point in layout.targets.values) {
    final along = (_angle(point) - layout.start) % (2 * math.pi);
    expect(along, lessThanOrEqualTo(layout.sweep + 1e-9));
  }
}

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

  group('constellationSectorCompactOuterRadius', () {
    test('is the last ring when rings a spacing apart fill from the inner '
        'one, each as full as it can be', () {
      var radius = 300.0;
      var left = 40;
      while (true) {
        left -= constellationSectorRingCapacity(
          radius: radius,
          span: math.pi / 2,
          minSpacing: _spacing,
        );
        if (left <= 0) break;
        radius += _spacing;
      }
      expect(
        constellationSectorCompactOuterRadius(
          innerRadius: 300,
          span: math.pi / 2,
          count: 40,
          minSpacing: _spacing,
        ),
        radius,
      );
    });

    test('is the inner radius when one ring holds them all, and never less '
        'than a spacing from the centre', () {
      expect(
        constellationSectorCompactOuterRadius(
          innerRadius: 300,
          span: math.pi / 2,
          count: 3,
          minSpacing: _spacing,
        ),
        300,
      );
      expect(
        constellationSectorCompactOuterRadius(
          innerRadius: 0,
          span: math.pi / 12,
          count: 1,
          minSpacing: _spacing,
        ),
        _spacing,
      );
    });
  });

  group('arrangeConstellationSector', () {
    test('equal radii make one ring: equal steps across the sector, centred '
        'on the direction', () {
      final members = [
        (id: 'a', position: _polar(0.1, 300)),
        (id: 'b', position: _polar(2, 300)),
        (id: 'c', position: _polar(-2.5, 300)),
      ];
      const direction = math.pi / 2;
      final layout = _arrange(
        members,
        direction: direction,
        outerRadius: 300,
      );

      expect(layout.targets.keys, unorderedEquals(['a', 'b', 'c']));
      expect(layout.rings, [300]);
      expect(layout.inner, 300);
      expect(layout.outer, 300);
      expect(layout.sweep, closeTo(math.pi / 2, 1e-12));
      expect(layout.start, closeTo(direction - math.pi / 4, 1e-12));
      final ring = _byRing(layout).single;
      final angles = ring.map(_angle).toList();
      // Three cells of π/6 each, a node in the middle of every cell.
      expect(_diff(angles[0], layout.start), closeTo(math.pi / 12, 1e-9));
      expect(_diff(angles[1], angles[0]), closeTo(math.pi / 6, 1e-9));
      expect(_diff(angles[2], angles[1]), closeTo(math.pi / 6, 1e-9));
      expect(_diff(angles[1], direction), closeTo(0, 1e-9));
    });

    test('an outer radius below the inner one counts as the inner one', () {
      final layout = _arrange(_scatter(3), outerRadius: 100);
      expect(layout.outer, 300);
      expect(layout.rings, [300]);
    });

    test('a band too thin for a second ring holds one ring half way', () {
      final layout = _arrange(_scatter(3), outerRadius: 340);
      expect(layout.rings, [320]);
      _expectEvenInBand(layout, 3);
    });

    test('rings go from the inner edge to the outer one at equal steps, and '
        'share the nodes by their length', () {
      final layout = _arrange(_scatter(60), outerRadius: 1000);
      final rings = layout.rings;
      expect(rings.length, greaterThan(2));
      expect(rings.first, 300);
      expect(rings.last, 1000);
      final step = (1000 - 300) / (rings.length - 1);
      for (var i = 1; i < rings.length; i++) {
        expect(rings[i] - rings[i - 1], closeTo(step, 1e-9));
      }
      final counts = [for (final ring in _byRing(layout)) ring.length];
      final total = rings.fold<double>(0, (sum, r) => sum + r);
      for (var i = 0; i < rings.length; i++) {
        expect(
          counts[i],
          closeTo(60 * rings[i] / total, 1),
          reason: 'ring $i takes its share',
        );
      }
      _expectEvenInBand(layout, 60);
    });

    test('cells come out about as deep as they are wide', () {
      final layout = _arrange(_scatter(100), outerRadius: 1500);
      final rings = layout.rings;
      final depth = (rings.last - rings.first) / (rings.length - 1);
      for (final ring in _byRing(layout)) {
        final width = _distance(ring[0], ring[1]);
        expect(width / depth, inInclusiveRange(0.5, 2));
      }
    });

    test('a wider band spreads the same nodes further apart', () {
      final members = _scatter(30);
      final compact = _arrange(members);
      final wide = _arrange(members, outerRadius: 2000);
      expect(wide.outer, 2000);
      expect(
        _minDistance(wide.targets.values),
        greaterThan(_minDistance(compact.targets.values)),
      );
    });

    test('a band with room for them keeps the nodes a spacing apart', () {
      for (final span in [math.pi / 12, math.pi / 3, math.pi, 2 * math.pi]) {
        for (final count in [2, 7, 30, 64, 200]) {
          for (final inner in [100.0, 300.0]) {
            final layout = _arrange(
              _scatter(count, seed: count),
              span: span,
              innerRadius: inner,
            );
            expect(
              _minDistance(layout.targets.values),
              greaterThanOrEqualTo(_spacing - 1e-6),
              reason: '$count nodes, ${(span * 180 / math.pi).round()}°',
            );
          }
        }
      }
    });

    test('a band too tight for them is kept as it is: the nodes come '
        'closer, even overlap, still evenly', () {
      final layout = _arrange(_scatter(40), innerRadius: 200, outerRadius: 260);
      expect(layout.inner, 200);
      expect(layout.outer, 260);
      expect(_minDistance(layout.targets.values), lessThan(_spacing));
      _expectEvenInBand(layout, 40);

      final single = _arrange(
        _scatter(40),
        innerRadius: 150,
        outerRadius: 150,
        span: math.pi / 12,
      );
      expect(single.rings, [150]);
      _expectEvenInBand(single, 40);
    });

    for (final span in [math.pi / 12, math.pi / 3, math.pi, 2 * math.pi]) {
      for (final count in [1, 2, 7, 30, 64, 200]) {
        for (final (name, inner, outer) in [
          ('one ring', 150.0, 150.0),
          ('tight', 150.0, 220.0),
          ('compact', 150.0, null),
          ('wide', 150.0, 3000.0),
        ]) {
          test('$count nodes, span ${(span * 180 / math.pi).round()}°, '
              '$name band: all inside it and evenly spaced', () {
            final layout = _arrange(
              _scatter(count, seed: count),
              span: span,
              innerRadius: inner,
              outerRadius: outer,
              direction: 2.5,
            );
            expect(layout.inner, inner);
            if (outer != null) expect(layout.outer, outer);
            _expectEvenInBand(layout, count);
            for (final point in layout.targets.values) {
              expect(_radius(point), greaterThanOrEqualTo(inner - 1e-9));
              expect(_radius(point), lessThanOrEqualTo(layout.outer + 1e-9));
            }
          });
        }
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

    test('the radii are kept exactly, even right at the centre', () {
      final layout = _arrange(_scatter(5), innerRadius: 0, outerRadius: 0);
      expect(layout.rings, [0]);
      for (final point in layout.targets.values) {
        expect(_radius(point), closeTo(0, 1e-9));
      }
    });

    test('the nearest go on the inner ring, and each ring keeps the order '
        'around the centre', () {
      final members = [
        (id: 'far-left', position: _polar(-math.pi / 2 - 0.5, 900)),
        (id: 'near-right', position: _polar(-math.pi / 2 + 0.4, 200)),
        (id: 'near-left', position: _polar(-math.pi / 2 - 0.4, 210)),
        (id: 'far-right', position: _polar(-math.pi / 2 + 0.5, 950)),
      ];
      // Two places on each of two rings (r 200 and 300, 60°).
      final layout = _arrange(
        members,
        innerRadius: 200,
        outerRadius: 300,
        span: math.pi / 3,
      );

      expect(layout.rings, [200, 300]);
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
        for (final outer in [null, 320.0, 1500.0]) {
          final first = _arrange(
            _scatter(37),
            span: span,
            direction: 1,
            outerRadius: outer,
          );
          final again = _arrange(
            [
              for (final MapEntry(key: id, value: position)
                  in first.targets.entries)
                (id: id, position: position),
            ],
            span: span,
            direction: 1,
            outerRadius: outer,
          );
          for (final MapEntry(key: id, value: point) in first.targets.entries) {
            expect(again.targets[id]!.x, closeTo(point.x, 1e-6), reason: id);
            expect(again.targets[id]!.y, closeTo(point.y, 1e-6), reason: id);
          }
        }
      }
    });

    test('is deterministic whatever order the members come in', () {
      for (final outer in [null, 320.0, 1500.0]) {
        final members = _scatter(25);
        final forward = _arrange(members, outerRadius: outer);
        final backward = _arrange(
          members.reversed.toList(),
          outerRadius: outer,
        );
        expect(backward.targets, forward.targets);
        expect(backward.rings, forward.rings);
      }
    });

    test('works around any centre, not only the viewer', () {
      const centre = (x: 900.0, y: 3100.0);
      final layout = _arrange(
        _scatter(9),
        centre: centre,
        innerRadius: 250,
        outerRadius: 600,
      );
      for (final point in layout.targets.values) {
        expect(_radius(point, centre), greaterThanOrEqualTo(250 - 1e-9));
        expect(_radius(point, centre), lessThanOrEqualTo(600 + 1e-9));
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
      final layout = _arrange(const [], outerRadius: 500);
      expect(layout.targets, isEmpty);
      expect(layout.rings, isEmpty);
      expect(layout.outer, 500);
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
