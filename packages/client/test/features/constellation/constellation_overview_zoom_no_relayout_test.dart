@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/util/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/util/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

Map<String, dynamic> _bobWireResponse() {
  Map<String, dynamic> peer(String id, String displayName) => {
    '__typename': 'v2_ConstellationPeer',
    'id': id,
    'contactOnly': false,
    'displayName': displayName,
    'handle': null,
    'image': null,
    'isNew': false,
    'pinState': null,
    'presence': 'visible',
    'temporaryBeaconId': null,
    'bondContexts': <dynamic>[],
    'visible': true,
  };

  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': '2026-11-06T12:00:00.000Z',
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': ['anna', 'boris', 'dima', 'kira'],
      'peers': [
        peer('bob', 'Боб'),
        peer('anna', 'Анна'),
        peer('boris', 'Борис'),
        peer('dima', 'Дима'),
        peer('kira', 'Кира'),
      ],
      'edges': [
        for (final dst in ['anna', 'boris', 'dima', 'kira'])
          {
            '__typename': 'v2_ConstellationEdge',
            'src': 'bob',
            'dst': dst,
            'tier': 1,
          },
      ],
      'requests': [
        {
          '__typename': 'v2_ConstellationRequest',
          'id': 'req-bob-1',
          'pinState': null,
          'authorId': 'bob',
          'title': 'Тестовый запрос на поле',
          'status': 0,
          'needs': <String>[],
          'primaryNeedSlug': null,
          'startAt': null,
          'endAt': null,
          'lastActivityAt': '2026-11-06T12:00:00.000Z',
          'addressLabel': null,
          'hasCoordinates': false,
          'isMine': true,
          'viewerHasActiveHelpOffer': false,
          'viewerIsRoomParticipant': true,
          'viewerHasForwardEdge': false,
          'forwardedById': null,
          'forwardedByName': null,
          'parentBeaconId': null,
          'helpOfferCount': 0,
          'coverSource': 0,
          'coverThumb': null,
          'has_unread': false,
        },
      ],
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
}

Future<ConstellationCubit> _loadBobCubitFromWire() async {
  late final ConstellationField mappedField;
  await withRemoteWire(
    {'ConstellationFieldFetch': _bobWireResponse()},
    [],
    (remote) async {
      mappedField = await ConstellationRepository(remote).fetch();
    },
  );
  final cubit = ConstellationCubit(
    case_: constellationCaseForField(mappedField),
    viewer: const Profile(id: 'bob', displayName: 'Боб'),
    semanticZoomEnabled: true,
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  return cubit;
}

Offset _position(ConstellationCubit cubit, String graphId) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
  expect(point, isNotNull, reason: '$graphId has a displayed scene position');
  return Offset(point!.x, point.y);
}

Map<String, Offset> _personPositions(ConstellationCubit cubit) {
  final field = cubit.state.field!;
  return {
    for (final peer in field.peers)
      if (peer.id != 'bob') peer.id: _position(cubit, 'fp:${peer.id}'),
  };
}

Future<void> _setZoomScale(
  WidgetTester tester,
  ConstellationCubit cubit,
  double targetScale,
) async {
  cubit.graphController.zoomBy(targetScale / cubit.graphController.cameraScale);
  await tester.pump();
  await tester.pump();
  expect(cubit.graphController.cameraScale, closeTo(targetScale, 1e-5));
}

void main() {
  testWidgets(
    'overview zoom keeps scene positions and skips relayout (375 RU, wire)',
    (tester) async {
      await usePhoneSurface(tester);
      final cubit = await _loadBobCubitFromWire();
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
        locale: const Locale('ru'),
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Тестовый запрос на поле'),
        findsWidgets,
        reason: 'request title visible before overview zoom',
      );

      await _setZoomScale(tester, cubit, 1);
      expect(holder.frame!.detail, ConstellationDetailLevel.close);
      final atClose = _personPositions(cubit);
      final layoutRuns = cubit.graphController.relayoutInvocationCount;

      await _setZoomScale(tester, cubit, 0.4);
      expect(
        holder.frame!.detail,
        ConstellationDetailLevel.overview,
        reason: 'below district scale draws overview dots',
      );
      expect(
        cubit.graphController.relayoutInvocationCount,
        layoutRuns,
        reason: 'entering overview must not trigger layout',
      );
      for (final entry in atClose.entries) {
        expect(
          _position(cubit, 'fp:${entry.key}'),
          entry.value,
          reason: '${entry.key} stays put when zooming out to dots',
        );
      }

      await _setZoomScale(tester, cubit, 1);
      expect(holder.frame!.detail, ConstellationDetailLevel.close);
      expect(
        cubit.graphController.relayoutInvocationCount,
        layoutRuns,
        reason: 'leaving overview must not trigger layout',
      );
      for (final entry in atClose.entries) {
        expect(
          _position(cubit, 'fp:${entry.key}'),
          entry.value,
          reason: '${entry.key} stays put when zooming back to detail',
        );
      }

      await _setZoomScale(tester, cubit, 0.35);
      await _setZoomScale(tester, cubit, 0.5);
      await _setZoomScale(tester, cubit, 0.38);
      expect(
        cubit.graphController.relayoutInvocationCount,
        layoutRuns,
        reason: 'panning across the threshold several times skips relayout',
      );
      for (final entry in atClose.entries) {
        expect(_position(cubit, 'fp:${entry.key}'), entry.value);
      }
    },
  );
}
