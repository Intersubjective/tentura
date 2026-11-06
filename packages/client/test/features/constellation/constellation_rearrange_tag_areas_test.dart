import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_rearrange_all.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

const _ego = 'ego';
const _spacing = 16.0;

ConstellationEdgeRef _e(String src, String dst, int tier) => (
  src: src,
  dst: dst,
  tier: tier,
);

ConstellationPathResolution _starPaths(Iterable<String> leaves) {
  final peers = {...leaves, _ego};
  return resolveConstellationPaths(
    egoId: _ego,
    visiblePeerIds: peers,
    holderIds: peers,
    edges: [for (final id in leaves) _e(_ego, id, 1)],
  );
}

ConstellationPoint _centroid(Iterable<ConstellationPoint> pts) {
  final list = pts.toList();
  assert(list.isNotEmpty, 'centroid needs points');
  final sx = list.map((p) => p.x).reduce((a, b) => a + b);
  final sy = list.map((p) => p.y).reduce((a, b) => a + b);
  final n = list.length;
  return (x: sx / n, y: sy / n);
}

double _dist(ConstellationPoint a, ConstellationPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Closest point on segment ab to p, and distance from p to that point.
(double t, double dist) _segmentProjection(
  ConstellationPoint p,
  ConstellationPoint a,
  ConstellationPoint b,
) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final apx = p.x - a.x;
  final apy = p.y - a.y;
  final ab2 = abx * abx + aby * aby;
  final t = ab2 < 1e-12 ? 0.0 : ((apx * abx + apy * aby) / ab2).clamp(0.0, 1.0);
  final q = (x: a.x + t * abx, y: a.y + t * aby);
  return (t, _dist(p, q));
}

void main() {
  group('computeConstellationRearrangeAll tag areas', () {
    test('two tags, ten people each: separation, radii, dual-tag segment', () {
      final tagA = List<String>.generate(10, (i) => 'a$i');
      final tagB = List<String>.generate(10, (i) => 'b$i');
      const dual = 'dual';
      final everyone = {...tagA, ...tagB, dual};
      final membersA = [...tagA, dual];
      final membersB = [...tagB, dual];
      final paths = _starPaths(everyone);
      const nodeSize = (width: 64.0, height: 64.0);
      final nodeSizes = <String, ConstellationSize>{
        for (final id in everyone) id: nodeSize,
        _ego: nodeSize,
      };
      final input = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: everyone,
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
        rearrangeOwnTagPeopleByTagId: {
          't1': membersA.toSet(),
          't2': membersB.toSet(),
        },
        rearrangeTagMagnetsByTagId: const <String, ConstellationPoint>{},
      );

      final once = computeConstellationRearrangeAll(input);
      final twice = computeConstellationRearrangeAll(input);
      expect(twice.layout.positions, once.layout.positions);

      final pos = once.layout.positions;
      final cA = once.tagCentres['t1']!;
      final cB = once.tagCentres['t2']!;

      final cell = math.max(nodeSize.width, nodeSize.height) + _spacing;
      final boundA = 2.5 * math.sqrt(membersA.length) * cell + 1.0;
      final boundB = 2.5 * math.sqrt(membersB.length) * cell + 1.0;
      for (final id in membersA) {
        expect(_dist(pos[id]!, cA), lessThanOrEqualTo(boundA));
      }
      for (final id in membersB) {
        expect(_dist(pos[id]!, cB), lessThanOrEqualTo(boundB));
      }
      for (final id in tagA) {
        expect(_dist(pos[id]!, cA), lessThan(_dist(pos[id]!, cB)));
      }
      for (final id in tagB) {
        expect(_dist(pos[id]!, cB), lessThan(_dist(pos[id]!, cA)));
      }

      final proj = _segmentProjection(pos[dual]!, cA, cB);
      expect(
        proj.$2,
        lessThanOrEqualTo(math.max(nodeSize.width, nodeSize.height)),
      );

      for (final MapEntry(:key, :value) in once.pinned.entries) {
        expect(pos[key], value);
      }
    });

    test('untagged people keep no-tag positions when outside tag disks', () {
      final tagPeople = ['t0'];
      const untagged = 'u0';
      final everyone = {...tagPeople, untagged};
      final paths = _starPaths(everyone);
      const nodeSize = (width: 48.0, height: 48.0);
      final nodeSizes = <String, ConstellationSize>{
        for (final id in everyone) id: nodeSize,
        _ego: nodeSize,
      };
      final plain = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: everyone,
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
        rearrangeOwnTagPeopleByTagId: const <String, Set<String>>{},
        rearrangeTagMagnetsByTagId: const <String, ConstellationPoint>{},
      );
      final loose = computeConstellationRearrangeAll(plain);
      final taggedInput = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: everyone,
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
        rearrangeOwnTagPeopleByTagId: {
          'tg': tagPeople.toSet(),
        },
        rearrangeTagMagnetsByTagId: const <String, ConstellationPoint>{},
      );
      final tagged = computeConstellationRearrangeAll(taggedInput);
      expect(
        tagged.layout.positions[untagged],
        loose.layout.positions[untagged],
      );
    });

    test('magnet tag: member centroid near magnet', () {
      final members = List<String>.generate(6, (i) => 'm$i');
      final paths = _starPaths(members);
      const nodeSize = (width: 64.0, height: 64.0);
      final nodeSizes = <String, ConstellationSize>{
        for (final id in members) id: nodeSize,
        _ego: nodeSize,
      };
      final magnet = constellationCanvasCentrePoint();
      final input = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: members.toSet(),
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
        rearrangeOwnTagPeopleByTagId: {
          'tm': members.toSet(),
        },
        rearrangeTagMagnetsByTagId: {
          'tm': magnet,
        },
      );
      final layout = computeConstellationRearrangeAll(input);
      final c = _centroid([
        for (final id in members) layout.layout.positions[id]!,
      ]);
      expect(_dist(c, layout.tagCentres['tm']!), lessThanOrEqualTo(64));
    });

    test('automatic tag ids do not form an area', () {
      final people = {'p1', 'p2'};
      final paths = _starPaths(people);
      const nodeSize = (width: 64.0, height: 64.0);
      final nodeSizes = <String, ConstellationSize>{
        for (final id in people) id: nodeSize,
        _ego: nodeSize,
      };
      final input = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: people,
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
        rearrangeOwnTagPeopleByTagId: {
          'auto:mutualContact': people,
        },
        rearrangeTagMagnetsByTagId: const <String, ConstellationPoint>{},
      );
      final noTag = computeConstellationRearrangeAll((
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: people,
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: nodeSizes,
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: _spacing,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
        rearrangeOwnTagPeopleByTagId: const <String, Set<String>>{},
        rearrangeTagMagnetsByTagId: const <String, ConstellationPoint>{},
      ));
      final withAuto = computeConstellationRearrangeAll(input);
      expect(withAuto.layout.positions, noTag.layout.positions);
    });
  });
}
