import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_chain.dart';

/// #641: the shortest chain of visible trust edges from the viewer.
typedef _E = ({String src, String dst, int tier});

_E _e(String src, String dst, [int tier = 1]) =>
    (src: src, dst: dst, tier: tier);

void main() {
  group('constellationShortestTrustChain', () {
    test('finds the shortest directed chain', () {
      final chain = constellationShortestTrustChain(
        from: 'me',
        to: 'zoe',
        edges: [
          _e('me', 'dima'),
          _e('dima', 'raf'),
          _e('raf', 'zoe'),
          _e('me', 'ann'),
          _e('ann', 'bob'),
          _e('bob', 'cid'),
          _e('cid', 'zoe'),
        ],
      );
      expect(chain, ['me', 'dima', 'raf', 'zoe']);
    });

    test('follows trust direction only', () {
      // Zoe trusts Raf and Raf trusts me: nothing leads from me to Zoe.
      expect(
        constellationShortestTrustChain(
          from: 'me',
          to: 'zoe',
          edges: [_e('zoe', 'raf'), _e('raf', 'me')],
        ),
        isNull,
      );
    });

    test('returns null when no visible chain exists', () {
      expect(
        constellationShortestTrustChain(
          from: 'me',
          to: 'zoe',
          edges: [_e('me', 'dima'), _e('raf', 'zoe')],
        ),
        isNull,
      );
    });

    test('the viewer alone is a chain of one', () {
      expect(
        constellationShortestTrustChain(from: 'me', to: 'me', edges: const []),
        ['me'],
      );
    });

    test('ties: fewer derived edges win over smaller ids', () {
      final chain = constellationShortestTrustChain(
        from: 'me',
        to: 'zoe',
        edges: [
          _e('me', 'ann'),
          _e('ann', 'zoe', 2),
          _e('me', 'bob'),
          _e('bob', 'zoe'),
        ],
      );
      expect(chain, ['me', 'bob', 'zoe']);
    });

    test('ties: equal chains break by ids, whatever the edge order', () {
      final edges = [
        _e('me', 'raf'),
        _e('raf', 'zoe'),
        _e('me', 'dima'),
        _e('dima', 'zoe'),
      ];
      expect(
        constellationShortestTrustChain(from: 'me', to: 'zoe', edges: edges),
        ['me', 'dima', 'zoe'],
      );
      expect(
        constellationShortestTrustChain(
          from: 'me',
          to: 'zoe',
          edges: edges.reversed,
        ),
        ['me', 'dima', 'zoe'],
      );
    });

    test('a pair with both tiers counts as explicit', () {
      final chain = constellationShortestTrustChain(
        from: 'me',
        to: 'zoe',
        edges: [
          _e('me', 'ann'),
          _e('ann', 'zoe', 2),
          _e('ann', 'zoe'),
          _e('me', 'aaa'),
          _e('aaa', 'zoe', 2),
        ],
      );
      // Both chains have two hops; Ann's is all explicit.
      expect(chain, ['me', 'ann', 'zoe']);
    });

    test('uses only the allowed people', () {
      final edges = [
        _e('me', 'ann'),
        _e('ann', 'zoe'),
        _e('me', 'bob'),
        _e('bob', 'cid'),
        _e('cid', 'zoe'),
      ];
      expect(
        constellationShortestTrustChain(
          from: 'me',
          to: 'zoe',
          edges: edges,
          allowedNodeIds: {'bob', 'cid', 'zoe'},
        ),
        ['me', 'bob', 'cid', 'zoe'],
      );
      expect(
        constellationShortestTrustChain(
          from: 'me',
          to: 'zoe',
          edges: edges,
          allowedNodeIds: {'ann', 'bob'},
        ),
        isNull,
      );
    });

    group('contact nodes without content', () {
      test("the viewer's own edge reaches one", () {
        expect(
          constellationShortestTrustChain(
            from: 'me',
            to: 'olga',
            edges: [_e('me', 'olga')],
            contactOnlyIds: {'olga'},
          ),
          ['me', 'olga'],
        );
      });

      test('no chain passes through one', () {
        expect(
          constellationShortestTrustChain(
            from: 'me',
            to: 'zoe',
            edges: [_e('me', 'olga'), _e('olga', 'zoe')],
            contactOnlyIds: {'olga'},
          ),
          isNull,
        );
      });

      test("nobody else's edge to one counts", () {
        expect(
          constellationShortestTrustChain(
            from: 'me',
            to: 'olga',
            edges: [_e('me', 'ann'), _e('ann', 'olga')],
            contactOnlyIds: {'olga'},
          ),
          isNull,
        );
      });
    });
  });

  group('constellationTrustHops', () {
    test('counts directed steps and skips contact nodes', () {
      final hops = constellationTrustHops(
        from: 'me',
        edges: [
          _e('me', 'ann'),
          _e('ann', 'bob', 2),
          _e('bob', 'cid'),
          _e('me', 'olga'),
          _e('olga', 'dan'),
          _e('eve', 'me'),
        ],
        contactOnlyIds: {'olga'},
      );
      expect(hops, {'me': 0, 'ann': 1, 'olga': 1, 'bob': 2, 'cid': 3});
    });
  });

  test('a found chain names its intermediaries and hops', () {
    const chain = ConstellationTrustChainFound(['me', 'dima', 'raf', 'zoe']);
    expect(chain.intermediaryIds, ['dima', 'raf']);
    expect(chain.hops.toList(), [
      ('me', 'dima'),
      ('dima', 'raf'),
      ('raf', 'zoe'),
    ]);
    expect(
      const ConstellationTrustChainFound(['me', 'zoe']).intermediaryIds,
      isEmpty,
    );
  });
}
