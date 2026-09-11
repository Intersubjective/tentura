import 'package:test/test.dart';

import 'package:tentura_server/domain/constellation/constellation_path_resolution.dart';

const _ego = 'ego';

ConstellationEdgeRef _e(String src, String dst, int tier) => (
  src: src,
  dst: dst,
  tier: tier,
);

void main() {
  test('parity: tier 1 wins across stages [ALG-STAGE1]', () {
    final result = resolveConstellationPaths(
      egoId: _ego,
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

  test('parity: unreachable holder stays in ring', () {
    final result = resolveConstellationPaths(
      egoId: _ego,
      visiblePeerIds: {'a'},
      holderIds: {'orphan'},
      edges: [_e(_ego, 'a', 1)],
    );
    expect(result.ring, {'orphan'});
    expect(result.keep, isEmpty);
  });

  test('anchor closure expands visible peers with path holders', () {
    final holders = {'author'};
    final visible = {'mid', ...holders};
    final result = resolveConstellationPaths(
      egoId: _ego,
      visiblePeerIds: visible,
      holderIds: holders,
      edges: [
        _e(_ego, 'mid', 1),
        _e('mid', 'author', 1),
      ],
    );

    expect(result.attributed, {'author'});
    expect(result.keep, containsAll(['mid', 'author']));
    expect(result.ring, isEmpty);

    final supportEdges = constellationSupportEdges(
      egoId: _ego,
      resolution: result,
      trustEdges: [
        _e(_ego, 'mid', 1),
        _e('mid', 'author', 1),
      ],
    );
    expect(supportEdges, isNotEmpty);
  });
}
