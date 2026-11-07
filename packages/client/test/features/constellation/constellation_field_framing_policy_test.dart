@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

Matrix4 _cameraMatrix(WidgetTester tester) {
  return tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .clone();
}

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

void main() {
  group('Field camera policy U3 (#1055, #1037)', () {
    testWidgets('fit-all scale floor 0.45 on Bob wire field (375 RU)', (
      tester,
    ) async {
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

      cubit.graphController.zoomBy(0.35);
      await tester.pump();
      await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
      await tester.pumpAndSettle();

      expect(
        cubit.graphController.cameraScale,
        greaterThanOrEqualTo(kConstellationDistrictDetailScale),
      );
      expect(holder.frame, isNotNull);
      for (final entry in holder.frame!.tapTargets.entries) {
        if (!entry.key.startsWith('fp:')) {
          continue;
        }
        expect(entry.value.width, greaterThanOrEqualTo(44));
        expect(entry.value.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('three rapid fit-all taps share one camera matrix (375 RU)', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
        locale: const Locale('ru'),
      );
      await tester.pumpAndSettle();
      cubit.graphController.zoomBy(0.4);
      await tester.pump();

      final fit = find.byKey(TestIds.key(TestIds.constellationFitAll));
      await tester.tap(fit);
      await tester.tap(fit);
      await tester.tap(fit);
      await tester.pumpAndSettle();

      final matrix = _cameraMatrix(tester).storage;
      await tester.tap(fit);
      await tester.pump();
      expect(_cameraMatrix(tester).storage, matrix);
      expect(
        cubit.graphController.cameraScale,
        greaterThanOrEqualTo(kConstellationDistrictDetailScale),
      );
    });

    testWidgets(
      'fit-all after overview zoom respects district scale floor (375 RU)',
      (
        tester,
      ) async {
        await usePhoneSurface(tester);
        final cubit = await loadReferenceCubit();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        await tester.pumpAndSettle();

        for (
          var i = 0;
          i < 24 && cubit.graphController.cameraScale >= 0.45;
          i++
        ) {
          cubit.graphController.zoomBy(0.85);
          await tester.pump();
        }
        expect(
          cubit.graphController.cameraScale,
          lessThan(kConstellationDistrictDetailScale),
        );

        await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
        await tester.pumpAndSettle();
        expect(
          cubit.graphController.cameraScale,
          greaterThanOrEqualTo(kConstellationDistrictDetailScale),
        );
      },
    );

    testWidgets('wheel zoom stops at 2.0 (#1037, 375 RU)', (tester) async {
      await usePhoneSurface(tester);
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
        locale: const Locale('ru'),
      );
      await tester.pumpAndSettle();
      final center = Offset(kPhoneSurface.width / 2, kPhoneSurface.height / 2);
      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(center));
      for (var i = 0; i < 40; i++) {
        await tester.sendEventToBinding(wheel.scroll(const Offset(0, -400)));
        await tester.pump();
      }
      expect(cubit.graphController.cameraScale, lessThanOrEqualTo(2.0 + 0.001));
      expect(cubit.graphController.cameraScale, greaterThan(1.5));
    });

    testWidgets('centre-on-me queued during relayout runs after settle', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

      cubit.setFilterCapabilitySlugs({'tools'});
      await tester.pump();
      final context = tester.element(find.byType(ConstellationBody));
      final insets = cubit.fieldCameraViewportInsets(
        context,
        contextPanelVisible: false,
      );
      if (cubit.graphController.isRelayoutInFlight) {
        cubit.centerOnEgo(insets: insets);
        expect(cubit.fieldCameraPendingForTest, isTrue);
      } else {
        cubit.graphController.zoomBy(0.25);
        await tester.pump();
        cubit.centerOnEgo(insets: insets);
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 800));
      expect(cubit.fieldCameraPendingForTest, isFalse);
      expect(cubit.graphController.cameraScale, closeTo(1.0, 0.02));
    });
  });
}
