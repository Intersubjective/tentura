@TestOn('vm')
library;

// A trust chain the Field cannot show whole dims nothing (#1192 follow-up).
//
// Real path: the Field, mutual-trust and trust-chain responses go through the
// real transport, GraphQL mappers and repositories into the Field cubit, and
// the widget tests mount the real Field on that cubit. The Field holds no
// chain from the viewer to Bob, so only the server can name one:
// viewer → Xenia → Bob. On the Field:
// - Carol: a direct contact of the viewer, with a Request and a Post of her
//   own, not on the chain and not one of Bob's mutual-trust contacts;
// - Mia: the server's only mutual-trust contact of Bob;
// - Bob, with a Request of his own.
//
// - Xenia off the Field: the scene treats the chain as absent (it draws the
//   "no chain" viewer–Bob placeholder and fades no edge), so the cubit, the
//   map markers, the label plates and the node-ring layer must not fade
//   anyone either. The panel line still names Xenia from the server's answer.
// - Xenia on the Field (positive control): the scene draws the chain hops
//   (viewer–Xenia and Xenia–Bob, no viewer–Bob placeholder), and Carol, her
//   Request and her Post are dimmed while the chain's people, Mia and Bob's
//   own Request are not.
// - A longer served chain viewer → Xenia → Yuri → Bob with Xenia on the
//   Field and only Yuri off it is not shown whole either: no hop is drawn,
//   not even viewer–Xenia between two placed people, and nothing is dimmed.
//
// The Field fades a node by painting its map marker and label plate through
// an opacity layer (kConstellationTrustChainDimOpacity). The widget tests
// measure that opacity, so they require that mechanism; the node-ring layer
// is checked through the dimmed set it is given.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_mutual_trust_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_trust_chain_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_chain.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_mutual_trust_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_ring_layer.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _bob = 'Ubob000000001';
const _carol = 'Ucarol0000001';
const _mia = 'Umia000000001';
const _xenia = 'Uxenia0000001';
const _yuri = 'Uyuri00000001';
const _reqBob = 'Breqbob000001';
const _reqCarol = 'Breqcarol0001';
const _postCarol = 'Ppostcarol001';

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

Map<String, dynamic> _request(String id, String authorId, String title) => {
  '__typename': 'v2_ConstellationRequest',
  'id': id,
  'pinState': null,
  'authorId': authorId,
  'title': title,
  'status': 0,
  'needs': <String>[],
  'primaryNeedSlug': null,
  'startAt': null,
  'endAt': null,
  'lastActivityAt': '2026-11-06T12:00:00.000Z',
  'addressLabel': null,
  'hasCoordinates': false,
  'isMine': false,
  'viewerHasActiveHelpOffer': false,
  'viewerIsRoomParticipant': false,
  'viewerHasForwardEdge': false,
  'forwardedById': null,
  'forwardedByName': null,
  'parentBeaconId': null,
  'helpOfferCount': 0,
  'coverSource': 0,
  'coverThumb': null,
  'has_unread': false,
};

Map<String, dynamic> _post(String id, String authorId, String excerpt) => {
  '__typename': 'v2_ConstellationPost',
  'id': id,
  'authorId': authorId,
  'lastActivityAt': '2026-11-08T11:00:00.000Z',
  'rootExcerpt': excerpt,
  'isPinned': false,
  'hiddenReachCount': 0,
  'has_unread': false,
  'expiresAt': null,
  'status': 0,
};

/// Viewer ⇄ Carol is explicit trust both ways; Bob, Mia (and Xenia, when
/// [xeniaOnField]) trust the viewer only by derived trust, so the Field
/// itself shows no chain from the viewer to Bob.
Map<String, dynamic> _fieldResponse({required bool xeniaOnField}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-08T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': [_carol],
    'peers': [
      _peer(_bob, 'Bob'),
      _peer(_carol, 'Carol'),
      _peer(_mia, 'Mia'),
      if (xeniaOnField) _peer(_xenia, 'Xenia'),
    ],
    'edges': [
      _edge(_viewer.id, _carol, 1),
      _edge(_carol, _viewer.id, 1),
      _edge(_bob, _viewer.id, 2),
      _edge(_mia, _viewer.id, 2),
      if (xeniaOnField) _edge(_xenia, _viewer.id, 2),
    ],
    'requests': [
      _request(_reqBob, _bob, 'Bike repair'),
      _request(_reqCarol, _carol, 'Moving boxes'),
    ],
    'posts': [_post(_postCarol, _carol, 'Spare seedlings')],
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

/// The server names the chain viewer → Xenia → Bob (with [throughYuri],
/// viewer → Xenia → Yuri → Bob; Yuri is never on the Field) and reports Mia
/// as Bob's only mutual-trust contact.
Map<String, dynamic> Function(WireSent) _wireAnswer({
  required bool xeniaOnField,
  bool throughYuri = false,
}) => (request) {
  final personId = request.variables['personId'] as String?;
  return switch (request.operationName) {
    'ConstellationFieldFetch' => _fieldResponse(xeniaOnField: xeniaOnField),
    'ConstellationMutualTrustFetch' => {
      '__typename': 'query_root',
      'constellationMutualTrust': personId == _bob ? [_mia] : <String>[],
    },
    'ConstellationTrustChainFetch' => {
      '__typename': 'query_root',
      'constellationTrustChain': [
        if (personId == _bob)
          for (final (id, name) in [
            (_viewer.id, 'Viewer'),
            (_xenia, 'Xenia'),
            if (throughYuri) (_yuri, 'Yuri'),
            (_bob, 'Bob'),
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
};

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Loads the Field over the wire, selects Bob and waits for the server's
/// chain and mutual-trust answers to arrive. [sent] records every request.
Future<ConstellationCubit> _loadAndSelectBob(
  RemoteApiService remote,
  List<WireSent> sent,
) async {
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
  await cubit.stream
      .firstWhere((state) => state.status is StateIsSuccess)
      .timeout(const Duration(seconds: 15));
  cubit.selectPerson(_bob);
  await _settle();
  expect(
    sent.where(
      (r) =>
          r.operationName == 'ConstellationTrustChainFetch' &&
          r.variables['personId'] == _bob,
    ),
    isNotEmpty,
    reason: "Bob's chain comes from the production trust-chain query",
  );
  // The served chain went through the mapper and is held by the cubit.
  expect(
    cubit.serverTrustChainName(_xenia),
    'Xenia',
    reason: "the server's chain viewer → Xenia → Bob was parsed and kept",
  );
  expect(
    cubit.selectedMutualTrustIds,
    {_mia},
    reason: "Mia is Bob's only mutual-trust contact, Carol is not one",
  );
  return cubit;
}

Map<String, NodeDetails> _placedNodes(ConstellationCubit cubit) => {
  for (final node
      in cubit.graphController.renderSnapshot.topology.nodesById.values)
    node.payload.id: node.payload,
};

/// Every drawn edge between persons [x] and [y], either direction, as
/// `src->dst#kind`.
List<String> _pairEdges(ConstellationCubit cubit, String x, String y) {
  final ids = {'fp:$x', 'fp:$y'};
  return [
    for (final edge
        in cubit.graphController.renderSnapshot.topology.edgesById.values)
      if (ids.contains(edge.payload.source.graphNodeId) &&
          ids.contains(edge.payload.destination.graphNodeId) &&
          edge.payload.source.graphNodeId !=
              edge.payload.destination.graphNodeId)
        edge.payload.semanticId,
  ];
}

void _expectPlaced(ConstellationCubit cubit, {required bool xeniaOnField}) {
  final placed = _placedNodes(cubit).keys;
  expect(
    placed,
    containsAll([
      _viewer.id,
      _bob,
      _carol,
      _mia,
      _reqBob,
      _reqCarol,
      _postCarol,
    ]),
    reason:
        'the viewer, Bob, Carol, Mia, both Requests and the Post are on the '
        'Field',
  );
  if (xeniaOnField) {
    expect(placed, contains(_xenia), reason: 'Xenia is on the Field');
  } else {
    expect(placed, isNot(contains(_xenia)), reason: 'Xenia is off the Field');
  }
  expect(placed, isNot(contains(_yuri)), reason: 'Yuri is off the Field');
}

/// The opacity [target] is painted with: the product of every opacity layer
/// between its deepest rendered descendant and the root of the render tree.
/// Opacity layers are how the Field fades a node off the trust chain (see the
/// header), so this is the faded-or-not property a user sees.
double _paintedOpacity(WidgetTester tester, Finder target) {
  expect(target, findsOneWidget);
  final leaf = find
      .descendant(
        of: target,
        matching: find.byWidgetPredicate((_) => true),
      )
      .evaluate()
      .lastWhere((element) => element.renderObject != null);
  var opacity = 1.0;
  for (var r = leaf.renderObject; r != null; r = r.parent) {
    if (r is RenderOpacity) {
      opacity *= r.opacity;
    } else if (r is RenderAnimatedOpacity) {
      opacity *= r.opacity.value;
    } else if (r is RenderSliverOpacity) {
      opacity *= r.opacity;
    }
  }
  return opacity;
}

/// The map marker of [id]'s node (its labelled semantics button).
Finder _marker(ConstellationCubit cubit, String id) {
  final graphId = _placedNodes(cubit)[id]!.graphNodeId;
  return find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.identifier == 'constellation.mapNode:$graphId',
  );
}

/// The label plate the viewport overlay draws for [id]'s node.
Finder _plate(ConstellationCubit cubit, String id) => find.byKey(
  ValueKey('constellation.slot.${_placedNodes(cubit)[id]!.graphNodeId}'),
);

Set<String> _ringLayerDimmed(WidgetTester tester) => tester
    .widget<ConstellationNodeRingLayer>(find.byType(ConstellationNodeRingLayer))
    .dimmedGraphIds;

String _chainLineText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('constellation.trust_chain')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  group('a server chain through someone off the Field dims nothing', () {
    test('Xenia off the Field: the scene draws the "no chain" placeholder and '
        'fades no edge, and no placed person, Request or Post is dimmed, '
        'Carol included', () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        const {},
        sent,
        responseFor: (r) async => _wireAnswer(xeniaOnField: false)(r),
        (remote) async {
          final cubit = await _loadAndSelectBob(remote, sent);
          try {
            _expectPlaced(cubit, xeniaOnField: false);

            // The scene half: the chain counts as absent.
            final viewerBob = _pairEdges(cubit, _viewer.id, _bob);
            expect(
              viewerBob,
              hasLength(1),
              reason:
                  'with no chain shown, Bob gets the one viewer–Bob '
                  'placeholder edge, drawn $viewerBob',
            );
            expect(
              _pairEdges(cubit, _bob, _mia),
              [endsWith('#mutualTrust')],
              reason: "Bob's mutual trust edge to Mia is drawn",
            );
            expect(
              cubit.edgeFadeBySemanticId,
              isEmpty,
              reason: 'the scene fades no edge for a chain it cannot show',
            );

            // The cubit half: and so nothing is dimmed.
            final nodes = _placedNodes(cubit);
            expect(
              cubit.isDimmedByTrustChain(nodes[_carol]!),
              isFalse,
              reason: 'Carol is not faded for a chain the Field does not show',
            );
            for (final MapEntry(:key, :value) in nodes.entries) {
              expect(
                cubit.isDimmedByTrustChain(value),
                isFalse,
                reason: '$key must not be dimmed',
              );
            }
          } finally {
            await cubit.close();
          }
        },
      );
    });

    test('Xenia on the Field: the scene draws the chain hops instead of the '
        'placeholder, and Carol, her Request and her Post are dimmed while '
        "the chain, Mia and Bob's Request are not", () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        const {},
        sent,
        responseFor: (r) async => _wireAnswer(xeniaOnField: true)(r),
        (remote) async {
          final cubit = await _loadAndSelectBob(remote, sent);
          try {
            _expectPlaced(cubit, xeniaOnField: true);
            final chain = cubit.selectedTrustChain;
            expect(chain, isA<ConstellationTrustChainFound>());
            expect((chain! as ConstellationTrustChainFound).path, [
              _viewer.id,
              _xenia,
              _bob,
            ]);

            // The scene half: the chain is drawn hop by hop.
            expect(
              _pairEdges(cubit, _viewer.id, _xenia),
              isNotEmpty,
              reason: 'the viewer–Xenia hop is drawn',
            );
            expect(
              _pairEdges(cubit, _xenia, _bob),
              isNotEmpty,
              reason: 'the Xenia–Bob hop is drawn',
            );
            expect(
              _pairEdges(cubit, _viewer.id, _bob),
              isEmpty,
              reason: 'Bob is reached through Xenia: no viewer–Bob placeholder',
            );
            expect(_pairEdges(cubit, _bob, _mia), [endsWith('#mutualTrust')]);

            // The cubit half: off-chain nodes are dimmed.
            final nodes = _placedNodes(cubit);
            for (final id in [_carol, _reqCarol, _postCarol]) {
              expect(
                cubit.isDimmedByTrustChain(nodes[id]!),
                isTrue,
                reason: '$id is off the shown chain',
              );
            }
            for (final id in [_viewer.id, _xenia, _bob, _mia, _reqBob]) {
              expect(
                cubit.isDimmedByTrustChain(nodes[id]!),
                isFalse,
                reason: "$id is on the chain, Bob's contact or Bob's own",
              );
            }
          } finally {
            await cubit.close();
          }
        },
      );
    });

    test('a longer chain with only one of its people off the Field: no hop '
        'is drawn, not even between the placed viewer and Xenia, and '
        'nothing is dimmed', () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        const {},
        sent,
        responseFor: (r) async =>
            _wireAnswer(xeniaOnField: true, throughYuri: true)(r),
        (remote) async {
          final cubit = await _loadAndSelectBob(remote, sent);
          try {
            _expectPlaced(cubit, xeniaOnField: true);
            expect(cubit.serverTrustChainName(_yuri), 'Yuri');

            // The scene half: the chain counts as absent.
            expect(
              _pairEdges(cubit, _viewer.id, _xenia),
              isEmpty,
              reason:
                  'the viewer–Xenia hop of a chain not shown whole is '
                  'not drawn',
            );
            final viewerBob = _pairEdges(cubit, _viewer.id, _bob);
            expect(
              viewerBob,
              hasLength(1),
              reason:
                  'Bob gets the one viewer–Bob placeholder, drawn '
                  '$viewerBob',
            );
            expect(cubit.edgeFadeBySemanticId, isEmpty);

            // The cubit half: nothing is dimmed.
            for (final MapEntry(:key, :value) in _placedNodes(cubit).entries) {
              expect(
                cubit.isDimmedByTrustChain(value),
                isFalse,
                reason: '$key must not be dimmed',
              );
            }
          } finally {
            await cubit.close();
          }
        },
      );
    });

    Future<ConstellationCubit> mount(
      WidgetTester tester, {
      required bool xeniaOnField,
    }) async {
      final sent = <WireSent>[];
      late ConstellationCubit cubit;
      await tester.runAsync(
        () => withRemoteWire(
          const {},
          sent,
          responseFor: (r) async => _wireAnswer(xeniaOnField: xeniaOnField)(r),
          (remote) async => cubit = await _loadAndSelectBob(remote, sent),
        ),
      );
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1280, 900),
        locale: const Locale('en'),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectPlaced(cubit, xeniaOnField: xeniaOnField);
      return cubit;
    }

    testWidgets('Xenia off the Field: every map marker and label plate is '
        "painted like Bob's, the node rings fade nothing, and the panel "
        'still names Xenia from the server chain', (tester) async {
      final cubit = await mount(tester, xeniaOnField: false);

      final bobMarker = _paintedOpacity(tester, _marker(cubit, _bob));
      final bobPlate = _paintedOpacity(tester, _plate(cubit, _bob));
      for (final id in [_carol, _mia, _reqBob, _reqCarol, _postCarol]) {
        expect(
          _paintedOpacity(tester, _marker(cubit, id)),
          bobMarker,
          reason: "$id's map marker is not faded",
        );
        expect(
          _paintedOpacity(tester, _plate(cubit, id)),
          bobPlate,
          reason: "$id's label plate is not faded",
        );
      }
      expect(
        _ringLayerDimmed(tester),
        isEmpty,
        reason: 'the node-ring layer fades no node',
      );
      expect(_chainLineText(tester), 'Through Xenia');
    });

    testWidgets('Xenia on the Field: the map markers and label plates of '
        "Carol, her Request and her Post are painted fainter than Bob's, "
        "Mia's are not, and the node rings fade Carol", (tester) async {
      final cubit = await mount(tester, xeniaOnField: true);

      final bobMarker = _paintedOpacity(tester, _marker(cubit, _bob));
      final bobPlate = _paintedOpacity(tester, _plate(cubit, _bob));
      for (final id in [_carol, _reqCarol, _postCarol]) {
        expect(
          _paintedOpacity(tester, _marker(cubit, id)),
          lessThan(bobMarker),
          reason: "$id's map marker is faded off the shown chain",
        );
        expect(
          _paintedOpacity(tester, _plate(cubit, id)),
          lessThan(bobPlate),
          reason: "$id's label plate is faded off the shown chain",
        );
      }
      for (final id in [_mia, _xenia, _reqBob]) {
        expect(
          _paintedOpacity(tester, _marker(cubit, id)),
          bobMarker,
          reason: "$id's map marker is not faded",
        );
      }
      final dimmed = _ringLayerDimmed(tester);
      expect(dimmed, contains(_placedNodes(cubit)[_carol]!.graphNodeId));
      expect(dimmed, isNot(contains(_placedNodes(cubit)[_bob]!.graphNodeId)));
      expect(_chainLineText(tester), 'Through Xenia');
    });
  });
}
