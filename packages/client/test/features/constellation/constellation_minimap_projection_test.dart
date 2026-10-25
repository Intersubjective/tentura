import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_minimap.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

const _people = <LPoint>[
  (x: -1200, y: 300),
  (x: 800, y: 250),
  (x: 300, y: -900),
  (x: 1500, y: 1100),
  (x: 0, y: 0),
];

void main() {
  group('minimap projection', () {
    test('is 104 points square', () {
      expect(kConstellationMinimapSize, 104);
    });

    test('puts every person inside the minimap square', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      for (final person in _people) {
        final dot = projection.worldToMinimap(person);
        expect(dot.x, inInclusiveRange(0, kConstellationMinimapSize));
        expect(dot.y, inInclusiveRange(0, kConstellationMinimapSize));
      }
    });

    test('uses the whole square along the longer side of the field', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      final dots = [for (final p in _people) projection.worldToMinimap(p)];
      final width =
          dots.map((d) => d.x).reduce((a, b) => a > b ? a : b) -
          dots.map((d) => d.x).reduce((a, b) => a < b ? a : b);
      final height =
          dots.map((d) => d.y).reduce((a, b) => a > b ? a : b) -
          dots.map((d) => d.y).reduce((a, b) => a < b ? a : b);
      final longer = width > height ? width : height;
      expect(longer, greaterThan(kConstellationMinimapSize * 0.8));
    });

    test('keeps the aspect ratio: one scale for both axes', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      final a = projection.worldToMinimap((x: 0, y: 0));
      final b = projection.worldToMinimap((x: 400, y: 400));
      expect(b.x - a.x, closeTo(b.y - a.y, 1e-9));
      expect(b.x - a.x, greaterThan(0));
    });

    test('keeps left/right and up/down order of people', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      final west = projection.worldToMinimap(_people[0]);
      final east = projection.worldToMinimap(_people[3]);
      final north = projection.worldToMinimap(_people[2]);
      final south = projection.worldToMinimap(_people[3]);
      expect(west.x, lessThan(east.x));
      expect(north.y, lessThan(south.y));
    });

    test('converts a minimap point back to the world point it shows', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      for (final person in _people) {
        final back = projection.minimapToWorld(
          projection.worldToMinimap(person),
        );
        expect(back.x, closeTo(person.x, 1e-6));
        expect(back.y, closeTo(person.y, 1e-6));
      }
      const tap = (x: 52.0, y: 13.0);
      final world = projection.minimapToWorld(tap);
      final again = projection.worldToMinimap(world);
      expect(again.x, closeTo(tap.x, 1e-6));
      expect(again.y, closeTo(tap.y, 1e-6));
    });

    test('ignores the order the people are listed in', () {
      final a = ConstellationMinimapProjection.fromPoints(_people);
      final b = ConstellationMinimapProjection.fromPoints(_people.reversed);
      for (final person in _people) {
        final da = a.worldToMinimap(person);
        final db = b.worldToMinimap(person);
        expect(da.x, closeTo(db.x, 1e-9));
        expect(da.y, closeTo(db.y, 1e-9));
      }
    });

    test('maps the camera viewport rectangle corner by corner', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      const viewport = (left: -300.0, top: -200.0, right: 500.0, bottom: 400.0);
      final frame = projection.frameOf(viewport);
      final topLeft = projection.worldToMinimap(
        (x: viewport.left, y: viewport.top),
      );
      final bottomRight = projection.worldToMinimap(
        (x: viewport.right, y: viewport.bottom),
      );
      expect(frame.left, closeTo(topLeft.x, 1e-9));
      expect(frame.top, closeTo(topLeft.y, 1e-9));
      expect(frame.right, closeTo(bottomRight.x, 1e-9));
      expect(frame.bottom, closeTo(bottomRight.y, 1e-9));
    });

    test('clamps the frame to the minimap square when the camera shows more '
        'than the field', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      final frame = projection.frameOf((
        left: -9000.0,
        top: -9000.0,
        right: 9000.0,
        bottom: 9000.0,
      ));
      expect(frame.left, 0);
      expect(frame.top, 0);
      expect(frame.right, kConstellationMinimapSize);
      expect(frame.bottom, kConstellationMinimapSize);
    });

    test('clamps only the side of the frame that overhangs the field', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      final frame = projection.frameOf((
        left: 1000.0,
        top: 800.0,
        right: 9000.0,
        bottom: 9000.0,
      ));
      final inside = projection.worldToMinimap((x: 1000, y: 800));
      expect(frame.left, closeTo(inside.x, 1e-9));
      expect(frame.top, closeTo(inside.y, 1e-9));
      expect(frame.right, kConstellationMinimapSize);
      expect(frame.bottom, kConstellationMinimapSize);
    });

    test('never leaves the minimap square, even for a far-away camera', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      for (final shift in [-50000.0, 50000.0]) {
        final frame = projection.frameOf((
          left: shift,
          top: shift,
          right: shift + 800,
          bottom: shift + 600,
        ));
        expect(frame.left, inInclusiveRange(0, kConstellationMinimapSize));
        expect(frame.top, inInclusiveRange(0, kConstellationMinimapSize));
        expect(
          frame.right,
          inInclusiveRange(frame.left, kConstellationMinimapSize),
        );
        expect(
          frame.bottom,
          inInclusiveRange(frame.top, kConstellationMinimapSize),
        );
      }
    });

    test('frame follows a pan and shrinks on zoom in', () {
      final projection = ConstellationMinimapProjection.fromPoints(_people);
      const viewport = (left: -400.0, top: -300.0, right: 400.0, bottom: 300.0);
      const panned = (left: 100.0, top: -300.0, right: 900.0, bottom: 300.0);
      const zoomed = (left: -200.0, top: -150.0, right: 200.0, bottom: 150.0);
      final base = projection.frameOf(viewport);
      final moved = projection.frameOf(panned);
      final closer = projection.frameOf(zoomed);
      expect(moved.left, greaterThan(base.left));
      expect(moved.right - moved.left, closeTo(base.right - base.left, 1e-9));
      expect(
        closer.right - closer.left,
        closeTo((base.right - base.left) / 2, 1e-9),
      );
      expect(
        closer.bottom - closer.top,
        closeTo((base.bottom - base.top) / 2, 1e-9),
      );
    });

    test('copes with no people and with one person', () {
      for (final points in [
        const <LPoint>[],
        const [(x: 40.0, y: -70.0)],
      ]) {
        final projection = ConstellationMinimapProjection.fromPoints(points);
        const tap = (x: 30.0, y: 80.0);
        final world = projection.minimapToWorld(tap);
        expect(world.x.isFinite && world.y.isFinite, isTrue);
        final back = projection.worldToMinimap(world);
        expect(back.x, closeTo(tap.x, 1e-6));
        expect(back.y, closeTo(tap.y, 1e-6));
      }
      final single = ConstellationMinimapProjection.fromPoints(const [
        (x: 40.0, y: -70.0),
      ]).worldToMinimap((x: 40, y: -70));
      expect(single.x, inInclusiveRange(0, kConstellationMinimapSize));
      expect(single.y, inInclusiveRange(0, kConstellationMinimapSize));
    });
  });
}
