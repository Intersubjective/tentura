@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';

final class _MutableFieldRepository implements ConstellationRepositoryPort {
  _MutableFieldRepository(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

Matrix4 _cameraMatrix(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .clone();

ConstellationField _fieldWithExtraPeer() {
  final base = constellationReferenceField();
  return ConstellationField(
    loadedAt: base.loadedAt,
    context: base.context,
    peers: [
      ...base.peers,
      const ConstellationPerson(id: 'new', displayName: 'Новый коллега'),
    ],
    edges: [
      ...base.edges,
      const ConstellationTrustEdgeEntity(src: 'ego', dst: 'new', tier: 1),
    ],
    requests: base.requests,
    anchorProjection: base.anchorProjection,
  );
}

void main() {
  test(
    'Bob wire fetch path still feeds the initial-framing harness (#1056)',
    () async {
      await withRemoteWire(
        {
          'ConstellationFieldFetch': {
            '__typename': 'query_root',
            'constellationField': {
              '__typename': 'v2_ConstellationField',
              'loadedAt': '2026-11-07T10:00:00.000Z',
              'context': '',
              'peersCapped': false,
              'requestsCapped': false,
              'directContactIds': ['anna'],
              'peers': [
                {
                  '__typename': 'v2_ConstellationPeer',
                  'id': 'bob',
                  'contactOnly': false,
                  'displayName': 'Боб',
                  'handle': null,
                  'image': null,
                  'isNew': false,
                  'pinState': null,
                  'presence': 'visible',
                  'temporaryBeaconId': null,
                  'bondContexts': <dynamic>[],
                  'visible': true,
                },
                {
                  '__typename': 'v2_ConstellationPeer',
                  'id': 'anna',
                  'contactOnly': false,
                  'displayName': 'Анна',
                  'handle': null,
                  'image': null,
                  'isNew': false,
                  'pinState': null,
                  'presence': 'visible',
                  'temporaryBeaconId': null,
                  'bondContexts': <dynamic>[],
                  'visible': true,
                },
              ],
              'edges': [
                {
                  '__typename': 'v2_ConstellationEdge',
                  'src': 'bob',
                  'dst': 'anna',
                  'tier': 1,
                },
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
          },
        },
        [],
        (remote) async {
          final field = await ConstellationRepository(remote).fetch();
          expect(field.peers, hasLength(2));
        },
      );
    },
  );

  group('Field initial framing U4 (#1055, #1056)', () {
    testWidgets('cold start frames at close-detail floor on phone RU', (
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

      expect(cubit.fieldInitialFrameCompletedForTest, isTrue);
      expect(
        cubit.graphController.cameraScale,
        greaterThanOrEqualTo(kConstellationCloseDetailScale),
      );
      expect(cubit.graphController.cameraScale, lessThanOrEqualTo(1.0));
    });

    testWidgets(
      'skips re-frame when the user moved the camera before people arrive',
      (tester) async {
        final repo = _MutableFieldRepository(constellationReferenceField());
        final fixture = ConstellationStoreFixture(repo, accountId: 'ego');
        final cubit = fixture.createCubit(viewer: kRefEgo);
        addTearDown(cubit.close);
        await cubit.load();
        await pumpConstellationBody(
          tester,
          cubit,
          stabilizeFieldChrome: false,
        );
        await tester.pumpAndSettle();

        final beforeMove = _cameraMatrix(tester);
        final at = tester.getCenter(find.byType(InteractiveViewer));
        final gesture = await tester.startGesture(at);
        await gesture.moveBy(const Offset(90, 50));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(_cameraMatrix(tester).storage, isNot(beforeMove.storage));
        expect(
          cubit.graphController.userCameraInputRevision.value,
          greaterThan(0),
        );

        final afterUserMove = _cameraMatrix(tester);
        repo.field = _fieldWithExtraPeer();
        await fixture.store.requestRefresh(ConstellationRefreshReason.catchUp);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(cubit.state.field!.peers, hasLength(4));
        expect(cubit.fieldPeerCountAtLastProgrammaticFrameForTest, 3);
        expect(_cameraMatrix(tester).storage, afterUserMove.storage);
      },
    );

    testWidgets('re-frames when people arrive and the camera was untouched', (
      tester,
    ) async {
      final repo = _MutableFieldRepository(constellationReferenceField());
      final fixture = ConstellationStoreFixture(repo, accountId: 'ego');
      final cubit = fixture.createCubit(viewer: kRefEgo);
      addTearDown(cubit.close);
      await cubit.load();
      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();

        expect(cubit.fieldPeerCountAtLastProgrammaticFrameForTest, 3);
        expect(cubit.graphController.userCameraInputRevision.value, 0);
        repo.field = _fieldWithExtraPeer();
        await fixture.store.requestRefresh(ConstellationRefreshReason.catchUp);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(cubit.state.field!.peers, hasLength(4));
        expect(cubit.fieldInitialFrameCompletedForTest, isTrue);
        expect(
          cubit.graphController.cameraScale,
          greaterThanOrEqualTo(kConstellationCloseDetailScale),
        );
        expect(
          cubit.fieldPeerCountAtLastProgrammaticFrameForTest,
          4,
          reason: 'untouched camera should accept the automatic re-frame',
        );
    });
  });
}
