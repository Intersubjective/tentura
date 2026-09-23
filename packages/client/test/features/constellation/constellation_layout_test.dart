import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/constellation_cap_policy.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

const _ego = 'ego';
const _ringGap = kConstellationRingUnitPixels;
const _satelliteOffset = 56.0;
const _epsilon = 1.0;

ConstellationEdgeRef _edge(String src, String dst, int tier) => (
  src: src,
  dst: dst,
  tier: tier,
);

ConstellationPoint _centre() => constellationCanvasCentrePoint();

double _distFromCentre(ConstellationPoint position) {
  final centre = _centre();
  final dx = position.x - centre.x;
  final dy = position.y - centre.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _distance(ConstellationPoint a, ConstellationPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

ConstellationPathResolution _paths({
  Set<String> visiblePeerIds = const {},
  Set<String> holderIds = const {},
  Iterable<ConstellationEdgeRef> edges = const [],
  int maxHops = 3,
}) {
  return resolveConstellationPaths(
    egoId: _ego,
    visiblePeerIds: visiblePeerIds,
    holderIds: holderIds,
    edges: edges,
    maxHops: maxHops,
  );
}

ConstellationLayout _layout({
  required ConstellationPathResolution paths,
  Set<String> keptPeerIds = const {},
  Map<String, List<String>> visibleRequestsByAuthor = const {},
  Set<String> egoOwnRequestIds = const {},
  int maxHops = 3,
  double ringGap = _ringGap,
  double residualRingFactor = 1.6,
  double satelliteOffset = _satelliteOffset,
}) {
  return computeConstellationLayout(
    egoId: _ego,
    paths: paths,
    keptPeerIds: keptPeerIds,
    visibleRequestsByAuthor: visibleRequestsByAuthor,
    egoOwnRequestIds: egoOwnRequestIds,
    maxHops: maxHops,
    ringGap: ringGap,
    residualRingFactor: residualRingFactor,
    satelliteOffset: satelliteOffset,
  );
}

Map<String, ConstellationPoint> _personPositions(ConstellationLayout layout) {
  return Map<String, ConstellationPoint>.from(layout.positions)
    ..removeWhere((id, _) => id.startsWith('req'));
}

void main() {
  group('computeConstellationLayout', () {
    test('rings: depth-2, residual ring, and satellite radii [R10]', () {
      final paths = _paths(
        visiblePeerIds: {'a', 'b', 'q', 'r'},
        holderIds: {'b', 'r'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'b', 1),
          _edge('b', 'q', 1),
          _edge(_ego, 'q', 2),
          _edge('q', 'r', 2),
        ],
      );
      expect(paths.ring, {'r'});
      final kept = {'a', 'b', 'r'};

      final layout = _layout(
        paths: paths,
        keptPeerIds: kept,
        visibleRequestsByAuthor: {'b': ['req-b1']},
      );

      final bPos = layout.positions['b']!;
      expect(_distFromCentre(bPos), closeTo(2 * _ringGap, _epsilon));
      expect(layout.ring['b'], 2);

      final rPos = layout.positions['r']!;
      expect(_distFromCentre(rPos), greaterThan(3 * _ringGap));
      expect(layout.ring['r'], 4);

      final reqPos = layout.positions['req-b1']!;
      // Obstacle-aware placement (R04a): may sit farther than fan radius to clear author.
      expect(_distance(reqPos, bPos), greaterThan(_satelliteOffset));
    });

    test('satellite stability: extra satellites do not move people [R9]', () {
      final paths = _paths(
        visiblePeerIds: {'a', 'h'},
        holderIds: {'h'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'h', 1),
        ],
      );
      final kept = {'a', 'h'};

      final before = _layout(
        paths: paths,
        keptPeerIds: kept,
        visibleRequestsByAuthor: {'h': ['req-1']},
      );
      final after = _layout(
        paths: paths,
        keptPeerIds: kept,
        visibleRequestsByAuthor: {'h': ['req-1', 'req-2', 'req-3']},
      );

      expect(_personPositions(after), _personPositions(before));
    });

    test(
      'satellite stability boundary: first request may move people when holder status changes',
      () {
        final edges = [
          _edge(_ego, 'a', 1),
          _edge('a', 'h', 1),
        ];
        final pathsNoHolder = _paths(
          visiblePeerIds: {'a', 'h'},
          holderIds: {},
          edges: edges,
        );
        final pathsWithHolder = _paths(
          visiblePeerIds: {'a', 'h'},
          holderIds: {'h'},
          edges: edges,
        );

        final before = _layout(
          paths: pathsNoHolder,
          keptPeerIds: {},
        );
        final after = _layout(
          paths: pathsWithHolder,
          keptPeerIds: {'a', 'h'},
          visibleRequestsByAuthor: {'h': ['req-1']},
        );

        expect(after.positions.containsKey('h'), isTrue);
        expect(before.positions.containsKey('h'), isFalse);
        expect(after.positions['h'], isNot(equals(before.positions[_ego])));
      },
    );

    test('filter stability: hiding branch requests moves no person', () {
      final paths = _paths(
        visiblePeerIds: {'a', 'b', 'c'},
        holderIds: {'b', 'c'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'b', 1),
          _edge(_ego, 'c', 1),
        ],
      );
      final kept = {'a', 'b', 'c'};

      final full = _layout(
        paths: paths,
        keptPeerIds: kept,
        visibleRequestsByAuthor: {
          'b': ['req-b1'],
          'c': ['req-c1'],
        },
      );
      final filtered = _layout(
        paths: paths,
        keptPeerIds: kept,
        visibleRequestsByAuthor: {'b': ['req-b1']},
      );

      expect(_personPositions(filtered), _personPositions(full));
    });

    test('sector containment: depth-2 sibling only reshuffles inside parent sector', () {
      final edges = [
        _edge(_ego, 'p', 1),
        _edge('p', 'c1', 1),
        _edge(_ego, 'q', 1),
        _edge('q', 'd1', 1),
      ];
      final pathsOneChild = _paths(
        visiblePeerIds: {'p', 'c1', 'q', 'd1'},
        holderIds: {'c1', 'd1'},
        edges: edges,
      );
      final pathsTwoChildren = _paths(
        visiblePeerIds: {'p', 'c1', 'c2', 'q', 'd1'},
        holderIds: {'c1', 'c2', 'd1'},
        edges: [
          ...edges,
          _edge('p', 'c2', 1),
        ],
      );

      final before = _layout(
        paths: pathsOneChild,
        keptPeerIds: {'p', 'c1', 'q', 'd1'},
      );
      final after = _layout(
        paths: pathsTwoChildren,
        keptPeerIds: {'p', 'c1', 'c2', 'q', 'd1'},
      );

      for (final id in [_ego, 'p', 'q', 'd1']) {
        expect(after.positions[id], equals(before.positions[id]));
      }
      expect(after.positions['c1'], isNot(equals(before.positions['c1'])));
      expect(after.positions.containsKey('c2'), isTrue);
    });

    test("ego satellites hang off the centre [D16]", () {
      final layout = _layout(
        paths: _paths(),
        egoOwnRequestIds: {'ego-req-1', 'ego-req-2'},
      );

      final req1 = layout.positions['ego-req-1']!;
      final req2 = layout.positions['ego-req-2']!;
      expect(_distFromCentre(req1), greaterThan(0));
      expect(_distFromCentre(req2), greaterThan(0));
      expect(req1, isNot(equals(req2)));
      expect(layout.ring.containsKey('ego-req-1'), isFalse);
    });

    test('cap-displaced people and their requests get no position', () {
      final capped = resolveAndCapConstellation(
        egoId: _ego,
        visiblePeerIds: {'a', 'b', 'h'},
        holderIds: {'h'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'b', 1),
          _edge('b', 'h', 1),
        ],
        cap: 1,
      );

      expect(capped.keptPeerIds, isEmpty);
      expect(capped.paths.keep, containsAll(['a', 'b', 'h']));

      final layout = _layout(
        paths: capped.paths,
        keptPeerIds: capped.keptPeerIds,
        visibleRequestsByAuthor: {'h': ['req-h1']},
      );

      expect(layout.positions.containsKey(_ego), isTrue);
      expect(layout.ring[_ego], 0);
      for (final id in ['a', 'b', 'h', 'req-h1']) {
        expect(layout.positions.containsKey(id), isFalse);
        expect(layout.ring.containsKey(id), isFalse);
      }
    });

    test('maxHops drives residual ring radius', () {
      final paths = _paths(
        visiblePeerIds: {'a', 'b', 'q', 'r'},
        holderIds: {'r'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'b', 1),
          _edge('b', 'q', 1),
          _edge(_ego, 'q', 2),
          _edge('q', 'r', 2),
        ],
        maxHops: 3,
      );
      expect(paths.ring, {'r'});

      final hops2 = _layout(
        paths: paths,
        keptPeerIds: {'r'},
        maxHops: 2,
        residualRingFactor: 1.6,
      );
      final hops3 = _layout(
        paths: paths,
        keptPeerIds: {'r'},
        maxHops: 3,
        residualRingFactor: 1.6,
      );

      final r2 = _distFromCentre(hops2.positions['r']!);
      final r3 = _distFromCentre(hops3.positions['r']!);
      expect(r2, closeTo((2 + 1.6) * _ringGap, _epsilon));
      expect(r3, closeTo((3 + 1.6) * _ringGap, _epsilon));
      expect(r2, isNot(closeTo(r3, _epsilon)));
    });

    test('determinism: shuffled input iteration order yields identical positions', () {
      final paths = _paths(
        visiblePeerIds: {'a', 'b', 'c', 'd'},
        holderIds: {'b', 'c', 'd'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'b', 1),
          _edge(_ego, 'c', 1),
          _edge('c', 'd', 1),
        ],
      );
      final kept = {'a', 'b', 'c', 'd'};

      final ordered = _layout(
        paths: paths,
        keptPeerIds: kept,
        visibleRequestsByAuthor: {
          'b': ['req-b2', 'req-b1'],
          'd': ['req-d1'],
        },
        egoOwnRequestIds: {'ego-req-2', 'ego-req-1'},
      );

      final shuffled = computeConstellationLayout(
        egoId: _ego,
        paths: paths,
        keptPeerIds: {...kept}.toList().reversed.toSet(),
        visibleRequestsByAuthor: {
          'd': ['req-d1'],
          'b': ['req-b1', 'req-b2'],
        },
        egoOwnRequestIds: {'ego-req-1', 'ego-req-2'},
      );

      expect(shuffled.positions, ordered.positions);
      expect(shuffled.ring, ordered.ring);
    });

    test('sibling sectors split equally by id, not subtree size', () {
      final paths = _paths(
        visiblePeerIds: {'a', 'b', 'c', 'd'},
        holderIds: {'c', 'd'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'c', 1),
          _edge(_ego, 'b', 1),
          _edge('b', 'd', 1),
        ],
      );

      final layout = _layout(
        paths: paths,
        keptPeerIds: {'a', 'b', 'c', 'd'},
      );

      final cAngle = _angleFromCentre(layout.positions['c']!);
      final dAngle = _angleFromCentre(layout.positions['d']!);
      expect((cAngle - dAngle).abs(), closeTo(math.pi, 0.05));
    });
  });

  group('R04a drawn-only satellites', () {
    test('constellationDrawnSatellites excludes hidden and pinned ids', () {
      const plan = ConstellationLabelDisplayPlan(
        drawnRequestIds: {'r1', 'r2', 'e1'},
        layoutRequestsByAuthor: {
          'author-a': ['r1', 'hidden', 'r2'],
          'ego': ['e1', 'e-hidden'],
        },
        egoOwnRequestIds: {'e1', 'e-pinned'},
        overflowHiddenCountByAuthor: const {},
        pinnedRequestIds: {'e-pinned', 'r2'},
      );
      final drawn = constellationDrawnSatellites(plan);
      expect(drawn.byAuthor, {
        'author-a': ['r1'],
        'ego': ['e1'],
      });
      expect(drawn.egoOwn, {'e1'});
    });
  });

  group('R04a footprints and obstacles', () {
    const _sampleMetrics = (
      labelGap: 4.0,
      personLabelWidth: 100.0,
      personLabelHeight: 20.0,
      requestLabelWidth: 100.0,
      requestLabelHeight: 20.0,
      chipWidth: 120.0,
      chipHeight: 32.0,
      badgeOverhang: 8.0,
    );

    ConstellationPlacedLayoutInput _peerAndRequestInput({
      Map<String, ConstellationFootprint> footprints = const {},
    }) {
      final paths = _paths(
        visiblePeerIds: {'author'},
        holderIds: {'author'},
        edges: [_edge(_ego, 'author', 1)],
      );
      return (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: {'author'},
        pinnedPersonIds: const {},
        pinnedRequestIds: const {},
        supportPersonIds: const {},
        anchorByNodeId: const {},
        priorHints: null,
        nodeSizes: const {
          'author': (width: 40.0, height: 40.0),
          'req-1': (width: 36.0, height: 36.0),
        },
        satelliteRequestIdsByAuthor: const {'author': ['req-1']},
        requestAuthorById: const {'req-1': 'author'},
        egoOwnRequestIds: const {},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: footprints,
      );
    }

    test('empty footprints preserve layout output', () {
      final input = _peerAndRequestInput();
      final layout = computeConstellationPlacedLayout(input: input);
      expect(layout.positions.keys, containsAll(['author', 'req-1']));
      final again = computeConstellationPlacedLayout(input: input);
      expect(again.positions, layout.positions);
    });

    test('request avoids overlapping author footprint when alternative exists',
        () {
      final authorFootprint = (
        left: 90.0,
        top: 40.0,
        right: 90.0,
        bottom: 140.0,
      );
      final requestFootprint = (
        left: 25.0,
        top: 25.0,
        right: 25.0,
        bottom: 70.0,
      );
      final egoFootprint = constellationNodeFootprint(
        kind: ConstellationFootprintKind.person,
        bodySize: 40,
        hasAuthorChip: false,
        metrics: _sampleMetrics,
      );
      final input = _peerAndRequestInput(
        footprints: {
          _ego: egoFootprint,
          'author': authorFootprint,
          'req-1': requestFootprint,
        },
      );
      final layout = computeConstellationPlacedLayout(input: input);
      final overlaps = constellationFootprintOverlaps(input, layout);
      expect(
        overlaps.any(
          (pair) => pair.$1 == 'author' || pair.$2 == 'author'
              ? pair.$1 == 'req-1' || pair.$2 == 'req-1'
              : false,
        ),
        isFalse,
      );
    });

    test('non-empty footprints do not move people (A3 guard)', () {
      final paths = _paths(
        visiblePeerIds: {'a', 'h'},
        holderIds: {'h'},
        edges: [
          _edge(_ego, 'a', 1),
          _edge('a', 'h', 1),
        ],
      );
      final base = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: {'a', 'h'},
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: const {'a': (width: 80.0, height: 80.0)},
        satelliteRequestIdsByAuthor: const {'h': ['req-1', 'req-2', 'req-3']},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
      );
      final withFootprints = (
        egoId: base.egoId,
        paths: base.paths,
        automaticKeptPeerIds: base.automaticKeptPeerIds,
        pinnedPersonIds: base.pinnedPersonIds,
        pinnedRequestIds: base.pinnedRequestIds,
        supportPersonIds: base.supportPersonIds,
        anchorByNodeId: base.anchorByNodeId,
        priorHints: base.priorHints,
        nodeSizes: base.nodeSizes,
        satelliteRequestIdsByAuthor: base.satelliteRequestIdsByAuthor,
        requestAuthorById: base.requestAuthorById,
        egoOwnRequestIds: base.egoOwnRequestIds,
        spacing: base.spacing,
        maxHops: base.maxHops,
        viewportClass: base.viewportClass,
        footprints: {
          for (final id in ['a', 'h', _ego])
            id: constellationNodeFootprint(
              kind: ConstellationFootprintKind.person,
              bodySize: 40,
              hasAuthorChip: id == 'h',
              metrics: _sampleMetrics,
            ),
          for (final id in ['req-1', 'req-2', 'req-3'])
            id: constellationNodeFootprint(
              kind: ConstellationFootprintKind.request,
              bodySize: 36,
              hasAuthorChip: false,
              metrics: _sampleMetrics,
            ),
        },
      );
      final emptyLayout = computeConstellationPlacedLayout(input: base);
      final footprintLayout = computeConstellationPlacedLayout(
        input: withFootprints,
      );
      expect(
        _personPositions(footprintLayout),
        _personPositions(emptyLayout),
      );
    });
  });

  group('constellationFootprintOverlaps', () {
    test('reports overlapping non-pinned pair', () {
      final input = (
        egoId: _ego,
        paths: _paths(),
        automaticKeptPeerIds: const {'a', 'b'},
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: const <String, ConstellationSize>{},
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const {
          'a': (left: 50.0, top: 50.0, right: 50.0, bottom: 50.0),
          'b': (left: 50.0, top: 50.0, right: 50.0, bottom: 50.0),
        },
      );
      final centre = _centre();
      final layout = (
        positions: {
          'a': centre,
          'b': centre,
        },
        ring: <String, int>{'a': 1, 'b': 1},
      );
      final overlaps = constellationFootprintOverlaps(input, layout);
      expect(overlaps, {('a', 'b')});
    });

    test('skips overlaps when both nodes are pinned', () {
      final input = (
        egoId: _ego,
        paths: _paths(),
        automaticKeptPeerIds: const <String>{},
        pinnedPersonIds: const {'a', 'b'},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: const <String, ConstellationSize>{},
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const {
          'a': (left: 50.0, top: 50.0, right: 50.0, bottom: 50.0),
          'b': (left: 50.0, top: 50.0, right: 50.0, bottom: 50.0),
        },
      );
      final centre = _centre();
      final layout = (
        positions: {'a': centre, 'b': centre},
        ring: const <String, int>{},
      );
      expect(constellationFootprintOverlaps(input, layout), isEmpty);
    });

    test('returns empty when footprints do not overlap', () {
      final input = (
        egoId: _ego,
        paths: _paths(),
        automaticKeptPeerIds: const {'a', 'b'},
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: const <String, ConstellationSize>{},
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const {
          'a': (left: 10.0, top: 10.0, right: 10.0, bottom: 10.0),
          'b': (left: 10.0, top: 10.0, right: 10.0, bottom: 10.0),
        },
      );
      final centre = _centre();
      final layout = (
        positions: {
          'a': (x: centre.x, y: centre.y),
          'b': (x: centre.x + 500, y: centre.y),
        },
        ring: <String, int>{'a': 1, 'b': 1},
      );
      expect(constellationFootprintOverlaps(input, layout), isEmpty);
    });
  });

  group('R04b ego satellite direction', () {
    test('no depth-1 peers → down and full circle gap', () {
      final result = constellationEgoSatelliteDirection([]);
      expect(result.direction.dx, closeTo(0, 1e-9));
      expect(result.direction.dy, closeTo(1, 1e-9));
      expect(result.gap, closeTo(2 * math.pi, 1e-9));
    });

    test('three peer screen angles → bisector near 152.5°', () {
      final result = constellationEgoSatelliteDirection([
        _rad(90),
        _rad(215),
        _rad(327),
      ]);
      final angleDeg = _deg(
        math.atan2(result.direction.dy, result.direction.dx),
      );
      expect(angleDeg, closeTo(152.5, 1.0));
    });

    test('equal gaps keep smaller start angle (tie-break)', () {
      final result = constellationEgoSatelliteDirection([0, math.pi]);
      expect(result.direction.dx, closeTo(0, 1e-9));
      expect(result.direction.dy, closeTo(1, 1e-9));
    });

    test('single peer screen angle → fan bisector opposite peer', () {
      final peerAngle = _rad(0);
      final heading = constellationEgoSatelliteDirection([peerAngle]);
      expect(heading.direction.dx, closeTo(-1, 0.01));
      expect(heading.direction.dy, closeTo(0, 0.01));
    });
  });

  group('R04b pins exact (D20)', () {
    test('identical pinned anchors coincide and are not reported as overlap', () {
      const anchor = ConstellationAnchorPosition(
        xUnits: 3,
        yUnits: -2,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      final point = constellationV1AnchorToPoint(anchor);
      final input = (
        egoId: _ego,
        paths: _paths(),
        automaticKeptPeerIds: const <String>{},
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: {'req-a', 'req-b'},
        supportPersonIds: const <String>{},
        anchorByNodeId: {
          'req-a': anchor,
          'req-b': anchor,
        },
        priorHints: null,
        nodeSizes: const {
          'req-a': (width: 36.0, height: 36.0),
          'req-b': (width: 36.0, height: 36.0),
        },
        satelliteRequestIdsByAuthor: const <String, List<String>>{},
        requestAuthorById: const <String, String>{},
        egoOwnRequestIds: const <String>{},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const {
          'req-a': (left: 30.0, top: 30.0, right: 30.0, bottom: 60.0),
          'req-b': (left: 30.0, top: 30.0, right: 30.0, bottom: 60.0),
        },
      );
      final layout = computeConstellationPlacedLayout(input: input);
      expect(layout.positions['req-a'], point);
      expect(layout.positions['req-b'], point);
      expect(constellationFootprintOverlaps(input, layout), isEmpty);
    });
  });

  group('R04b attachment crossing preference', () {
    test('chooses zero-overlap candidate that avoids crossing a body', () {
      final centre = _centre();
      final blockAnchor = ConstellationAnchorPosition(
        xUnits: (centre.x + _ringGap + 40 - centre.x) /
            kConstellationRingUnitPixels,
        yUnits: 0,
        coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
      );
      final paths = _paths(
        visiblePeerIds: {'author', 'block'},
        holderIds: {'author'},
        edges: [
          _edge(_ego, 'author', 1),
          _edge(_ego, 'block', 1),
        ],
      );
      final input = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: {'author'},
        pinnedPersonIds: const {'block'},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: {'block': blockAnchor},
        priorHints: null,
        nodeSizes: const {
          'author': (width: 40.0, height: 40.0),
          'block': (width: 80.0, height: 80.0),
          'req-1': (width: 36.0, height: 36.0),
        },
        satelliteRequestIdsByAuthor: const {'author': ['req-1']},
        requestAuthorById: const {'req-1': 'author'},
        egoOwnRequestIds: const <String>{},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
      );
      final layout = computeConstellationPlacedLayout(input: input);
      final authorPos = layout.positions['author']!;
      final reqPos = layout.positions['req-1']!;
      final blockPos = layout.positions['block']!;
      final blockBody = constellationRenderedBounds(
        centre: blockPos,
        size: (width: 80.0, height: 80.0),
      );
      final crossesBlock = _segmentCrossesRect(
        Offset(authorPos.x, authorPos.y),
        Offset(reqPos.x, reqPos.y),
        blockBody,
      );
      expect(crossesBlock, isFalse);
    });

    test('falls back to first zero-overlap when all cross bodies', () {
      final centre = _centre();
      final authorX = centre.x + _ringGap;
      final paths = _paths(
        visiblePeerIds: {'author'},
        holderIds: {'author'},
        edges: [_edge(_ego, 'author', 1)],
      );
      final input = (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: {'author'},
        pinnedPersonIds: const <String>{},
        pinnedRequestIds: const <String>{},
        supportPersonIds: const <String>{},
        anchorByNodeId: const <String, ConstellationAnchorPosition>{},
        priorHints: null,
        nodeSizes: const {
          'author': (width: 40.0, height: 40.0),
          'req-1': (width: 36.0, height: 36.0),
        },
        satelliteRequestIdsByAuthor: const {'author': ['req-1']},
        requestAuthorById: const {'req-1': 'author'},
        egoOwnRequestIds: const <String>{},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: const <String, ConstellationFootprint>{},
      );
      final layoutWithBlocker = computeConstellationPlacedLayout(
        input: (
          egoId: input.egoId,
          paths: input.paths,
          automaticKeptPeerIds: input.automaticKeptPeerIds,
          pinnedPersonIds: const {'block'},
          pinnedRequestIds: input.pinnedRequestIds,
          supportPersonIds: input.supportPersonIds,
          anchorByNodeId: {
            'block': ConstellationAnchorPosition(
              xUnits: (authorX + 30 - centre.x) / kConstellationRingUnitPixels,
              yUnits: 0,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
          },
          priorHints: input.priorHints,
          nodeSizes: {
            ...input.nodeSizes,
            'block': (width: 200.0, height: 200.0),
          },
          satelliteRequestIdsByAuthor: input.satelliteRequestIdsByAuthor,
          requestAuthorById: input.requestAuthorById,
          egoOwnRequestIds: input.egoOwnRequestIds,
          spacing: input.spacing,
          maxHops: input.maxHops,
          viewportClass: input.viewportClass,
          footprints: input.footprints,
        ),
      );
      final baseline = computeConstellationPlacedLayout(input: input);
      expect(
        layoutWithBlocker.positions['req-1'],
        baseline.positions['req-1'],
      );
    });
  });

  group('R04b reference footprint overlap', () {
    const _refMetrics = (
      labelGap: 2.0,
      personLabelWidth: 120.0,
      personLabelHeight: 22.0,
      requestLabelWidth: 144.0,
      requestLabelHeight: 40.0,
      chipWidth: 110.0,
      chipHeight: 44.0,
      badgeOverhang: 8.0,
    );

    ConstellationPlacedLayoutInput _referenceLikeInput({
      Map<String, ConstellationFootprint> footprints = const {},
    }) {
      final paths = _paths(
        visiblePeerIds: {'am', 'in', 'sm'},
        holderIds: {'in', 'sm'},
        edges: [
          _edge(_ego, 'am', 1),
          _edge(_ego, 'in', 1),
          _edge(_ego, 'sm', 1),
          _edge('in', 'req-in-1', 1),
        ],
      );
      return (
        egoId: _ego,
        paths: paths,
        automaticKeptPeerIds: {'am', 'in', 'sm'},
        pinnedPersonIds: const {},
        pinnedRequestIds: const {},
        supportPersonIds: const {},
        anchorByNodeId: const {},
        priorHints: null,
        nodeSizes: const {
          'am': (width: 40.0, height: 40.0),
          'in': (width: 40.0, height: 40.0),
          'sm': (width: 40.0, height: 40.0),
        },
        satelliteRequestIdsByAuthor: const {
          'ego': ['req-ego-1', 'req-ego-2', 'req-ego-3'],
          'in': ['req-in-1'],
        },
        requestAuthorById: const {'req-in-1': 'in'},
        egoOwnRequestIds: const {'req-ego-1', 'req-ego-2', 'req-ego-3'},
        spacing: 16.0,
        maxHops: 3,
        viewportClass: ConstellationViewportClass.expanded,
        footprints: footprints,
      );
    }

    Map<String, ConstellationFootprint> _referenceFootprints() {
      final metrics = _refMetrics;
      final people = ['am', 'in', 'sm', _ego];
      final requests = ['req-ego-1', 'req-ego-2', 'req-ego-3', 'req-in-1'];
      return {
        for (final id in people)
          id: constellationNodeFootprint(
            kind: ConstellationFootprintKind.person,
            bodySize: 40,
            hasAuthorChip: id == 'in',
            metrics: metrics,
          ),
        for (final id in requests)
          id: constellationNodeFootprint(
            kind: ConstellationFootprintKind.request,
            bodySize: 36,
            hasAuthorChip: false,
            metrics: metrics,
          ),
      };
    }

    test('no footprint overlaps with realistic metrics', () {
      final footprints = _referenceFootprints();
      final input = _referenceLikeInput(footprints: footprints);
      final layout = computeConstellationPlacedLayout(input: input);
      expect(constellationFootprintOverlaps(input, layout), isEmpty);
    });
  });
}

bool _segmentCrossesRect(Offset a, Offset b, ConstellationBounds r) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  const eps = 1e-9;
  var t0 = 0.0;
  var t1 = 1.0;

  bool clip(double p, double q) {
    if (p.abs() < eps) {
      return q >= 0;
    }
    final r = q / p;
    if (p < 0) {
      if (r > t1) {
        return false;
      }
      if (r > t0) {
        t0 = r;
      }
    } else {
      if (r < t0) {
        return false;
      }
      if (r < t1) {
        t1 = r;
      }
    }
    return true;
  }

  if (!clip(-dx, a.dx - r.left)) {
    return false;
  }
  if (!clip(dx, r.right - a.dx)) {
    return false;
  }
  if (!clip(-dy, a.dy - r.top)) {
    return false;
  }
  if (!clip(dy, r.bottom - a.dy)) {
    return false;
  }
  return t0 <= t1;
}

double _angleFromCentre(ConstellationPoint position) {
  final centre = _centre();
  final delta = (x: position.x - centre.x, y: position.y - centre.y);
  return math.atan2(delta.y, delta.x);
}

double _rad(double degrees) => degrees * math.pi / 180;

double _deg(double radians) => radians * 180 / math.pi;
