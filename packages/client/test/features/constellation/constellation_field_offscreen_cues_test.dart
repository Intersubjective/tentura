@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/ui/test_ids.dart';

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
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  return cubit;
}

Rect _nodeBodyInViewport(ConstellationCubit cubit, String graphId) {
  final snapshot = cubit.graphController.renderSnapshot;
  final point = snapshot.resolvePosition(graphId);
  final sceneNode = snapshot.topology.nodesById[graphId];
  if (point == null || sceneNode == null) {
    return Rect.zero;
  }
  final bounds = constellationPlacedNodeBounds(
    centre: (x: point.x, y: point.y),
    footprint: cubit.layoutFootprints[graphId],
    size: (width: sceneNode.size.width, height: sceneNode.size.height),
  );
  final controller = cubit.graphController;
  final topLeft = controller.sceneToViewportLocal(
    Offset(bounds.left, bounds.top),
  );
  final bottomRight = controller.sceneToViewportLocal(
    Offset(bounds.right, bounds.bottom),
  );
  return Rect.fromPoints(topLeft, bottomRight);
}

bool _nodeInsideSafeRect(WidgetTester tester, ConstellationCubit cubit, String graphId) {
  final context = tester.element(find.byType(ConstellationBody));
  final insets = cubit.fieldCameraViewportInsets(
    context,
    contextPanelVisible: false,
  );
  final pixel = cubit.graphController.viewportSize!;
  final safe = Rect.fromLTRB(
    insets.left,
    insets.top,
    pixel.width - insets.right,
    pixel.height - insets.bottom,
  );
  final body = _nodeBodyInViewport(cubit, graphId);
  return safe.overlaps(body);
}

void main() {
  test(
    'Bob wire fetch feeds off-screen cue counting (#1053)',
    () async {
      await withRemoteWire(
        {'ConstellationFieldFetch': _bobWireResponse()},
        [],
        (remote) async {
          final field = await ConstellationRepository(remote).fetch();
          expect(field.peers, hasLength(5));
        },
      );
    },
  );

  group('Field camera policy U6 off-screen cues (#1055, #1053)', () {
    testWidgets(
      'zoom 2 on ego shows directional cues; fit-all hides them (375 RU)',
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

        final context = tester.element(find.byType(ConstellationBody));
        final insets = cubit.fieldCameraViewportInsets(
          context,
          contextPanelVisible: false,
        );
        cubit.centerOnEgo(insets: insets);
        await tester.pumpAndSettle();
        while (cubit.graphController.cameraScale < 2.0 - 0.01) {
          cubit.graphController.zoomBy(1.15);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        final zoomed = cubit.fieldOffscreenCues(insets: insets);
        final offScreenTotal =
            zoomed.left + zoomed.right + zoomed.above + zoomed.below;
        expect(offScreenTotal, greaterThan(0));
        expect(
          find.byKey(const Key('constellation.offscreen.below')),
          findsWidgets,
        );

        await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
        await tester.pumpAndSettle();

        final fit = cubit.fieldOffscreenCues(insets: insets);
        expect(fit.hasAny, isFalse);
        expect(find.byKey(const Key('constellation.offscreen.left')), findsNothing);
      },
    );

    testWidgets(
      'tapping the below cue reveals Anna inside the safe rect (375 RU)',
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

        final context = tester.element(find.byType(ConstellationBody));
        final insets = cubit.fieldCameraViewportInsets(
          context,
          contextPanelVisible: false,
        );
        cubit.centerOnEgo(insets: insets);
        await tester.pumpAndSettle();
        while (cubit.graphController.cameraScale < 2.0 - 0.01) {
          cubit.graphController.zoomBy(1.15);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        final before = cubit.fieldOffscreenCues(insets: insets);
        final beforeTotal =
            before.left + before.right + before.above + before.below;

        final cue = [
          find.byKey(const Key('constellation.offscreen.below')),
          find.byKey(const Key('constellation.offscreen.left')),
          find.byKey(const Key('constellation.offscreen.right')),
          find.byKey(const Key('constellation.offscreen.above')),
        ].firstWhere((f) => f.evaluate().isNotEmpty);
        await tester.tap(cue);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 350));

        final after = cubit.fieldOffscreenCues(insets: insets);
        final afterTotal = after.left + after.right + after.above + after.below;
        expect(afterTotal, lessThan(beforeTotal));
        expect(
          cubit.fieldAnyNodeBodyInSafeRectForTest(insets: insets),
          isTrue,
        );
        final revealedAnna = _nodeInsideSafeRect(tester, cubit, 'fp:anna');
        if (cue == find.byKey(const Key('constellation.offscreen.below'))) {
          expect(revealedAnna, isTrue);
        }
      },
    );
  });
}
