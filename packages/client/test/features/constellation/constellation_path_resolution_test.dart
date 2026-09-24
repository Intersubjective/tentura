import 'package:flutter_test/flutter_test.dart';

import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

const _ego = 'ego';

ConstellationEdgeRef _e(String src, String dst, int tier) => (
  src: src,
  dst: dst,
  tier: tier,
);

ConstellationPathResolution _resolve({
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

void main() {
  group('resolveConstellationPaths', () {
    test('tier 1 wins across stages, however much longer [ALG-STAGE1]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
          _e('b', 'h', 1),
          _e(_ego, 'h', 2),
        ],
      );

      expect(result.depth['h'], 3);
      expect(result.derived['h'], 0);
      expect(result.parent['h'], 'b');
      expect(result.parentTier['h'], 1);
      expect(result.attributed, {'h'});
      expect(result.ring, isEmpty);
    });

    test('hops first inside stage 2 / derived is per-layer [ALG-STAGE2]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'c', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 2),
          _e('a', 'h', 2),
          _e(_ego, 'b', 2),
          _e('b', 'c', 1),
          _e('c', 'h', 1),
        ],
      );

      expect(result.depth['h'], 2);
      expect(result.derived['h'], 2);
    });

    test('equal-length stage-2 paths prefer fewer tier-2 edges [ALG-STAGE2]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 2),
          _e(_ego, 'b', 2),
          _e('a', 'h', 2),
          _e('b', 'h', 1),
        ],
      );

      expect(result.depth['h'], 2);
      expect(result.derived['h'], 1);
      expect(result.parent['h'], 'b');
      expect(result.parentTier['h'], 1);
    });

    test('unreachable first layer, reachable second [ALG-STAGE2]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'p'},
        holderIds: {'p'},
        edges: [
          _e(_ego, 'a', 2),
          _e('a', 'p', 1),
        ],
      );

      expect(result.depth['p'], 2);
      expect(result.derived['p'], 1);
    });

    test('stage-1 nodes carry derived == 0 [ALG-STAGE1]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'c'},
        holderIds: {'c'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
          _e('b', 'c', 1),
          _e(_ego, 'c', 2),
          _e('a', 'c', 2),
        ],
      );

      for (final peer in ['a', 'b', 'c']) {
        expect(result.derived[peer], 0);
      }
    });

    test('stage-2 constraint costs reachability, deliberately [ALG-STAGE2]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'q', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
          _e('b', 'q', 1),
          _e(_ego, 'q', 2),
          _e('q', 'h', 2),
        ],
      );

      expect(result.ring, {'h'});
      expect(result.attributed, isEmpty);
      expect(result.parent.containsKey('h'), isFalse);
    });

    test('min-id parent, not first discovery [ALG-PARENT]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'c', 'z', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e(_ego, 'b', 1),
          _e('a', 'z', 1),
          _e('b', 'c', 1),
          _e('z', 'h', 1),
          _e('c', 'h', 1),
        ],
      );

      expect(result.parent['h'], 'c');
      expect(result.parent['h'], isNot('z'));
    });

    test('tier beats id in the parent tie-break [ALG-PARENT]', () {
      final result = _resolve(
        visiblePeerIds: {'q1', 'q2', 'p'},
        holderIds: {'p'},
        edges: [
          _e(_ego, 'q2', 1),
          _e(_ego, 'q1', 2),
          _e('q1', 'p', 1),
          _e('q2', 'p', 2),
        ],
      );

      expect(result.depth['p'], 2);
      expect(result.derived['p'], 1);
      expect(result.parent['p'], 'q1');
      expect(result.parentTier['p'], 1);
    });

    test('illegal parent rejected [ALG-PARENT]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'q', 'r', 'p'},
        holderIds: {'p'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
          _e('b', 'q', 1),
          _e('q', 'p', 1),
          _e('r', 'p', 1),
          _e(_ego, 'q', 2),
          _e(_ego, 'r', 2),
        ],
      );

      expect(result.depth['p'], 2);
      expect(result.derived['p'], 1);
      expect(result.parent['p'], 'r');
      expect(result.parentTier['p'], 1);
      expect(result.depth[result.parent['p']], result.depth['p']! - 1);
    });

    test('parent is always exactly one ring in [ALG-PARENT]', () {
      final fixtures = <List<ConstellationEdgeRef>>[
        [
          _e(_ego, 'a', 1),
          _e('a', 'b', 2),
          _e('b', 'c', 1),
        ],
        [
          _e(_ego, 'x', 2),
          _e('x', 'y', 2),
          _e('y', 'z', 1),
        ],
        [
          _e(_ego, 'm', 1),
          _e('m', 'n', 2),
          _e(_ego, 'n', 2),
          _e('n', 'o', 1),
        ],
      ];

      for (final edges in fixtures) {
        final peers = <String>{};
        for (final edge in edges) {
          peers.add(edge.src);
          peers.add(edge.dst);
        }
        peers.remove(_ego);

        final result = _resolve(
          visiblePeerIds: peers,
          holderIds: peers,
          edges: edges,
        );

        for (final peer in result.depth.keys) {
          final parentId = result.parent[peer];
          expect(parentId, isNotNull);
          if (parentId == _ego) {
            expect(result.depth[peer], 1);
          } else {
            expect(result.depth[parentId], result.depth[peer]! - 1);
          }
        }
      }
    });

    test('duplicate pair, tier 1 wins [ALG-DEDUP]', () {
      final edges = [
        _e(_ego, 'a', 1),
        _e('a', 'b', 1),
        _e('a', 'b', 2),
      ];

      for (final permutation in _permutations(edges)) {
        final result = _resolve(
          visiblePeerIds: {'a', 'b'},
          holderIds: {'b'},
          edges: permutation,
        );

        expect(result.depth['b'], 2);
        expect(result.derived['b'], 0);
        expect(result.parent['b'], 'a');
        expect(result.parentTier['b'], 1);
      }
    });

    test('ego is excluded [ALG-EGO]', () {
      final result = _resolve(
        visiblePeerIds: {'a'},
        holderIds: {_ego, 'a'},
        edges: [_e('a', _ego, 1)],
      );

      expect(result.depth.containsKey(_ego), isFalse);
      expect(result.derived.containsKey(_ego), isFalse);
      expect(result.parent.containsKey(_ego), isFalse);
      expect(result.parentTier.containsKey(_ego), isFalse);
      expect(result.attributed.contains(_ego), isFalse);
      expect(result.keep.contains(_ego), isFalse);
      expect(result.ring.contains(_ego), isFalse);
    });

    test('ego-only field [ALG-EGO]', () {
      final result = _resolve(
        visiblePeerIds: {},
        holderIds: {_ego},
        edges: [],
      );

      expect(result.depth, isEmpty);
      expect(result.derived, isEmpty);
      expect(result.parent, isEmpty);
      expect(result.parentTier, isEmpty);
      expect(result.attributed, isEmpty);
      expect(result.keep, isEmpty);
      expect(result.ring, isEmpty);
    });

    test('no order dependence in the table [ALG-STAGE2]', () {
      final edges = [
        _e(_ego, 'a', 2),
        _e(_ego, 'c', 2),
        _e('a', 'b', 1),
        _e('b', 'x', 1),
        _e('c', 'x', 1),
      ];

      for (final permutation in _permutations(edges)) {
        final result = _resolve(
          visiblePeerIds: {'a', 'b', 'c', 'x'},
          holderIds: {'x'},
          edges: permutation,
        );

        expect(result.depth['x'], 2);
        expect(result.derived['x'], 1);
        expect(result.parent['x'], 'c');
      }
    });

    test('depth cap sends a 4-hop holder to ring', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'c', 'd', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
          _e('b', 'c', 1),
          _e('c', 'd', 1),
          _e('d', 'h', 1),
        ],
      );

      expect(result.ring, {'h'});
      expect(result.attributed, isEmpty);
    });

    test('direction: inbound edge alone does not reach peer [D7]', () {
      final result = _resolve(
        visiblePeerIds: {'a'},
        holderIds: {'a'},
        edges: [_e('a', _ego, 1)],
      );

      expect(result.depth.containsKey('a'), isFalse);
      expect(result.ring, {'a'});
    });

    test('containment ignores edges outside the visible set [D6]', () {
      final result = _resolve(
        visiblePeerIds: {'a'},
        holderIds: {'a'},
        edges: [
          _e(_ego, 'a', 1),
          _e(_ego, 'ghost', 1),
          _e('ghost', 'a', 1),
        ],
      );

      expect(result.parent['a'], _ego);
      expect(result.depth['a'], 1);
      expect(result.derived['a'], 0);
    });

    test('Steiner pruning drops non-holder branches [ALG-PRUNE]', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'b', 'c', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
          _e('a', 'c', 1),
          _e('b', 'h', 1),
        ],
      );

      expect(result.keep, containsAll(['a', 'b', 'h']));
      expect(result.keep.contains('c'), isFalse);
      expect(result.attributed.contains('c'), isFalse);
    });

    test('ring holder reachable only through a non-visible person', () {
      final result = _resolve(
        visiblePeerIds: {'a', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'ghost', 1),
          _e('ghost', 'h', 1),
        ],
      );

      expect(result.ring, {'h'});
      expect(result.parent.containsKey('h'), isFalse);
    });

    test('determinism under shuffled inputs', () {
      final edges = [
        _e(_ego, 'a', 1),
        _e('a', 'b', 2),
        _e(_ego, 'c', 2),
        _e('c', 'd', 1),
        _e('b', 'h', 1),
        _e('d', 'h', 2),
      ];
      final peers = {'a', 'b', 'c', 'd', 'h'};

      ConstellationPathResolution? baseline;
      for (var i = 0; i < 50; i++) {
        final shuffledPeers = peers.toList()..shuffle();
        final shuffledEdges = edges.toList()..shuffle();
        final result = resolveConstellationPaths(
          egoId: _ego,
          visiblePeerIds: shuffledPeers.toSet(),
          holderIds: {'h'},
          edges: shuffledEdges,
        );
        baseline ??= result;
        expect(result.depth, baseline!.depth);
        expect(result.derived, baseline.derived);
        expect(result.parent, baseline.parent);
        expect(result.parentTier, baseline.parentTier);
        expect(result.attributed, baseline.attributed);
        expect(result.keep, baseline.keep);
        expect(result.ring, baseline.ring);
      }
    });
  });
}

List<List<ConstellationEdgeRef>> _permutations(List<ConstellationEdgeRef> items) {
  if (items.length <= 1) {
    return [items];
  }
  final results = <List<ConstellationEdgeRef>>[];
  for (var i = 0; i < items.length; i++) {
    final rest = [
      ...items.sublist(0, i),
      ...items.sublist(i + 1),
    ];
    for (final tail in _permutations(rest)) {
      results.add([items[i], ...tail]);
    }
  }
  return results;
}
