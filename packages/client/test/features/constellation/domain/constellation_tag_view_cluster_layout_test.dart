import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_tag_view_cluster_layout.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

const LPoint _ego = (x: 0, y: 0);
const _unit = kConstellationRingUnitPixels;

TagViewPerson _person(
  String id, {
  required double angle,
  required int depth,
  Set<String> tags = const {'a'},
}) => (id: id, angle: angle, depth: depth, tagIds: tags);

LPoint _polar(LPoint ego, double angle, double radius) => (
  x: ego.x + radius * math.cos(angle),
  y: ego.y + radius * math.sin(angle),
);

LPoint _expectedCentre(
  List<TagViewPerson> members,
  double Function(int depth) ringRadius,
) {
  var sx = 0.0;
  var sy = 0.0;
  var radius = 0.0;
  for (final p in members) {
    sx += math.cos(p.angle);
    sy += math.sin(p.angle);
    radius += ringRadius(p.depth);
  }
  final angle = (sx.abs() < 1e-9 && sy.abs() < 1e-9) ? 0.0 : math.atan2(sy, sx);
  return _polar(_ego, angle, radius / members.length);
}

void main() {
  group('computeConstellationTagViewClusterLayout', () {
    double ringRadius(int depth) => depth * _unit;

    test('each tag centre is the mean direction and radius of its members', () {
      final people = [
        _person('p1', angle: -0.5, depth: 2, tags: {'t1'}),
        _person('p2', angle: 0.5, depth: 4, tags: {'t1'}),
        _person('p3', angle: math.pi, depth: 1, tags: {'t2'}),
      ]..sort((a, b) => a.id.compareTo(b.id));
      final result = computeConstellationTagViewClusterLayout(
        ego: _ego,
        tagIds: const ['t1', 't2'],
        sortedPeople: people,
        ringRadius: ringRadius,
      );
      final t1Members = people.where((p) => p.tagIds.contains('t1')).toList();
      expect(
        result.clusterCentres['t1'],
        equals(_expectedCentre(t1Members, ringRadius)),
      );
      expect(
        result.clusterCentres['t2'],
        equals(_expectedCentre([people[2]], ringRadius)),
      );
    });

    test('a person in two tags sits at the midpoint of the tag centres', () {
      final people = [
        _person('a1', angle: -0.3, depth: 2, tags: {'a'}),
        _person('a2', angle: 0.3, depth: 3, tags: {'a'}),
        _person('b1', angle: math.pi - 0.3, depth: 2, tags: {'b'}),
        _person('b2', angle: math.pi + 0.3, depth: 3, tags: {'b'}),
        _person('both', angle: math.pi / 2, depth: 2, tags: {'a', 'b'}),
      ]..sort((a, b) => a.id.compareTo(b.id));
      final result = computeConstellationTagViewClusterLayout(
        ego: _ego,
        tagIds: const ['a', 'b'],
        sortedPeople: people,
        ringRadius: ringRadius,
      );
      final centreA = result.clusterCentres['a']!;
      final centreB = result.clusterCentres['b']!;
      final both = result.positions['both']!;
      expect(both.x, closeTo((centreA.x + centreB.x) / 2, 1e-9));
      expect(both.y, closeTo((centreA.y + centreB.y) / 2, 1e-9));
    });

    test('the same input twice gives identical output', () {
      final people = [
        _person('x', angle: 1, depth: 2, tags: {'a', 'b'}),
        _person('y', angle: -1, depth: 3, tags: {'a'}),
      ]..sort((a, b) => a.id.compareTo(b.id));
      TagViewClusterLayout run() => computeConstellationTagViewClusterLayout(
        ego: _ego,
        tagIds: const ['a', 'b'],
        sortedPeople: people,
        ringRadius: ringRadius,
      );
      final first = run();
      final second = run();
      expect(second.positions, equals(first.positions));
      expect(second.clusterCentres, equals(first.clusterCentres));
    });
  });
}
