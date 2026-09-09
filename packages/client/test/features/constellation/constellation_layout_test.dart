import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_cap_policy.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_path_resolution.dart';

const _ego = 'ego';
const _canvas = Size(2400, 1800);
const _ringGap = 170.0;
const _satelliteOffset = 56.0;
const _epsilon = 1.0;

ConstellationEdgeRef _edge(String src, String dst, int tier) => (
  src: src,
  dst: dst,
  tier: tier,
);

Offset _centre() => _canvas.center(Offset.zero);

double _distFromCentre(Offset position) => (position - _centre()).distance;

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
    canvasSize: _canvas,
    maxHops: maxHops,
    ringGap: ringGap,
    residualRingFactor: residualRingFactor,
    satelliteOffset: satelliteOffset,
  );
}

Map<String, Offset> _personPositions(ConstellationLayout layout) {
  return Map<String, Offset>.from(layout.positions)
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
      expect((reqPos - bPos).distance, lessThanOrEqualTo(_satelliteOffset + _epsilon));
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

      for (final id in ['ego-req-1', 'ego-req-2']) {
        final pos = layout.positions[id]!;
        expect((pos - _centre()).distance, lessThanOrEqualTo(_satelliteOffset + _epsilon));
      }
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
        canvasSize: _canvas,
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
}

double _angleFromCentre(Offset position) {
  final delta = position - _centre();
  return math.atan2(delta.dy, delta.dx);
}
