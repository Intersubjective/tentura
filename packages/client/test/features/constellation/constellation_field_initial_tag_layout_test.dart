import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _ego = Profile(id: 'ego', displayName: 'Эго');

final _tagA = {for (var i = 0; i < 6; i++) 'a$i'};
final _tagB = {for (var i = 0; i < 6; i++) 'b$i'};
final _untagged = {for (var i = 0; i < 6; i++) 'u$i'};
final _people = [..._tagA, ..._tagB, ..._untagged];

Set<String> _tagsOf(String id) => _tagA.contains(id)
    ? const {'tA'}
    : _tagB.contains(id)
    ? const {'tB'}
    : const {};

Set<String> _peopleIn(String tag) => switch (tag) {
  'tA' => _tagA,
  'tB' => _tagB,
  _ => const {},
};

ConstellationField _field() => ConstellationField(
  loadedAt: DateTime.utc(2026, 11, 7),
  context: '',
  peers: [
    for (final id in _people)
      ConstellationPerson(
        id: id,
        displayName: 'Коллега $id',
        ownTagIds: _tagsOf(id).toList(),
      ),
  ],
  edges: [
    for (final id in _people)
      ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
  ],
  anchorProjection: ConstellationAnchorProjection.empty,
);

final class _Repo implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => _field();
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ConstellationCubit> _pumpField(
  WidgetTester tester, {
  required Size size,
  required bool tags,
}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _Repo(),
      accountId: 'ego',
      realtime: buildTestRealtimeSync().case_,
    ).store,
    viewer: _ego,
    forwardCase: buildTestForwardCase(_FakeForwardRepository()),
    ownTagIdsOf: tags ? _tagsOf : null,
    peopleInTag: tags ? _peopleIn : null,
    loadOnCreate: false,
  );
  addTearDown(cubit.close);
  await cubit.load();
  await pumpConstellationBody(tester, cubit, size: size);
  return cubit;
}

Map<String, Offset> _positions(ConstellationCubit cubit) => {
  for (final id in ['ego', ..._people])
    id: cubit.graphController.getPositionOrNullForId('fp:$id')!,
};

/// Owner report 2026-11-07: on load the Field drew each tag's people
/// squeezed together, off ego and at the wrong detail level, until a later
/// relayout (~30 s) spread them and framed the camera.
void main() {
  for (final size in const [kPhoneSurface, Size(1440, 900)]) {
    group('Field first layout with tag areas at $size (RU)', () {
      testWidgets('first presented layout is the settled one', (tester) async {
        final plain = _positions(
          await _pumpField(tester, size: size, tags: false),
        );
        final cubit = await _pumpField(tester, size: size, tags: true);
        final first = _positions(cubit);
        final relayouts = cubit.graphController.relayoutInvocationCount;

        // Nobody is a newcomer on a cold load: tag seating moves no one.
        for (final id in plain.keys) {
          expect(first[id]!.dx, closeTo(plain[id]!.dx, 0.5), reason: id);
          expect(first[id]!.dy, closeTo(plain[id]!.dy, 0.5), reason: id);
        }

        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
        expect(
          cubit.graphController.relayoutInvocationCount,
          relayouts,
          reason: 'no second layout replaces the first one',
        );
        final settled = _positions(cubit);
        for (final id in first.keys) {
          expect(settled[id], first[id], reason: id);
        }
      });

      testWidgets('initial framing runs: ego in the safe viewport, '
          'close detail', (tester) async {
        final cubit = await _pumpField(tester, size: size, tags: true);
        expect(
          identical(
            cubit.graphSceneLayoutAlgorithm,
            cubit.graphSceneLayoutAlgorithm,
          ),
          isTrue,
          reason: 'the view must get the instance the cubit laid out with',
        );
        expect(cubit.fieldInitialFrameCompletedForTest, isTrue);
        expect(cubit.fieldCameraPendingForTest, isFalse);
        final scale = cubit.graphController.cameraScale;
        expect(
          settledConstellationDetailLevel(scale),
          ConstellationDetailLevel.close,
        );
        final matrix = tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value;
        final ego = MatrixUtils.transformPoint(
          matrix,
          cubit.graphController.getPositionOrNullForId('fp:ego')!,
        );
        final viewport = cubit.graphController.viewportSize!;
        final safe = cubit.fieldCameraViewportSnapshotForTest.deflateRect(
          Offset.zero & viewport,
        );
        expect(safe.contains(ego), isTrue, reason: 'ego $ego in $safe');
      });
    });
  }
}
