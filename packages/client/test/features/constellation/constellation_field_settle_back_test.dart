@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

Matrix4 _cameraMatrix(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .clone();

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
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  return cubit;
}

bool _anyNodeInSafeRect(WidgetTester tester, ConstellationCubit cubit) {
  final context = tester.element(find.byType(ConstellationBody));
  final insets = cubit.fieldCameraViewportInsets(
    context,
    contextPanelVisible: false,
  );
  return cubit.fieldAnyNodeBodyInSafeRectForTest(insets: insets);
}

void main() {
  test(
    'Bob wire fetch feeds settle-back target selection (#1054)',
    () async {
      late final ConstellationField mappedField;
      await withRemoteWire(
        {'ConstellationFieldFetch': _bobWireResponse()},
        [],
        (remote) async {
          mappedField = await ConstellationRepository(remote).fetch();
        },
      );
      expect(mappedField.peers, hasLength(5));
      expect(mappedField.requests, hasLength(1));
    },
  );

  group('Field camera policy U5 settle-back (#1055, #1054)', () {
    testWidgets(
      'Bob wire cubit exposes nearest reveal target when safe rect is empty',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadBobCubitFromWire();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        await tester.pumpAndSettle();

        expect(_anyNodeInSafeRect(tester, cubit), isTrue);
        final context = tester.element(find.byType(ConstellationBody));
        final insets = cubit.fieldCameraViewportInsets(
          context,
          contextPanelVisible: false,
        );

        cubit.graphController.jumpToPosition(const Offset(9000, 9000));
        await tester.pump();

        expect(cubit.fieldAnyNodeBodyInSafeRectForTest(insets: insets), isFalse);
        expect(cubit.fieldSettleBackRevealTarget(insets: insets), isNotNull);
      },
    );

    testWidgets(
      'pumping after an empty pan triggers settle-back reveal (375 RU)',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadBobCubitFromWire();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
        await tester.pumpAndSettle();
        expect(_anyNodeInSafeRect(tester, cubit), isTrue);

        cubit.graphController.jumpToPosition(const Offset(9000, 9000));
        await tester.pump();
        expect(_anyNodeInSafeRect(tester, cubit), isFalse);

        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(_anyNodeInSafeRect(tester, cubit), isTrue);
      },
    );

    testWidgets(
      'after fit-all, fling 600 px up then settle-back leaves a node in the safe rect (375 RU)',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadBobCubitFromWire();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
        await tester.pumpAndSettle();
        expect(_anyNodeInSafeRect(tester, cubit), isTrue);

        final at = tester.getCenter(find.byType(InteractiveViewer));
        final gesture = await tester.startGesture(at);
        await gesture.moveBy(const Offset(0, -600));
        await gesture.up();
        await tester.pump();
        expect(
          _anyNodeInSafeRect(tester, cubit),
          isFalse,
          reason: '600 px pan should leave the safe rect empty before settle-back',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(_anyNodeInSafeRect(tester, cubit), isTrue);
      },
    );

    testWidgets(
      'small pan that keeps nodes visible does not settle-back afterwards (375 RU)',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadBobCubitFromWire();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
        await tester.pumpAndSettle();
        expect(_anyNodeInSafeRect(tester, cubit), isTrue);

        final at = tester.getCenter(find.byType(InteractiveViewer));
        final gesture = await tester.startGesture(at);
        await gesture.moveBy(const Offset(0, -24));
        await gesture.up();
        await tester.pump();
        final matrixAfterPan = _cameraMatrix(tester).storage;
        await tester.pump(const Duration(milliseconds: 500));

        expect(_anyNodeInSafeRect(tester, cubit), isTrue);
        expect(_cameraMatrix(tester).storage, matrixAfterPan);
      },
    );
  });
}
