import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_tag_view_layout.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_tag_view_scene_layout.dart';

/// The tag view lays out the members of one or more tags around the viewer
/// without any pins: the same data always gives the same positions, a small
/// tag keeps each person's Field direction with the radial gaps closed, a big
/// tag falls back to rings by trust depth, and a person in two tags sits
/// between the two clusters.

const LPoint _ego = (x: 0, y: 0);
const _unit = kConstellationRingUnitPixels;

TagViewPerson _person(
  String id, {
  required double angle,
  required int depth,
  Set<String> tags = const {'a'},
}) => (id: id, angle: angle, depth: depth, tagIds: tags);

double _distance(LPoint a, LPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

double _radius(LPoint p) => _distance(p, _ego);

double _angleOf(LPoint p) => math.atan2(p.y - _ego.y, p.x - _ego.x);

double _angleGap(double a, double b) {
  final d = (a - b) % (2 * math.pi);
  return math.min(d, 2 * math.pi - d);
}

Map<String, LPoint> _layout(
  List<TagViewPerson> people, {
  List<String> tagIds = const ['a'],
}) => computeConstellationTagViewLayout(
  ego: _ego,
  tagIds: tagIds,
  people: people,
).positions;

List<TagViewPerson> _smallTag() => [
  _person('p1', angle: -2.4, depth: 1),
  _person('p2', angle: -1.0, depth: 4),
  _person('p3', angle: 0.3, depth: 1),
  _person('p4', angle: 1.2, depth: 4),
  _person('p5', angle: 2.5, depth: 7),
];

List<TagViewPerson> _bigTag(int count) => [
  for (var i = 0; i < count; i++)
    _person(
      'q$i',
      angle: -math.pi + (i * 2 * math.pi / count),
      depth: 1 + i % 4,
    ),
];

void main() {
  group('Tag view layout', () {
    test('same tag data gives identical positions on every run', () {
      final people = _smallTag();
      expect(_layout(people), equals(_layout(people)));
    });

    test('input order of the members does not change the positions', () {
      final people = _smallTag();
      expect(
        _layout(people.reversed.toList()),
        equals(_layout(people)),
      );
    });

    test('up to 30 people keep their Field direction within tolerance', () {
      final people = _smallTag();
      final positions = _layout(people);
      for (final p in people) {
        expect(positions, contains(p.id));
        expect(
          _angleGap(_angleOf(positions[p.id]!), p.angle),
          lessThan(0.3),
          reason: '${p.id} drifted from its Field direction',
        );
      }
    });

    test('up to 30 people close radial gaps between occupied depths', () {
      final people = _smallTag(); // depths 1, 4, 7
      final positions = _layout(people);
      final radii = {
        for (final p in people) p.depth: _radius(positions[p.id]!),
      };
      expect(radii[4]! - radii[1]!, lessThanOrEqualTo(1.5 * _unit));
      expect(radii[7]! - radii[4]!, lessThanOrEqualTo(1.5 * _unit));
      expect(radii[1]!, lessThan(radii[4]!));
      expect(radii[4]!, lessThan(radii[7]!));
    });

    test('exactly 30 people still use Field directions, not rings', () {
      final people = _bigTag(30);
      final positions = _layout(people);
      for (final p in people) {
        expect(
          _angleGap(_angleOf(positions[p.id]!), p.angle),
          lessThan(0.3),
        );
      }
    });

    test('more than 30 people sit on one ring per trust depth', () {
      final people = _bigTag(40);
      final positions = _layout(people);
      final byDepth = <int, List<double>>{};
      for (final p in people) {
        byDepth.putIfAbsent(p.depth, () => []).add(_radius(positions[p.id]!));
      }
      expect(byDepth.keys, hasLength(4));
      for (final radii in byDepth.values) {
        for (final r in radii) {
          expect(r, closeTo(radii.first, 1e-6));
        }
      }
      final ordered = [for (final d in byDepth.keys.toList()..sort()) byDepth[d]!.first];
      for (var i = 1; i < ordered.length; i++) {
        expect(ordered[i], greaterThan(ordered[i - 1]));
      }
    });

    test('a person in two tags lies between both cluster centres', () {
      final people = [
        _person('a1', angle: -0.3, depth: 2),
        _person('a2', angle: 0.3, depth: 3),
        _person('b1', angle: math.pi - 0.3, depth: 2),
        _person('b2', angle: math.pi + 0.3, depth: 3),
        _person('both', angle: math.pi / 2, depth: 2, tags: {'a', 'b'}),
      ];
      // 'a' / 'b' membership for the single-tag people.
      final tagged = [
        for (final p in people)
          if (p.id.startsWith('a'))
            _person(p.id, angle: p.angle, depth: p.depth, tags: {'a'})
          else if (p.id.startsWith('b'))
            _person(p.id, angle: p.angle, depth: p.depth, tags: {'b'})
          else
            p,
      ];
      final result = computeConstellationTagViewLayout(
        ego: _ego,
        tagIds: const ['a', 'b'],
        people: tagged,
      );
      final centreA = result.clusterCentres['a']!;
      final centreB = result.clusterCentres['b']!;
      final both = result.positions['both']!;
      final apart = _distance(centreA, centreB);
      expect(apart, greaterThan(0));
      expect(_distance(both, centreA), lessThan(apart));
      expect(_distance(both, centreB), lessThan(apart));
      expect(
        (_distance(both, centreA) - _distance(both, centreB)).abs(),
        lessThan(apart / 2),
        reason: 'shared person should not hug one cluster',
      );
      // Single-tag people stay with their own cluster.
      expect(
        _distance(result.positions['a1']!, centreA),
        lessThan(_distance(result.positions['a1']!, centreB)),
      );
      expect(
        _distance(result.positions['b1']!, centreB),
        lessThan(_distance(result.positions['b1']!, centreA)),
      );
    });

    test('layout leaves its input untouched and persists nothing', () {
      final people = _smallTag();
      final before = [for (final p in people) (p.id, p.angle, p.depth, ([...p.tagIds]..sort()).join(','))];
      final result = computeConstellationTagViewLayout(
        ego: _ego,
        tagIds: const ['a'],
        people: people,
      );
      expect(
        [for (final p in people) (p.id, p.angle, p.depth, ([...p.tagIds]..sort()).join(','))],
        equals(before),
      );
      expect(result.positions.keys, unorderedEquals(['p1', 'p2', 'p3', 'p4', 'p5']));
    });

    test('as a scene layout it completes with a terminal frame of the same positions', () async {
      final people = _smallTag();
      final algorithm = ConstellationTagViewSceneLayoutAlgorithm(
        tagIds: const ['a'],
        people: people,
      );
      final request = GraphLayoutRequest(
        ticket: mintGraphLayoutTicket(
          owner: Object(),
          topologyRevision: 1,
          generation: 1,
        ),
        canvasSize: SceneSize(width: 500, height: 500),
        nodesById: {
          for (final p in people)
            p.id: GraphLayoutNode(
              id: p.id,
              size: SceneSize(width: 40, height: 40),
            ),
        },
        edgesById: const {},
      );
      final frames = await algorithm.layout(request).toList();
      expect(frames, isNotEmpty);
      final last = frames.last;
      expect(last.isTerminal, isTrue);
      expect(last.positions.keys, unorderedEquals(request.nodeIds));
      final pure = _layout(people);
      final frame = last.positions;
      final centre = frame['p1']!;
      // Frame is the pure layout up to one common translation.
      for (final p in people) {
        expect(
          frame[p.id]!.x - centre.x,
          closeTo(pure[p.id]!.x - pure['p1']!.x, 1e-6),
        );
        expect(
          frame[p.id]!.y - centre.y,
          closeTo(pure[p.id]!.y - pure['p1']!.y, 1e-6),
        );
      }
    });
  });
}
