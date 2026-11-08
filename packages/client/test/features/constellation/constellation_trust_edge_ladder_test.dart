// The Field draws one trust edge per pair of people: the strongest type wins
// (mutual trust > direct one-way trust > derived/indirect trust). A selected
// person's chain shows that strongest type on every hop, and the dashed
// "indirect connection" edge from the viewer is only a placeholder for a
// person no chain on the Field can reach.
//
// Every test reads what the rendered scene holds (the graph topology the
// painter draws), after selecting people through the cubit as the Field does.

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_trust_chain_person.dart';
import 'package:tentura/features/constellation/domain/port/constellation_mutual_trust_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_mutual_trust_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';

import '../../support/constellation_store_fixture.dart';

const _ego = 'ego';
final _loadedAt = DateTime.utc(2026, 11, 8, 12);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// The server's mutual-trust answer per person (explicit trust both ways the
/// Field's own edges may not show).
final class _MutualPort implements ConstellationMutualTrustPort {
  _MutualPort(this.answers);

  final Map<String, Set<String>> answers;

  @override
  Future<Set<String>> fetchMutualTrust(String personId) async =>
      answers[personId] ?? const {};
}

/// The server's trust chain per person.
final class _ChainPort implements ConstellationTrustChainPort {
  _ChainPort(this.answers);

  final Map<String, List<ConstellationTrustChainPerson>> answers;

  @override
  Future<List<ConstellationTrustChainPerson>> fetchTrustChain(
    String personId,
  ) async => answers[personId] ?? const [];
}

ConstellationTrustEdgeEntity _e(String src, String dst, {int tier = 1}) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: tier);

/// A Field holding [peers] (each with a Request of their own, so everyone is
/// placed whatever trust reaches them) and [edges].
ConstellationField _field({
  required List<String> peers,
  required List<ConstellationTrustEdgeEntity> edges,
  List<String> directContactIds = const [],
  List<ConstellationTrustEdgeEntity> supportEdges = const [],
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: [
    for (final id in peers) ConstellationPerson(id: id, displayName: id),
  ],
  edges: edges,
  directContactIds: directContactIds,
  requests: [
    for (final id in peers)
      ConstellationRequest(
        id: 'req-$id',
        authorId: id,
        title: 'Request of $id',
        status: 0,
      ),
  ],
  anchorProjection: supportEdges.isEmpty
      ? null
      : ConstellationAnchorProjection(
          revision: ConstellationAnchorProjection.empty.revision,
          anchors: const [],
          pinnedPeers: const [],
          pinnedRequests: const [],
          supportPeers: const [],
          supportEdges: supportEdges,
          serverFilteredBeaconIds: const [],
          serverFilteredBeaconCount: 0,
        ),
);

Future<ConstellationCubit> _load(
  ConstellationField field, {
  Map<String, Set<String>> mutualAnswers = const {},
  Map<String, List<ConstellationTrustChainPerson>>? chainAnswers,
}) async {
  final store = ConstellationStoreFixture(
    _StubRepository(field),
    accountId: _ego,
  ).store;
  final cubit = ConstellationCubit(
    case_: store,
    viewer: const Profile(id: _ego, displayName: 'Ego'),
    mutualTrustCase: ConstellationMutualTrustCase(
      _MutualPort(mutualAnswers),
      env: const Env(),
      logger: Logger('test'),
    ),
    trustChainCase: chainAnswers == null
        ? null
        : ConstellationTrustChainCase(
            _ChainPort(chainAnswers),
            env: const Env(),
            logger: Logger('test'),
          ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

/// Lets the mutual-trust and trust-chain answers land and the scene redraw.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _select(ConstellationCubit cubit, String personId) async {
  cubit.selectPerson(personId);
  await _settle();
}

/// Kinds of every drawn edge between person [x] and person [y], either
/// direction, as `src->dst#kind`.
List<String> _pairEdges(ConstellationCubit cubit, String x, String y) {
  final ids = {'fp:$x', 'fp:$y'};
  return [
    for (final edge
        in cubit.graphController.renderSnapshot.topology.edgesById.values)
      if (ids.contains(edge.payload.source.graphNodeId) &&
          ids.contains(edge.payload.destination.graphNodeId) &&
          edge.payload.source.graphNodeId !=
              edge.payload.destination.graphNodeId)
        edge.payload.semanticId.replaceAll('fp:', ''),
  ]..sort();
}

ConstellationEdgeKind _kindOf(String pairEdge) =>
    ConstellationEdgeKind.values.byName(pairEdge.split('#').last);

/// The single kind drawn between [x] and [y]; fails when there is not exactly
/// one edge.
ConstellationEdgeKind _onlyKind(ConstellationCubit cubit, String x, String y) {
  final edges = _pairEdges(cubit, x, y);
  expect(
    edges,
    hasLength(1),
    reason: 'exactly one edge must join $x and $y, drawn: $edges',
  );
  return _kindOf(edges.single);
}

bool _isDashed(ConstellationEdgeKind kind) {
  final theme = TenturaTheme.light();
  return constellationEdgeStyle(
        kind,
        theme.extension<TenturaTokens>()!,
        theme.colorScheme,
      ).dash >
      0;
}

/// How much the drawn edge `src->dst#kind` between [x] and [y] is faded:
/// 1 when it is drawn at full strength.
double _fadeOf(ConstellationCubit cubit, String x, String y) {
  final drawn = [
    for (final edge
        in cubit.graphController.renderSnapshot.topology.edgesById.values)
      if ({edge.payload.source.id, edge.payload.destination.id}.containsAll({
        x,
        y,
      }))
        edge.payload.semanticId,
  ];
  expect(drawn, hasLength(1), reason: 'one edge joins $x and $y: $drawn');
  return cubit.edgeFadeBySemanticId[drawn.single] ?? 1;
}

/// The viewer is on the scene and drawn at full strength, not dimmed as off
/// a trust chain.
void _expectViewerShownUndimmed(ConstellationCubit cubit) {
  final viewer =
      cubit.graphController.renderSnapshot.topology.nodesById['fp:$_ego'];
  expect(viewer, isNotNull, reason: 'the viewer is on the scene');
  expect(
    cubit.isDimmedByTrustChain(viewer!.payload),
    isFalse,
    reason: 'the viewer is not faded',
  );
}

/// [id] is beyond every chain of trust the Field holds from the viewer (it
/// hangs on the outer ring).
void _expectOnRing(ConstellationCubit cubit, String id) => expect(
  cubit.state.paths!.ring,
  contains(id),
  reason: '$id must be beyond every chain the Field holds for this case',
);

void _expectPersonPlaced(ConstellationCubit cubit, String id) => expect(
  cubit.graphController.renderSnapshot.topology.nodesById.keys,
  contains('fp:$id'),
  reason: '$id must be on the Field for this case',
);

List<List<T>> _permutations<T>(List<T> items) {
  if (items.length <= 1) {
    return [items];
  }
  return [
    for (var i = 0; i < items.length; i++)
      for (final rest in _permutations([
        ...items.sublist(0, i),
        ...items.sublist(i + 1),
      ]))
        [items[i], ...rest],
  ];
}

void main() {
  group('one trust edge per pair, the strongest type wins', () {
    test('mutual trust replaces a one-way trust edge when the Field input '
        'holds both for the same pair', () async {
      // ego ⇄ bea explicitly (the Field's edges), and the same one-way
      // ego → bea again as an anchor support path.
      final cubit = await _load(
        _field(
          peers: ['bea'],
          edges: [_e(_ego, 'bea'), _e('bea', _ego)],
          directContactIds: ['bea'],
          supportEdges: [_e(_ego, 'bea')],
        ),
      );
      _expectPersonPlaced(cubit, 'bea');

      await _select(cubit, 'bea');

      expect(_onlyKind(cubit, _ego, 'bea'), ConstellationEdgeKind.mutualTrust);
    });

    test('mutual trust replaces a derived (indirect) edge when the Field '
        'input holds both for the same pair', () async {
      // bea ⇄ cid explicitly, plus a derived bea → cid support path.
      final cubit = await _load(
        _field(
          peers: ['bea', 'cid'],
          edges: [
            _e(_ego, 'bea'),
            _e(_ego, 'cid'),
            _e('bea', 'cid'),
            _e('cid', 'bea'),
          ],
          directContactIds: ['bea', 'cid'],
          supportEdges: [_e('bea', 'cid', tier: 2)],
        ),
      );

      await _select(cubit, 'bea');

      expect(_onlyKind(cubit, 'bea', 'cid'), ConstellationEdgeKind.mutualTrust);
    });

    test(
      'mutual trust the server reports replaces the one-way trust edge the '
      'Field shows',
      () async {
        // The Field shows only ego → bea; the server knows bea trusts ego back.
        final cubit = await _load(
          _field(
            peers: ['bea'],
            edges: [_e(_ego, 'bea')],
            directContactIds: ['bea'],
          ),
          mutualAnswers: {
            'bea': {_ego},
          },
        );
        _expectPersonPlaced(cubit, 'bea');

        await _select(cubit, 'bea');

        expect(
          _onlyKind(cubit, _ego, 'bea'),
          ConstellationEdgeKind.mutualTrust,
        );
      },
    );

    test(
      'mutual trust the server reports replaces the derived edge the Field '
      'shows',
      () async {
        // The Field shows only a derived bea → cid; the server knows the two
        // trust each other explicitly.
        final cubit = await _load(
          _field(
            peers: ['bea', 'cid'],
            edges: [
              _e(_ego, 'bea'),
              _e(_ego, 'cid'),
              _e('bea', 'cid', tier: 2),
            ],
            directContactIds: ['bea', 'cid'],
          ),
          mutualAnswers: {
            'bea': {'cid'},
          },
        );

        await _select(cubit, 'bea');

        expect(
          _onlyKind(cubit, 'bea', 'cid'),
          ConstellationEdgeKind.mutualTrust,
        );
      },
    );

    test('a direct one-way trust edge replaces a derived edge on the same '
        'pair', () async {
      // dan trusts ann explicitly; ann reaches dan only by derived trust.
      final cubit = await _load(
        _field(
          peers: ['ann', 'dan'],
          edges: [
            _e(_ego, 'ann'),
            _e(_ego, 'dan'),
            _e('dan', 'ann'),
            _e('ann', 'dan', tier: 2),
          ],
          directContactIds: ['ann', 'dan'],
        ),
      );

      await _select(cubit, 'dan');

      expect(_onlyKind(cubit, 'ann', 'dan'), ConstellationEdgeKind.tier1Path);
    });

    test('explicit trust both ways is one mutual trust edge, not two one-way '
        'edges', () async {
      final cubit = await _load(
        _field(
          peers: ['ann', 'ben'],
          edges: [
            _e(_ego, 'ann'),
            _e(_ego, 'ben'),
            _e('ann', 'ben'),
            _e('ben', 'ann'),
          ],
          directContactIds: ['ann', 'ben'],
        ),
      );

      await _select(cubit, 'ann');

      expect(_onlyKind(cubit, 'ann', 'ben'), ConstellationEdgeKind.mutualTrust);
    });

    group('a pair with a single trust type keeps exactly that type', () {
      test('mutual trust only', () async {
        // No edge between bea and cid on the Field; the server says mutual.
        final cubit = await _load(
          _field(
            peers: ['bea', 'cid'],
            edges: [_e(_ego, 'bea'), _e(_ego, 'cid')],
            directContactIds: ['bea', 'cid'],
          ),
          mutualAnswers: {
            'bea': {'cid'},
          },
        );

        await _select(cubit, 'bea');

        expect(
          _onlyKind(cubit, 'bea', 'cid'),
          ConstellationEdgeKind.mutualTrust,
        );
      });

      test('direct one-way trust only', () async {
        final cubit = await _load(
          _field(
            peers: ['ann', 'dan'],
            edges: [_e(_ego, 'ann'), _e(_ego, 'dan'), _e('dan', 'ann')],
            directContactIds: ['ann', 'dan'],
          ),
        );

        await _select(cubit, 'dan');

        expect(
          _onlyKind(cubit, 'ann', 'dan'),
          ConstellationEdgeKind.tier1Path,
        );
      });

      test('derived (indirect) trust only', () async {
        final cubit = await _load(
          _field(
            peers: ['ann', 'dan'],
            edges: [
              _e(_ego, 'ann'),
              _e(_ego, 'dan'),
              _e('dan', 'ann', tier: 2),
            ],
            directContactIds: ['ann', 'dan'],
          ),
        );

        await _select(cubit, 'dan');

        expect(
          _onlyKind(cubit, 'ann', 'dan'),
          ConstellationEdgeKind.tier2Path,
        );
      });
    });

    test(
      'the pair resolves the same whatever order its edges arrive in',
      () async {
        final pairEdges = [
          _e('ann', 'ben'),
          _e('ben', 'ann'),
          _e('ben', 'ann', tier: 2),
        ];
        final drawn = <String, List<String>>{};
        for (final order in _permutations(pairEdges)) {
          final cubit = await _load(
            _field(
              peers: ['ann', 'ben'],
              edges: [_e(_ego, 'ann'), _e(_ego, 'ben'), ...order],
              directContactIds: ['ann', 'ben'],
            ),
          );
          await _select(cubit, 'ann');
          drawn[order.map((e) => '${e.src}>${e.dst}:${e.tier}').join(' ')] =
              _pairEdges(cubit, 'ann', 'ben');
        }

        expect(drawn, hasLength(6), reason: 'every order of 3 edges is fed');

        for (final entry in drawn.entries) {
          expect(
            entry.value.map(_kindOf).toList(),
            [ConstellationEdgeKind.mutualTrust],
            reason: 'input order ${entry.key} drew ${entry.value}',
          );
        }
      },
    );
  });

  group('the chain Ego ⇄ Alice ⇄ Bob shows mutual trust on both hops', () {
    // Explicit trust both ways on Ego–Alice and on Alice–Bob, no explicit
    // trust between Ego and Bob. Bob trusts Ego only by derived trust, which
    // is what drew the dashed Ego–Bob edge.
    ConstellationField chainField() => _field(
      peers: ['alice', 'bob'],
      edges: [
        _e(_ego, 'alice'),
        _e('alice', _ego),
        _e('alice', 'bob'),
        _e('bob', 'alice'),
        _e('bob', _ego, tier: 2),
      ],
      directContactIds: ['alice'],
    );

    for (final selected in ['alice', 'bob']) {
      test('selecting $selected draws one mutual trust edge on Ego–Alice and '
          'on Alice–Bob, and nothing between Ego and Bob', () async {
        final cubit = await _load(chainField());
        _expectPersonPlaced(cubit, 'alice');
        _expectPersonPlaced(cubit, 'bob');

        await _select(cubit, selected);

        expect(
          _onlyKind(cubit, _ego, 'alice'),
          ConstellationEdgeKind.mutualTrust,
        );
        expect(
          _onlyKind(cubit, 'alice', 'bob'),
          ConstellationEdgeKind.mutualTrust,
        );
        expect(
          _pairEdges(cubit, _ego, 'bob'),
          isEmpty,
          reason: 'Bob is reached through Alice: no indirect edge to him',
        );
      });
    }

    test('with only the server naming the chain Ego → Alice → Bob, selecting '
        'Bob draws both hops of that chain and no indirect Ego–Bob '
        'edge', () async {
      // The Field holds no edge between Alice and Bob and the server reports
      // no mutual trust for Bob, so the Alice → Bob hop can come only from
      // the server's chain. Bob trusts Ego only by derived trust, which
      // reaches nobody from Ego: Bob is beyond every chain the Field holds.
      final cubit = await _load(
        _field(
          peers: ['alice', 'bob'],
          edges: [
            _e(_ego, 'alice'),
            _e('alice', _ego),
            _e('bob', _ego, tier: 2),
          ],
          directContactIds: ['alice'],
        ),
        chainAnswers: {
          'bob': const [
            ConstellationTrustChainPerson(id: _ego, displayName: 'Ego'),
            ConstellationTrustChainPerson(id: 'alice', displayName: 'Alice'),
            ConstellationTrustChainPerson(id: 'bob', displayName: 'Bob'),
          ],
        },
      );
      _expectPersonPlaced(cubit, 'alice');
      _expectOnRing(cubit, 'bob');
      expect(
        cubit.state.field!.edges.where(
          (e) => {e.src, e.dst}.containsAll({'alice', 'bob'}),
        ),
        isEmpty,
        reason: 'the Field itself holds no edge between Alice and Bob',
      );

      await _select(cubit, 'bob');

      expect(
        _onlyKind(cubit, _ego, 'alice'),
        ConstellationEdgeKind.mutualTrust,
        reason: 'the first hop, with the mutual trust the Field shows',
      );
      expect(
        _onlyKind(cubit, 'alice', 'bob'),
        ConstellationEdgeKind.tier1Path,
        reason: "the last hop, drawn from the server's chain alone",
      );
      expect(
        _pairEdges(cubit, _ego, 'bob'),
        isEmpty,
        reason: 'Bob is reached through Alice: no indirect edge to him',
      );
    });
  });

  group('the dashed indirect edge is a placeholder for an unreachable '
      'person', () {
    test('a person no trust chain on the Field reaches gets one dashed edge '
        'from Ego', () async {
      final cubit = await _load(
        _field(
          peers: ['alice', 'carol'],
          edges: [_e(_ego, 'alice'), _e('alice', _ego)],
          directContactIds: ['alice'],
        ),
        chainAnswers: const {},
      );
      _expectPersonPlaced(cubit, 'carol');

      await _select(cubit, 'carol');

      final kind = _onlyKind(cubit, _ego, 'carol');
      expect(_isDashed(kind), isTrue, reason: 'drawn as $kind');
    });

    test('a person reached only through people not on the Field gets one '
        'dashed edge from Ego and no chain edges', () async {
      // The server's chain Ego → Alice → Xenia → Fay passes Xenia, who is on
      // no Field. Ego trusts Alice one way only, so the only edge Ego–Alice
      // could get is the chain's own first hop.
      final cubit = await _load(
        _field(
          peers: ['alice', 'fay'],
          edges: [_e(_ego, 'alice')],
          directContactIds: ['alice'],
        ),
        chainAnswers: {
          'fay': const [
            ConstellationTrustChainPerson(id: _ego, displayName: 'Ego'),
            ConstellationTrustChainPerson(id: 'alice', displayName: 'Alice'),
            ConstellationTrustChainPerson(id: 'xenia', displayName: 'Xenia'),
            ConstellationTrustChainPerson(id: 'fay', displayName: 'Fay'),
          ],
        },
      );
      _expectPersonPlaced(cubit, 'fay');

      await _select(cubit, 'fay');

      final kind = _onlyKind(cubit, _ego, 'fay');
      expect(_isDashed(kind), isTrue, reason: 'drawn as $kind');
      // The chain cannot be shown, so none of its hops is drawn: neither
      // Ego → Alice nor anything from Alice towards Fay.
      expect(
        _pairEdges(cubit, _ego, 'alice'),
        isEmpty,
        reason: 'the placeholder replaces the whole chain, no first hop',
      );
      expect(_pairEdges(cubit, 'alice', 'fay'), isEmpty);
      expect(
        cubit.graphController.renderSnapshot.topology.nodesById.keys,
        isNot(contains('fp:xenia')),
      );
    });

    test('the dashed edge to a person no chain reaches is drawn at full '
        'strength', () async {
      final cubit = await _load(
        _field(
          peers: ['alice', 'carol'],
          edges: [_e(_ego, 'alice'), _e('alice', _ego)],
          directContactIds: ['alice'],
        ),
        chainAnswers: const {},
      );
      _expectOnRing(cubit, 'carol');

      await _select(cubit, 'carol');

      final kind = _onlyKind(cubit, _ego, 'carol');
      expect(_isDashed(kind), isTrue, reason: 'drawn as $kind');
      expect(_fadeOf(cubit, _ego, 'carol'), 1, reason: 'not faded');
    });

    test('a chain through someone not on the Field counts as no chain: the '
        'dashed edge to the person is drawn at full strength', () async {
      final cubit = await _load(
        _field(
          peers: ['alice', 'fay'],
          edges: [_e(_ego, 'alice')],
          directContactIds: ['alice'],
        ),
        chainAnswers: {
          'fay': const [
            ConstellationTrustChainPerson(id: _ego, displayName: 'Ego'),
            ConstellationTrustChainPerson(id: 'alice', displayName: 'Alice'),
            ConstellationTrustChainPerson(id: 'xenia', displayName: 'Xenia'),
            ConstellationTrustChainPerson(id: 'fay', displayName: 'Fay'),
          ],
        },
      );
      _expectOnRing(cubit, 'fay');

      await _select(cubit, 'fay');

      final kind = _onlyKind(cubit, _ego, 'fay');
      expect(_isDashed(kind), isTrue, reason: 'drawn as $kind');
      expect(
        _fadeOf(cubit, _ego, 'fay'),
        1,
        reason: 'no chain is drawn, so nothing is faded as off the chain',
      );
      _expectViewerShownUndimmed(cubit);
    });

    test('a chain through someone not on the Field counts as no chain: the '
        "person's own trust edge to the viewer is drawn instead of the "
        'dashed edge', () async {
      // Fay trusts the viewer by derived trust; the viewer reaches Fay only
      // through Xenia, who is on no Field.
      final cubit = await _load(
        _field(
          peers: ['alice', 'fay'],
          edges: [_e(_ego, 'alice'), _e('fay', _ego, tier: 2)],
          directContactIds: ['alice'],
        ),
        chainAnswers: {
          'fay': const [
            ConstellationTrustChainPerson(id: _ego, displayName: 'Ego'),
            ConstellationTrustChainPerson(id: 'alice', displayName: 'Alice'),
            ConstellationTrustChainPerson(id: 'xenia', displayName: 'Xenia'),
            ConstellationTrustChainPerson(id: 'fay', displayName: 'Fay'),
          ],
        },
      );
      _expectOnRing(cubit, 'fay');

      await _select(cubit, 'fay');

      expect(_onlyKind(cubit, _ego, 'fay'), ConstellationEdgeKind.tier2Path);
      expect(_fadeOf(cubit, _ego, 'fay'), 1, reason: 'not faded');
      _expectViewerShownUndimmed(cubit);
    });
  });

  group('a person beyond every chain on the Field (on the outer ring) gets '
      'one edge from the viewer, of the strongest type', () {
    for (final (label, edges, mutual, expected) in [
      (
        'mutual trust the server reports',
        <ConstellationTrustEdgeEntity>[],
        {
          'rae': {_ego},
        },
        ConstellationEdgeKind.mutualTrust,
      ),
      (
        'direct one-way trust towards the viewer',
        [_e('rae', _ego)],
        <String, Set<String>>{},
        ConstellationEdgeKind.tier1Path,
      ),
      (
        'derived trust towards the viewer',
        [_e('rae', _ego, tier: 2)],
        <String, Set<String>>{},
        ConstellationEdgeKind.tier2Path,
      ),
    ]) {
      test('with $label: exactly one edge, of that type, and no dashed '
          'placeholder beside it', () async {
        final cubit = await _load(
          _field(peers: ['rae'], edges: edges),
          mutualAnswers: mutual,
          chainAnswers: const {},
        );
        _expectOnRing(cubit, 'rae');

        await _select(cubit, 'rae');

        expect(_onlyKind(cubit, _ego, 'rae'), expected);
      });
    }

    test('one-way trust from the viewer to the person takes the person off '
        'the outer ring: one direct edge and no dashed placeholder', () async {
      // A ring person can never be one the viewer trusts: any viewer → person
      // edge the Field holds reaches the person in one hop. This pins that
      // such a person gets the direct edge alone.
      final cubit = await _load(
        _field(peers: ['rae'], edges: [_e(_ego, 'rae')]),
        chainAnswers: const {},
      );
      _expectPersonPlaced(cubit, 'rae');
      expect(
        cubit.state.paths!.ring,
        isNot(contains('rae')),
        reason: 'the viewer reaches rae in one hop',
      );

      await _select(cubit, 'rae');

      expect(_onlyKind(cubit, _ego, 'rae'), ConstellationEdgeKind.tier1Path);
    });

    test('reached by a local chain longer than three hops: the chain is '
        'drawn and no dashed edge from the viewer', () async {
      final cubit = await _load(
        _field(
          peers: ['a', 'b', 'c', 'd'],
          edges: [_e(_ego, 'a'), _e('a', 'b'), _e('b', 'c'), _e('c', 'd')],
          directContactIds: ['a'],
        ),
        chainAnswers: const {},
      );
      for (final id in ['a', 'b', 'c']) {
        _expectPersonPlaced(cubit, id);
      }
      _expectOnRing(cubit, 'd');

      await _select(cubit, 'd');

      for (final (x, y) in [(_ego, 'a'), ('a', 'b'), ('b', 'c'), ('c', 'd')]) {
        expect(
          _onlyKind(cubit, x, y),
          ConstellationEdgeKind.tier1Path,
          reason: 'the chain hop $x → $y is drawn',
        );
      }
      expect(
        _pairEdges(cubit, _ego, 'd'),
        isEmpty,
        reason: 'd is reached through the chain: no dashed edge to d',
      );
    });

    test('reached by a chain only the server names: the chain is drawn and '
        'no dashed edge from the viewer', () async {
      final cubit = await _load(
        _field(
          peers: ['alice', 'bob'],
          edges: [_e(_ego, 'alice')],
          directContactIds: ['alice'],
        ),
        chainAnswers: {
          'bob': const [
            ConstellationTrustChainPerson(id: _ego, displayName: 'Ego'),
            ConstellationTrustChainPerson(id: 'alice', displayName: 'Alice'),
            ConstellationTrustChainPerson(id: 'bob', displayName: 'Bob'),
          ],
        },
      );
      _expectPersonPlaced(cubit, 'alice');
      _expectOnRing(cubit, 'bob');

      await _select(cubit, 'bob');

      expect(_onlyKind(cubit, _ego, 'alice'), ConstellationEdgeKind.tier1Path);
      expect(_onlyKind(cubit, 'alice', 'bob'), ConstellationEdgeKind.tier1Path);
      expect(
        _pairEdges(cubit, _ego, 'bob'),
        isEmpty,
        reason: 'Bob is reached through Alice: no dashed edge to him',
      );
    });
  });
}
