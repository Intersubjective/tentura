// Selecting a Request or a Post on the Field draws the path to its author
// and the item's own edges, never anyone's whole trust fan:
//
// * the viewer's own Request or Post shows only the viewer → item edge and the
//   item → participant edges, even when the viewer trusts other people on
//   the Field directly;
// * when the server names the trust chain to the selected item's author only
//   after the selection was drawn, the Field redraws with that chain, for a
//   Post as for a Request, with no further user action.
//
// Every test reads what the rendered scene holds (the graph topology the
// painter draws), after selecting items through the cubit as the Field does.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_trust_chain_person.dart';
import 'package:tentura/features/constellation/domain/port/constellation_member_webs_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_mutual_trust_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_member_webs_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_mutual_trust_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

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

final class _MutualPort implements ConstellationMutualTrustPort {
  _MutualPort(this.answers);

  final Map<String, Set<String>> answers;

  @override
  Future<Set<String>> fetchMutualTrust(String personId) async =>
      answers[personId] ?? const {};
}

/// The server's trust chain per person, answered only when the test
/// completes that person's answer.
final class _LateChainPort implements ConstellationTrustChainPort {
  final Map<String, Completer<List<ConstellationTrustChainPerson>>> answers =
      {};

  Completer<List<ConstellationTrustChainPerson>> answerFor(String personId) =>
      answers.putIfAbsent(personId, Completer.new);

  @override
  Future<List<ConstellationTrustChainPerson>> fetchTrustChain(
    String personId,
  ) => answerFor(personId).future;
}

/// Who is inside or was forwarded each Request.
final class _MemberWebsPort implements ConstellationMemberWebsPort {
  _MemberWebsPort(this.websByBeaconId);

  final Map<String, List<ConstellationMemberWeb>> websByBeaconId;

  @override
  Future<List<ConstellationMemberWeb>> fetch(String beaconId) async =>
      websByBeaconId[beaconId] ?? const [];
}

ConstellationTrustEdgeEntity _e(String src, String dst, {int tier = 1}) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: tier);

ConstellationRequest _request(String id, String authorId) =>
    ConstellationRequest(
      id: id,
      authorId: authorId,
      title: 'Request $id',
      status: 0,
    );

ConstellationPost _post(String id, String authorId) => ConstellationPost(
  id: id,
  authorId: authorId,
  rootExcerpt: 'Post $id',
  lastActivityAt: _loadedAt.subtract(const Duration(hours: 1)),
);

Future<ConstellationCubit> _load(
  ConstellationField field, {
  Map<String, Set<String>> mutualAnswers = const {},
  _LateChainPort? chainPort,
  Map<String, List<ConstellationMemberWeb>> requestWebs = const {},
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
    trustChainCase: chainPort == null
        ? null
        : ConstellationTrustChainCase(
            chainPort,
            env: const Env(),
            logger: Logger('test'),
          ),
    memberWebsCase: ConstellationMemberWebsCase(
      _MemberWebsPort(requestWebs),
      env: const Env(),
      logger: Logger('test'),
    ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits (bounded) until [condition] holds.
Future<void> _until(bool Function() condition, String what) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'never reached: $what');
}

typedef _Drawn = ({String src, String dst, ConstellationEdgeKind kind});

/// Every edge of the rendered scene, by raw node ids and kind.
List<_Drawn> _drawn(ConstellationCubit cubit) => [
  for (final edge
      in cubit.graphController.renderSnapshot.topology.edgesById.values)
    (
      src: edge.payload.source.id,
      dst: edge.payload.destination.id,
      kind: ConstellationEdgeKind.values.byName(
        edge.payload.semanticId.split('#').last,
      ),
    ),
];

Set<String> _personIds(ConstellationCubit cubit) => {
  _ego,
  ...?cubit.state.field?.peers.map((p) => p.id),
};

/// Every drawn edge joining two people, as `src->dst#kind`.
List<String> _personEdges(ConstellationCubit cubit) {
  final people = _personIds(cubit);
  return [
    for (final e in _drawn(cubit))
      if (people.contains(e.src) && people.contains(e.dst) && e.src != e.dst)
        '${e.src}->${e.dst}#${e.kind.name}',
  ]..sort();
}

/// Drawn edges between person [x] and person [y], either direction.
List<String> _pairEdges(ConstellationCubit cubit, String x, String y) => [
  for (final e in _drawn(cubit))
    if ({e.src, e.dst}.containsAll({x, y}) && x != y)
      '${e.src}->${e.dst}#${e.kind.name}',
]..sort();

bool _hasEdge(
  ConstellationCubit cubit,
  String src,
  String dst,
  ConstellationEdgeKind kind,
) => _drawn(
  cubit,
).any((e) => e.src == src && e.dst == dst && e.kind == kind);

void _expectPlaced(ConstellationCubit cubit, Iterable<String> ids) => expect(
  cubit.graphController.renderSnapshot.topology.nodesById.values
      .map((n) => n.payload.id)
      .toSet(),
  containsAll(ids),
  reason: '$ids must all be on the Field for this case',
);

void main() {
  group("selecting the viewer's own item draws only the item's edges, not "
      "the viewer's trust fan", () {
    // The viewer trusts Bea one way and Cid both ways; both are on the Field
    // with Requests of their own. Bea is inside the viewer's item.
    final people = [
      const ConstellationPerson(id: 'bea', displayName: 'Bea'),
      const ConstellationPerson(id: 'cid', displayName: 'Cid'),
    ];
    final edges = [_e(_ego, 'bea'), _e(_ego, 'cid'), _e('cid', _ego)];

    test("the viewer's own Request: viewer → Request and Request → "
        'participant only', () async {
      final cubit = await _load(
        ConstellationField(
          loadedAt: _loadedAt,
          context: '',
          peers: people,
          edges: edges,
          directContactIds: const ['bea', 'cid'],
          requests: [
            _request('req-ego', _ego),
            _request('req-bea', 'bea'),
            _request('req-cid', 'cid'),
          ],
        ),
        requestWebs: const {
          'req-ego': [
            ConstellationMemberWeb(
              beaconId: 'req-ego',
              personId: 'bea',
              state: ConstellationMemberWebState.inside,
            ),
          ],
        },
      );
      _expectPlaced(cubit, ['req-ego', 'bea', 'cid']);

      cubit.selectRequest('req-ego');
      await _until(
        () => _hasEdge(
          cubit,
          'req-ego',
          'bea',
          ConstellationEdgeKind.webInside,
        ),
        'the Request → participant edge',
      );
      await _settle();

      expect(
        _hasEdge(cubit, _ego, 'req-ego', ConstellationEdgeKind.attachment),
        isTrue,
        reason: 'the viewer → own Request edge is drawn',
      );
      expect(
        _personEdges(cubit),
        isEmpty,
        reason:
            "no trust edge between people: the viewer's own Request "
            "does not show the viewer's trust fan",
      );
    });

    test("the viewer's own Post: viewer → Post and Post → participant "
        'only', () async {
      final cubit = await _load(
        ConstellationField(
          loadedAt: _loadedAt,
          context: '',
          peers: people,
          edges: edges,
          directContactIds: const ['bea', 'cid'],
          requests: [_request('req-bea', 'bea'), _request('req-cid', 'cid')],
          posts: [_post('post-ego', _ego)],
          memberWebs: const [
            ConstellationMemberWeb(
              beaconId: 'post-ego',
              personId: 'bea',
              state: ConstellationMemberWebState.forwarded,
            ),
          ],
        ),
      );
      _expectPlaced(cubit, ['post-ego', 'bea', 'cid']);

      // The Field selects a Post the same way as a Request.
      cubit.selectRequest('post-ego');
      await _until(
        () => _hasEdge(
          cubit,
          'post-ego',
          'bea',
          ConstellationEdgeKind.webForwarded,
        ),
        'the Post → participant edge',
      );
      await _settle();

      expect(
        _hasEdge(cubit, _ego, 'post-ego', ConstellationEdgeKind.attachment),
        isTrue,
        reason: 'the viewer → own Post edge is drawn',
      );
      expect(
        _personEdges(cubit),
        isEmpty,
        reason:
            "no trust edge between people: the viewer's own Post does not "
            "show the viewer's trust fan",
      );
    });
  });

  group('a trust chain the server names after the selection was drawn is '
      'drawn without another action', () {
    // The viewer trusts Alice; nothing on the Field leads on to Bob, so only
    // the server can name the chain Ego → Alice → Bob.
    ConstellationField field({
      List<ConstellationRequest> requests = const [],
      List<ConstellationPost> posts = const [],
    }) => ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      peers: const [
        ConstellationPerson(id: 'alice', displayName: 'Alice'),
        ConstellationPerson(id: 'bob', displayName: 'Bob'),
      ],
      edges: [_e(_ego, 'alice')],
      directContactIds: const ['alice'],
      requests: [_request('req-alice', 'alice'), ...requests],
      posts: posts,
    );

    const chain = [
      ConstellationTrustChainPerson(id: _ego, displayName: 'Ego'),
      ConstellationTrustChainPerson(id: 'alice', displayName: 'Alice'),
      ConstellationTrustChainPerson(id: 'bob', displayName: 'Bob'),
    ];

    for (final (label, itemId, f) in [
      ('Post', 'post-bob', field(posts: [_post('post-bob', 'bob')])),
      (
        'Request',
        'req-bob',
        field(requests: [_request('req-bob', 'bob')]),
      ),
    ]) {
      test('a selected $label: the chain to its author arriving late is '
          'drawn hop by hop', () async {
        final chainPort = _LateChainPort();
        final cubit = await _load(f, chainPort: chainPort);
        _expectPlaced(cubit, ['alice', 'bob', itemId]);

        // Posts and Requests are both selected through selectRequest.
        cubit.selectRequest(itemId);
        await _until(
          () =>
              _hasEdge(cubit, 'bob', itemId, ConstellationEdgeKind.attachment),
          'the author → $label edge',
        );
        await _settle();
        expect(
          chainPort.answers.keys,
          contains('bob'),
          reason: "the server was asked for the $label author's chain",
        );
        expect(
          _pairEdges(cubit, 'alice', 'bob'),
          isEmpty,
          reason: 'before the answer no chain is drawn',
        );

        final emitted = <ConstellationState>[];
        final subscription = cubit.stream.listen(emitted.add);
        addTearDown(subscription.cancel);

        chainPort.answerFor('bob').complete(chain);
        await _settle();

        expect(
          emitted,
          isNotEmpty,
          reason:
              'the cubit emits a new state once the chain arrives, so '
              'everything reading the selection rebuilds',
        );

        expect(
          _pairEdges(cubit, _ego, 'alice'),
          [
            '$_ego->alice#${ConstellationEdgeKind.tier1Path.name}',
          ],
          reason: 'the first hop of the chain is drawn',
        );
        expect(
          _pairEdges(cubit, 'alice', 'bob'),
          ['alice->bob#${ConstellationEdgeKind.tier1Path.name}'],
          reason: 'the last hop of the chain, to the $label author, is drawn',
        );
      });
    }
  });
}
