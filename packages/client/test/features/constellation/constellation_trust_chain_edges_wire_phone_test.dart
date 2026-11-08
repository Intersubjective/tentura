@TestOn('vm')
library;

// Real path for the chain Ego ⇄ Alice ⇄ Bob: the Field, mutual-trust and
// trust-chain responses go through the real transport, GraphQL mappers and
// repositories into the Field cubit (wired with the production use cases).
// Selecting Alice, then Bob, must show one mutual trust (double blue) edge on
// Ego–Alice and on Alice–Bob, no grey edge beside them, and no dashed Ego–Bob
// edge. The same chain is then mounted on a 375x667 phone in Russian, and the
// mounted Field's edge painter must style each hop as one double (twin),
// solid edge in the primary colour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_mutual_trust_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_trust_chain_repository.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_mutual_trust_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Я');
const _alice = 'Ualice0000001';
const _bob = 'Ubob000000001';

Map<String, dynamic> _peer(String id, String displayName) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'pinState': null,
  'contactOnly': false,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'displayName': displayName,
  'handle': null,
  'isNew': false,
  'image': null,
};

Map<String, dynamic> _edge(String src, String dst, int tier) => {
  '__typename': 'v2_ConstellationEdge',
  'src': src,
  'dst': dst,
  'tier': tier,
};

/// Explicit trust both ways on Ego–Alice and Alice–Bob; Bob trusts Ego only
/// by derived (tier 2) trust.
Map<String, dynamic> _fieldResponse() => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-08T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': [_alice],
    'peers': [
      _peer(_alice, 'Алиса Длиннофамильная-Константинопольская'),
      _peer(_bob, 'Борис'),
    ],
    'edges': [
      _edge(_viewer.id, _alice, 1),
      _edge(_alice, _viewer.id, 1),
      _edge(_alice, _bob, 1),
      _edge(_bob, _alice, 1),
      _edge(_bob, _viewer.id, 2),
    ],
    'requests': <dynamic>[],
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '0',
      'anchors': <dynamic>[],
      'pinnedPeers': <dynamic>[],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

/// What the server answers each person's mutual-trust and trust-chain query
/// with, for the same chain.
Map<String, dynamic> _wireAnswer(WireSent request) {
  final personId = request.variables['personId'] as String?;
  return switch (request.operationName) {
    'ConstellationFieldFetch' => _fieldResponse(),
    'ConstellationMutualTrustFetch' => {
      '__typename': 'query_root',
      'constellationMutualTrust': switch (personId) {
        _alice => [_viewer.id, _bob],
        _bob => [_alice],
        _ => <String>[],
      },
    },
    'ConstellationTrustChainFetch' => {
      '__typename': 'query_root',
      'constellationTrustChain': [
        for (final (id, name) in [
          (_viewer.id, 'Я'),
          if (personId == _bob) (_alice, 'Алиса'),
          if (personId != null) (personId, 'Человек'),
        ])
          {
            '__typename': 'v2_ConstellationTrustChainPerson',
            'userId': id,
            'displayName': name,
          },
      ],
    },
    _ => throw StateError('unexpected operation ${request.operationName}'),
  };
}

/// Every drawn edge between person [x] and person [y], either direction, as
/// `src->dst#kind`.
List<String> _pairEdges(ConstellationCubit cubit, String x, String y) {
  final ids = {'fp:$x', 'fp:$y'};
  return [
    for (final edge in _pairEdgeDetails(cubit, ids)) edge.semanticId,
  ]..sort();
}

List<EdgeDetails> _pairEdgeDetails(
  ConstellationCubit cubit,
  Set<String> ids,
) => [
  for (final edge
      in cubit.graphController.renderSnapshot.topology.edgesById.values)
    if (ids.contains(edge.payload.source.graphNodeId) &&
        ids.contains(edge.payload.destination.graphNodeId) &&
        edge.payload.source.graphNodeId != edge.payload.destination.graphNodeId)
      edge.payload,
];

void _expectPeopleOnField(ConstellationCubit cubit) => expect(
  cubit.graphController.renderSnapshot.topology.nodesById.keys,
  containsAll(['fp:${_viewer.id}', 'fp:$_alice', 'fp:$_bob']),
  reason: 'Ego, Alice and Bob must all be on the Field',
);

void _expectChainDrawnAsMutualTrust(ConstellationCubit cubit, String label) {
  for (final (x, y, pair) in [
    (_viewer.id, _alice, 'Ego–Alice'),
    (_alice, _bob, 'Alice–Bob'),
  ]) {
    final drawn = _pairEdges(cubit, x, y);
    expect(
      drawn,
      hasLength(1),
      reason: '$label: exactly one edge on $pair, drawn $drawn',
    );
    expect(
      drawn.single,
      endsWith('#mutualTrust'),
      reason: '$label: $pair is mutual trust',
    );
  }
  expect(
    _pairEdges(cubit, _viewer.id, _bob),
    isEmpty,
    reason: '$label: Bob is reached through Alice, no indirect Ego–Bob edge',
  );
}

/// The mounted Field paints [pair] as one double blue edge: the kind the
/// mounted edge painter looks up for each edge of the pair, styled with the
/// painter's own tokens and colour scheme, is a twin (two parallel strokes),
/// solid line in the primary colour, and there is exactly one such edge.
void _expectDoubleBlue(
  WidgetTester tester,
  ConstellationCubit cubit,
  (String, String) pair,
  String label,
) {
  final painter =
      tester
              .widget<GraphView<dynamic, dynamic>>(
                find.byWidgetPredicate((w) => w is GraphView),
              )
              .edgePainter
          as ConstellationEdgePainter;
  final edges = _pairEdgeDetails(cubit, {'fp:${pair.$1}', 'fp:${pair.$2}'});
  final kinds = [
    for (final edge in edges) painter.edgeKindByPair[edge.semanticId],
  ];
  expect(
    kinds,
    hasLength(1),
    reason:
        '$label: the painter draws one edge on ${pair.$1}–${pair.$2}, '
        'got $kinds',
  );
  expect(kinds.single, isNotNull, reason: '$label: the painter knows it');
  final style = constellationEdgeStyle(
    kinds.single!,
    painter.tt,
    painter.scheme,
  );
  expect(style.twin, isTrue, reason: '$label: two parallel strokes');
  expect(style.dash, 0, reason: '$label: solid, not dashed');
  expect(
    style.color,
    painter.scheme.primary,
    reason: '$label: the primary (blue) colour',
  );
  expect(
    painter.scheme.primary,
    Theme.of(
      tester.element(find.byType(ConstellationBody)),
    ).colorScheme.primary,
    reason: 'the painter uses the mounted theme',
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('the chain from the server is drawn as mutual trust on both hops, '
      'with Alice and then Bob selected', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      const {},
      sent,
      responseFor: (request) async => _wireAnswer(request),
      (remote) async {
        final store = ConstellationStoreFixture(
          ConstellationRepository(remote),
          accountId: _viewer.id,
        );
        await store.ready();
        final cubit = ConstellationCubit(
          case_: store.store,
          viewer: _viewer,
          mutualTrustCase: ConstellationMutualTrustCase(
            ConstellationMutualTrustRepository(remote),
            env: const Env(),
            logger: Logger('test'),
          ),
          trustChainCase: ConstellationTrustChainCase(
            ConstellationTrustChainRepository(remote),
            env: const Env(),
            logger: Logger('test'),
          ),
        );
        try {
          await cubit.stream
              .firstWhere((state) => state.status is StateIsSuccess)
              .timeout(const Duration(seconds: 15));
          _expectPeopleOnField(cubit);

          for (final (personId, label) in [
            (_alice, 'Alice selected'),
            (_bob, 'Bob selected'),
          ]) {
            cubit.selectPerson(personId);
            await _settle();
            expect(
              sent.where(
                (r) =>
                    r.operationName == 'ConstellationMutualTrustFetch' &&
                    r.variables['personId'] == personId,
              ),
              isNotEmpty,
              reason: '$label: the production mutual-trust query was sent',
            );
            _expectChainDrawnAsMutualTrust(cubit, label);
          }
        } finally {
          await cubit.close();
        }
      },
    );
  });

  for (final selections in [
    [_alice, _bob],
    [_bob],
  ]) {
    final names = selections
        .map((id) => id == _alice ? 'Alice' : 'Bob')
        .join(', then ');
    testWidgets('on a 375x667 phone in Russian the Field draws Ego ⇄ Alice ⇄ '
        'Bob as double blue edges when selecting $names', (tester) async {
      await usePhoneSurface(tester);
      final sent = <WireSent>[];
      late ConstellationCubit cubit;
      await tester.runAsync(
        () => withRemoteWire(
          {'ConstellationFieldFetch': _fieldResponse()},
          sent,
          (remote) async {
            final store = ConstellationStoreFixture(
              ConstellationRepository(remote),
              accountId: _viewer.id,
            );
            cubit = store.createCubit(viewer: _viewer);
            await store.ready();
            await cubit.load().timeout(const Duration(seconds: 15));
          },
        ),
      );
      expect(
        sent.map((request) => request.operationName),
        contains('ConstellationFieldFetch'),
      );

      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
        disableAnimations: true,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(ConstellationBody));
      expect(Localizations.localeOf(context), const Locale('ru'));
      expect(MediaQuery.sizeOf(context), kPhoneSurface);
      expect(
        tester.getSize(find.byType(ConstellationBody)),
        kPhoneSurface,
        reason: 'the Field fills the 375x667 phone',
      );
      _expectPeopleOnField(cubit);

      for (final personId in selections) {
        final label = '${personId == _alice ? 'Alice' : 'Bob'} selected';
        cubit.selectPerson(personId);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$label must render without overflow at 375x667',
        );
        _expectChainDrawnAsMutualTrust(cubit, label);
        _expectDoubleBlue(tester, cubit, (_viewer.id, _alice), label);
        _expectDoubleBlue(tester, cubit, (_alice, _bob), label);
      }
    });
  }
}
