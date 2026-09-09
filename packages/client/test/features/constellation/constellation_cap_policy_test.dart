import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_cap_policy.dart';
import 'package:tentura/features/constellation/domain/constellation_path_resolution.dart';

const _ego = 'ego';

ConstellationEdgeRef _e(String src, String dst, int tier) => (
  src: src,
  dst: dst,
  tier: tier,
);

ConstellationResolvedField _cap({
  required Set<String> visiblePeerIds,
  required Set<String> holderIds,
  required Iterable<ConstellationEdgeRef> edges,
  required int cap,
}) {
  return resolveAndCapConstellation(
    egoId: _ego,
    visiblePeerIds: visiblePeerIds,
    holderIds: holderIds,
    edges: edges,
    cap: cap,
  );
}

void main() {
  group('resolveAndCapConstellation', () {
    test('cap, path-preserving keeps whole ancestor chains', () {
      final edges = [
        _e(_ego, 'a', 1),
        _e('a', 'b', 1),
        _e('b', 'h', 1),
        _e(_ego, 'x', 1),
        _e('x', 'y', 1),
        _e('y', 'h2', 1),
      ];

      final result = _cap(
        visiblePeerIds: {'a', 'b', 'h', 'x', 'y', 'h2'},
        holderIds: {'h', 'h2'},
        edges: edges,
        cap: 4,
      );

      expect(result.capped, isTrue);
      expect(result.droppedHolderIds, isNotEmpty);
      expect(result.paths.ring, isEmpty);

      for (final holder in result.paths.attributed.intersection(result.keptPeerIds)) {
        var current = holder;
        while (result.paths.parent.containsKey(current)) {
          final ancestor = result.paths.parent[current]!;
          if (ancestor == _ego) {
            break;
          }
          expect(result.keptPeerIds, contains(ancestor));
          current = ancestor;
        }
      }

      expect(result.paths.ring, isEmpty);
    });

    test('cap, chains exceeding the budget drop the attributed holder', () {
      final result = _cap(
        visiblePeerIds: {'a', 'b', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
          _e('b', 'h', 1),
        ],
        cap: 2,
      );

      expect(result.droppedHolderIds, {'h'});
      expect(result.keptPeerIds.contains('h'), isFalse);
      expect(result.paths.ring.contains('h'), isFalse);
      expect(result.keptPeerIds.intersection({'a', 'b'}), isEmpty);
      expect(result.capped, isTrue);
    });

    test('cap, two-node chain with budget 1 [D9]', () {
      final result = _cap(
        visiblePeerIds: {'a', 'h'},
        holderIds: {'h'},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'h', 1),
        ],
        cap: 1,
      );

      expect(result.keptPeerIds, isEmpty);
      expect(result.droppedHolderIds, {'h'});
      expect(result.capped, isTrue);
    });

    test('cap, no holders leaves keptPeerIds empty and capped false', () {
      final result = _cap(
        visiblePeerIds: {'a', 'b'},
        holderIds: {},
        edges: [
          _e(_ego, 'a', 1),
          _e('a', 'b', 1),
        ],
        cap: 10,
      );

      expect(result.keptPeerIds, isEmpty);
      expect(result.capped, isFalse);
      expect(result.droppedHolderIds, isEmpty);
    });

    test('a ring holder displaced by the cap stays a ring holder [N2]', () {
      final edges = [
        _e(_ego, 'a', 1),
        _e('a', 'b', 1),
        _e('b', 'h', 1),
      ];

      final uncapped = _cap(
        visiblePeerIds: {'a', 'b', 'h', 'r'},
        holderIds: {'h', 'r'},
        edges: edges,
        cap: 100,
      );
      expect(uncapped.paths.ring, {'r'});

      final capped = _cap(
        visiblePeerIds: {'a', 'b', 'h', 'r'},
        holderIds: {'h', 'r'},
        edges: edges,
        cap: 3,
      );

      expect(capped.paths.ring, {'r'});
      expect(capped.keptPeerIds.contains('r'), isFalse);
      expect(capped.droppedHolderIds.contains('r'), isFalse);
      expect(capped.capped, isTrue);
    });

    test('cap never re-resolves paths.ring', () {
      final edges = [
        _e(_ego, 'a', 1),
        _e('a', 'b', 1),
        _e('b', 'h', 1),
        _e(_ego, 'r', 2),
      ];
      final peers = {'a', 'b', 'h', 'r'};
      final holders = {'h', 'r'};

      final full = _cap(
        visiblePeerIds: peers,
        holderIds: holders,
        edges: edges,
        cap: 100,
      );
      final capped = _cap(
        visiblePeerIds: peers,
        holderIds: holders,
        edges: edges,
        cap: 1,
      );

      expect(capped.paths.ring, full.paths.ring);
      expect(capped.paths.attributed, full.paths.attributed);
      expect(capped.paths.depth, full.paths.depth);
      expect(capped.paths.parent, full.paths.parent);
    });

    test('cap, score-independent selection depends only on ids', () {
      final edges = [
        _e(_ego, 'a', 1),
        _e('a', 'h1', 1),
        _e(_ego, 'b', 1),
        _e('b', 'h2', 1),
      ];

      final result = _cap(
        visiblePeerIds: {'a', 'b', 'h1', 'h2'},
        holderIds: {'h1', 'h2'},
        edges: edges,
        cap: 2,
      );

      expect(result.keptPeerIds, contains('a'));
      expect(result.keptPeerIds, contains('h1'));
      expect(result.droppedHolderIds, {'h2'});
      expect(result.capped, isTrue);
    });
  });
}
