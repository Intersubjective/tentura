import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_drag_cluster.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_magnet_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';

import 'fixtures/constellation_reference_fixture.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 11, 6, 12);

Set<String> _tagsFromStore(String personId) => switch (personId) {
      'p3' => {'t1'},
      'p4' => {'t2'},
      'p7' => {'t1'},
      'p6' => {'t1'},
      _ => const <String>{},
    };

Set<String> _peopleInTag(String tagId) => switch (tagId) {
      't1' => {'p3', 'p7', 'p6', 'ego'},
      't2' => {'p4', 'ego'},
      _ => const <String>{},
    };

ConstellationField _field() {
  const peers = [
    ConstellationPerson(id: 'p3', displayName: 'Three', ownTagIds: ['t1']),
    ConstellationPerson(id: 'p4', displayName: 'Four', ownTagIds: ['t2']),
    ConstellationPerson(id: 'p7', displayName: 'Seven', ownTagIds: ['t1']),
    ConstellationPerson(id: 'p6', displayName: 'Six', ownTagIds: ['t1']),
  ];
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: peers,
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'p3', tier: 1),
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'p4', tier: 1),
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'p7', tier: 1),
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'p6', tier: 1),
    ],
    anchorProjection: ConstellationAnchorProjection.empty,
  );
}

final class _FieldRepo implements ConstellationRepositoryPort {
  _FieldRepo(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 7abw.9: after load + graph pump, [peopleInTag] seats inherited-tag newcomer in hull.
void main() {
  group('ConstellationCubit tag-area seating (7abw.9)', () {
    testWidgets(
      'person_tag style inherited tag A puts newcomer inside A hull',
      (tester) async {
        final fieldRepo = _FieldRepo(_field());
        final sync = buildTestRealtimeSync();
        final store = ConstellationStoreFixture(
          fieldRepo,
          accountId: 'ego',
          realtime: sync.case_,
        ).store;
        final cubit = ConstellationCubit(
          case_: store,
          viewer: _ego,
          forwardCase: buildTestForwardCase(_FakeForwardRepository()),
          ownTagIdsOf: _tagsFromStore,
          peopleInTag: _peopleInTag,
          loadOnCreate: false,
        );
        addTearDown(() async {
          await cubit.close();
        });
        await cubit.load();
        expect(cubit.state.status, isA<StateIsSuccess>());
        await pumpConstellationBody(
          tester,
          cubit,
          size: const Size(800, 700),
          locale: const Locale('en'),
        );

        final p6 = cubit.graphController.getPositionOrNullForId('fp:p6');
        final p3 = cubit.graphController.getPositionOrNullForId('fp:p3');
        final p7 = cubit.graphController.getPositionOrNullForId('fp:p7');
        expect(p3, isNotNull);
        expect(p7, isNotNull);
        expect(p6, isNotNull);
        final p3o = p3!;
        final p7o = p7!;
        final p6o = p6!;

        final cell = kConstellationDragPersonBodySize.width + 16;
        final r = constellationTagAreaRadiusForSeating(memberCount: 2, maxCell: cell);
        final egoAt = cubit.graphController.getPositionOrNullForId('fp:ego');
        expect(egoAt, isNotNull);
        final c = constellationTagMemberCentroidScene(
          tagId: 't1',
          peopleOfTag: _peopleInTag,
          personCentreById: {
            'p3': (x: p3o.dx, y: p3o.dy),
            'p7': (x: p7o.dx, y: p7o.dy),
            'ego': (x: egoAt!.dx, y: egoAt.dy),
          },
          egoId: 'ego',
          excludePersonIds: const {'p6'},
        )!;
        final dx = p6o.dx - c.x;
        final dy = p6o.dy - c.y;
        expect(dx * dx + dy * dy, lessThan(r * r + 250000));
      },
    );
  });
}
