@TestOn('vm')
library;

// Real path on a 375x667 phone in Russian: the Field response goes through
// the real transport, GraphQL mapper and repository into the Field cubit and
// the mounted Field. With nothing selected no Post has an author edge;
// tapping a Post node draws the trust path Ego → amy → bob → the Post and the
// Post → participant edges, and none of bob's trust edges to other people.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Я');
const _amy = 'Uamy000000001';
const _bob = 'Ubob000000001';
const _cat = 'Ucat000000001';
const _dan = 'Udan000000001';
const _eve = 'Ueve000000001';
const _fay = 'Ufay000000001';
const _post = 'Ppost00000001';

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

Map<String, dynamic> _edge(String src, String dst) => {
  '__typename': 'v2_ConstellationEdge',
  'src': src,
  'dst': dst,
  'tier': 1,
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
  'lastActivityAt': DateTime.now().toUtc().toIso8601String(),
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

Map<String, dynamic> _memberWeb(String personId, String state) => {
  '__typename': 'v2_ConstellationMemberWeb',
  'beaconId': _post,
  'personId': personId,
  'state': state,
};

/// Ego → amy → bob explicitly; bob trusts eve and fay (who hold a Request
/// each, so they are on the Field). bob's Post has participants cat and dan.
Map<String, dynamic> _fieldResponse() {
  final now = DateTime.now().toUtc();
  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': now.toIso8601String(),
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': [_amy],
      'peers': [
        _peer(_amy, 'Анна Длиннофамильная-Константинопольская'),
        _peer(_bob, 'Борис'),
        _peer(_cat, 'Катя'),
        _peer(_dan, 'Даня'),
        _peer(_eve, 'Ева'),
        _peer(_fay, 'Фая'),
      ],
      'edges': [
        _edge(_viewer.id, _amy),
        _edge(_amy, _bob),
        _edge(_bob, _eve),
        _edge(_bob, _fay),
      ],
      'requests': [
        _request('Reve000000001', _eve, 'Нужна стремянка'),
        _request('Rfay000000001', _fay, 'Помочь с переездом'),
      ],
      'posts': [
        {
          '__typename': 'v2_ConstellationPost',
          'id': _post,
          'authorId': _bob,
          'lastActivityAt': now
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'expiresAt': now.add(const Duration(hours: 48)).toIso8601String(),
          'status': 0,
          'rootExcerpt': 'У кого есть лестница на выходные?',
          'isPinned': false,
          'hiddenReachCount': 0,
          'has_unread': false,
        },
      ],
      'memberWebs': [
        _memberWeb(_cat, 'INSIDE'),
        _memberWeb(_dan, 'FORWARDED'),
      ],
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
}

String _pair(String x, String y) => x.compareTo(y) <= 0 ? '$x–$y' : '$y–$x';

/// Every drawn edge as an undirected pair of domain ids.
Set<String> _drawnPairs(ConstellationCubit cubit) => {
  for (final edge
      in cubit.graphController.renderSnapshot.topology.edgesById.values)
    if (edge.payload.source.id != edge.payload.destination.id)
      _pair(edge.payload.source.id, edge.payload.destination.id),
};

/// The mounted Field draws its scene with the Field's edge painter, so the
/// scene topology asserted below is what the phone shows.
void _expectFieldEdgePainter(WidgetTester tester) => expect(
  tester
      .widget<GraphView<dynamic, dynamic>>(
        find.byWidgetPredicate((w) => w is GraphView),
      )
      .edgePainter,
  isA<ConstellationEdgePainter>(),
);

void main() {
  testWidgets('tapping a Post at 375x667 in Russian draws only the path to it '
      'and its participants, and no Post has an author edge while nothing is '
      'selected', (tester) async {
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
      cubit.graphController.renderSnapshot.topology.nodesById.keys,
      containsAll([
        'fp:${_viewer.id}',
        'fp:$_amy',
        'fp:$_bob',
        'fp:$_eve',
        'fp:$_fay',
        'fr:$_post',
      ]),
      reason: "the mapped Field places the path, bob's fan and the Post",
    );

    expect(
      _drawnPairs(cubit),
      isNot(contains(_pair(_bob, _post))),
      reason: 'nothing selected: the Post has no author edge',
    );

    cubit.focusBeacon(_post, insets: EdgeInsets.zero);
    await tester.pumpAndSettle();
    final postNode = find.byKey(TestIds.key(TestIds.graphNode(_post)));
    expect(postNode, findsOneWidget);
    await tester.tap(postNode);
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'selecting the Post must render without overflow at 375x667',
    );
    expect(cubit.state.selectedRequestId, _post);

    final drawn = _drawnPairs(cubit);
    expect(
      drawn,
      isNot(anyOf(contains(_pair(_bob, _eve)), contains(_pair(_bob, _fay)))),
      reason:
          "selecting the Post must not show bob's trust edges to eve and fay, "
          'drawn: ${drawn.toList()..sort()}',
    );
    for (final (x, y, what) in [
      (_viewer.id, _amy, 'path hop Ego–amy'),
      (_amy, _bob, 'path hop amy–bob'),
      (_bob, _post, 'path hop bob–Post'),
      (_post, _cat, 'Post–cat participant edge'),
      (_post, _dan, 'Post–dan participant edge'),
    ]) {
      expect(drawn, contains(_pair(x, y)), reason: '$what must be drawn');
    }
    _expectFieldEdgePainter(tester);
  });

  testWidgets(
    '«Show on Field» from another tab at 375x667 keeps the camera on the '
    'Post instead of the new visit fit-all',
    (tester) async {
      await usePhoneSurface(tester);
      late ConstellationCubit cubit;
      await tester.runAsync(
        () => withRemoteWire(
          {'ConstellationFieldFetch': _fieldResponse()},
          [],
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
      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
        disableAnimations: true,
      );
      await tester.pumpAndSettle();

      final graphView = find.byWidgetPredicate((w) => w is GraphView);
      final postNode = find.byKey(TestIds.key(TestIds.graphNode(_post)));
      double postOffCentre() =>
          (tester.getCenter(postNode) - tester.getCenter(graphView)).distance;
      expect(
        postOffCentre(),
        greaterThan(20),
        reason: 'precondition: the entry fit-all does not centre the Post',
      );

      // The app's order on «Show on Field» from a Post on another tab: the
      // tab activation starts a new Field visit (its automatic framing waits
      // for the next frame), and the focus request's post-frame callback
      // focuses the Post before that framing runs.
      cubit
        ..startFieldVisit()
        ..focusBeacon(_post, insets: EdgeInsets.zero);
      expect(cubit.state.selectedRequestId, _post);
      await tester.pump();
      final focused = tester.getCenter(postNode);
      expect(
        postOffCentre(),
        lessThan(40),
        reason: 'the focus moved the camera onto the Post',
      );
      await tester.pumpAndSettle();

      expect(
        (tester.getCenter(postNode) - focused).distance,
        lessThan(0.5),
        reason: 'the new visit fit-all must not replace the focused camera',
      );
    },
  );
}
