import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_sector_arrangement.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

// «Arrange in a sector» (#644): the selected people go evenly along an arc
// around the viewer, centred on the chosen direction, each at their own
// distance (distance band).

const LPoint _centre = (x: 2048, y: 2048);

LPoint _polar(double angle, double radius) => (
  x: _centre.x + math.cos(angle) * radius,
  y: _centre.y + math.sin(angle) * radius,
);

double _radius(LPoint p) => math.sqrt(
  math.pow(p.x - _centre.x, 2) + math.pow(p.y - _centre.y, 2),
);

double _angle(LPoint p) => math.atan2(p.y - _centre.y, p.x - _centre.x);

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

void main() {
  group('arrangeConstellationSector', () {
    test('spaces people evenly across the sector, centred on the '
        'direction', () {
      final members = [
        (id: 'a', position: _polar(0.1, 300)),
        (id: 'b', position: _polar(2, 300)),
        (id: 'c', position: _polar(-2.5, 300)),
      ];
      const direction = math.pi / 2;
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: members,
        direction: direction,
        span: math.pi / 2,
        minSpacing: 10,
      );

      final angles = layout.targets.values.map(_angle).toList()
        ..sort((a, b) => _diff(a, b).sign.toInt());
      expect(layout.targets.keys, unorderedEquals(['a', 'b', 'c']));
      expect(layout.sweep, closeTo(math.pi / 2, 1e-9));
      expect(layout.start, closeTo(direction - math.pi / 4, 1e-9));
      final gaps = [
        _diff(angles[1], angles[0]),
        _diff(angles[2], angles[1]),
      ];
      expect(gaps[0], closeTo(math.pi / 4, 1e-9));
      expect(gaps[1], closeTo(math.pi / 4, 1e-9));
      // The middle person sits on the chosen direction.
      expect(_diff(angles[1], direction), closeTo(0, 1e-9));
    });

    test('keeps each person at their own distance', () {
      final members = [
        (id: 'near', position: _polar(0, 200)),
        (id: 'mid', position: _polar(1, 400)),
        (id: 'far', position: _polar(2, 900)),
      ];
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: members,
        direction: -1,
        span: math.pi / 3,
        minSpacing: 10,
      );

      expect(_radius(layout.targets['near']!), closeTo(200, 1e-6));
      expect(_radius(layout.targets['mid']!), closeTo(400, 1e-6));
      expect(_radius(layout.targets['far']!), closeTo(900, 1e-6));
    });

    test('moves a person sitting on the viewer out to the minimum radius', () {
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: [
          (id: 'on-me', position: _centre),
          (id: 'b', position: _polar(0, 500)),
        ],
        direction: 0,
        span: math.pi / 2,
        minSpacing: 10,
        minRadius: 170,
      );

      expect(_radius(layout.targets['on-me']!), closeTo(170, 1e-6));
      expect(_radius(layout.targets['b']!), closeTo(500, 1e-6));
    });

    test('keeps the people in their current order around the viewer', () {
      // Already on the right of the direction stays on the right.
      const direction = 0.0;
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: [
          (id: 'left', position: _polar(-1.2, 300)),
          (id: 'middle', position: _polar(0.1, 300)),
          (id: 'right', position: _polar(1.4, 300)),
        ],
        direction: direction,
        span: math.pi / 2,
        minSpacing: 10,
      );

      final left = _angle(layout.targets['left']!);
      final middle = _angle(layout.targets['middle']!);
      final right = _angle(layout.targets['right']!);
      expect(left, lessThan(middle));
      expect(middle, lessThan(right));
    });

    test('the direction turns the whole sector', () {
      final members = [
        (id: 'a', position: _polar(0, 300)),
        (id: 'b', position: _polar(0.5, 300)),
      ];
      for (final direction in [0.0, math.pi / 2, math.pi, -math.pi / 2]) {
        final layout = arrangeConstellationSector(
          centre: _centre,
          members: members,
          direction: direction,
          span: math.pi / 3,
          minSpacing: 10,
        );
        final mean = constellationSectorCentroidDirection(
          centre: _centre,
          points: layout.targets.values,
        );
        expect(_diff(mean, direction), closeTo(0, 1e-9), reason: '$direction');
      }
    });

    test('widens a sector too narrow for the people to keep them apart', () {
      final members = [
        for (var i = 0; i < 6; i++) (id: 'p$i', position: _polar(i * 0.1, 300)),
      ];
      const minSpacing = 150.0;
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: members,
        direction: 0,
        span: math.pi / 6,
        minSpacing: minSpacing,
      );

      final points = layout.targets.values.toList()
        ..sort((a, b) => _angle(a).compareTo(_angle(b)));
      for (var i = 1; i < points.length; i++) {
        final chord = math.sqrt(
          math.pow(points[i].x - points[i - 1].x, 2) +
              math.pow(points[i].y - points[i - 1].y, 2),
        );
        expect(chord, greaterThanOrEqualTo(minSpacing - 1e-6));
      }
      expect(layout.sweep, greaterThan(math.pi / 6));
    });

    test('many people go evenly around the whole circle at most', () {
      final members = [
        for (var i = 0; i < 64; i++)
          (
            id: 'p${i.toString().padLeft(2, '0')}',
            position: _polar(i * 0.05, 400),
          ),
      ];
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: members,
        direction: 1,
        span: math.pi / 2,
        minSpacing: 140,
      );

      expect(layout.targets, hasLength(64));
      expect(layout.sweep, closeTo(2 * math.pi * 63 / 64, 1e-9));
      final angles = layout.targets.values.map(_angle).toList()..sort();
      for (var i = 1; i < angles.length; i++) {
        expect(angles[i] - angles[i - 1], closeTo(2 * math.pi / 64, 1e-6));
      }
      // No two people on the same spot.
      final distinct = {
        for (final p in layout.targets.values)
          '${p.x.toStringAsFixed(3)},${p.y.toStringAsFixed(3)}',
      };
      expect(distinct, hasLength(64));
    });

    test('pulls targets back into the stored-position envelope', () {
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: [
          // A far corner: its distance exceeds the envelope on an axis.
          (id: 'corner', position: (x: _centre.x + 1600, y: _centre.y + 1600)),
          (id: 'b', position: _polar(0, 300)),
        ],
        direction: 0,
        span: math.pi / 6,
        minSpacing: 10,
        maxAxisOffset: 1700,
      );

      for (final target in layout.targets.values) {
        expect((target.x - _centre.x).abs(), lessThanOrEqualTo(1700));
        expect((target.y - _centre.y).abs(), lessThanOrEqualTo(1700));
      }
    });

    test('nobody to arrange gives nothing', () {
      final layout = arrangeConstellationSector(
        centre: _centre,
        members: const [],
        direction: 0,
        span: math.pi,
        minSpacing: 10,
      );
      expect(layout.targets, isEmpty);
      expect(layout.sweep, 0);
    });
  });

  group('constellationSectorStep', () {
    test('splits the span between neighbours', () {
      expect(
        constellationSectorStep(
          count: 5,
          span: math.pi,
          minSpacing: 0,
          nearestRadius: 300,
        ),
        closeTo(math.pi / 4, 1e-12),
      );
    });

    test('a single person needs no step', () {
      expect(
        constellationSectorStep(
          count: 1,
          span: math.pi,
          minSpacing: 100,
          nearestRadius: 300,
        ),
        0,
      );
    });

    test('a full-circle span never puts the ends on top of each other', () {
      expect(
        constellationSectorStep(
          count: 4,
          span: 2 * math.pi,
          minSpacing: 0,
          nearestRadius: 300,
        ),
        closeTo(math.pi / 2, 1e-12),
      );
    });
  });

  group('constellationSectorCentroidDirection', () {
    test('points at the middle of the people by direction, not distance', () {
      final direction = constellationSectorCentroidDirection(
        centre: _centre,
        points: [_polar(0, 100), _polar(math.pi / 2, 5000)],
      );
      expect(direction, closeTo(math.pi / 4, 1e-9));
    });

    test('falls back when the people cancel out', () {
      final direction = constellationSectorCentroidDirection(
        centre: _centre,
        points: [_polar(0, 100), _polar(math.pi, 100)],
        fallback: 1.5,
      );
      expect(direction, 1.5);
    });
  });
}
