import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart'
    as layout_domain;
import 'package:tentura/features/constellation/domain/constellation_pin_position.dart';
import 'package:tentura/features/constellation/domain/constellation_rearrange_all.dart';
import 'package:tentura/features/constellation/domain/constellation_rearrange_tag_areas.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';

layout_domain.ConstellationLayout _placed(layout_domain.ConstellationPlacedLayoutInput i) =>
    layout_domain.computeConstellationPlacedLayout(input: i);

/// 7abw.7 — Rearrange everyone: every member the tag stage seats is pinned on Apply.
const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 11, 12);

Set<String> _tagsFromStore(String personId) => switch (personId) {
  'p3' => {'t1'},
  'p4' => {'t2'},
  'p5' => {'t1', 't2'},
  _ => const <String>{},
};

ConstellationField _twoTagField() {
  const peers = [
    ConstellationPerson(id: 'p1', displayName: 'Peer one'),
    ConstellationPerson(id: 'p2', displayName: 'Peer two'),
    ConstellationPerson(id: 'p3', displayName: 'Peer three'),
    ConstellationPerson(id: 'p4', displayName: 'Peer four'),
    ConstellationPerson(id: 'p5', displayName: 'Peer five'),
  ];
  const pinnedAt = <String, ConstellationAnchorPosition>{
    'p1': ConstellationAnchorPosition(
      xUnits: 1,
      yUnits: 2,
      coordinateSpaceVersion: 1,
    ),
    'p2': ConstellationAnchorPosition(
      xUnits: 3,
      yUnits: 4,
      coordinateSpaceVersion: 1,
    ),
  };
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: peers,
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [
        for (final entry in pinnedAt.entries)
          ConstellationAnchor(
            target: ConstellationAnchorTarget.person(entry.key),
            position: entry.value,
            revision: ConstellationAnchorRevision(BigInt.one),
            placedAt: DateTime.utc(2026, 9, 11),
          ),
      ],
      pinnedPeers: peers,
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _TagFieldRepository implements ConstellationRepositoryPort {
  _TagFieldRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
}

final class _TestAnchorServer implements ConstellationWriteFake {
  _TestAnchorServer(this._anchors);

  final Map<ConstellationAnchorTarget, ConstellationAnchorPosition> _anchors;

  final events = <String>[];
  final batches = <List<ConstellationAnchorApplyOp>>[];
  var _revision = BigInt.from(10);

  Map<ConstellationAnchorTarget, ConstellationAnchorPosition> get anchors =>
      {..._anchors};

  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) async {
    events.add('save:$reason');
    return 'snap';
  }

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) async {
    events.add('restore');
    return 'snap2';
  }

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    events.add('apply');
    batches.add(ops);
    final before = ConstellationAnchorRevision(_revision);
    final results = <ConstellationAnchorOpResult>[];
    for (final op in ops) {
      _revision += BigInt.one;
      final revision = ConstellationAnchorRevision(_revision);
      switch (op.kind) {
        case ConstellationAnchorOpKind.upsert:
          _anchors[op.target] = op.position!;
          results.add(
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: revision,
              target: op.target,
              anchor: ConstellationAnchor(
                target: op.target,
                position: op.position!,
                revision: revision,
                placedAt: DateTime.utc(2026, 9, 11, 1),
              ),
            ),
          );
        case ConstellationAnchorOpKind.delete:
          _anchors.remove(op.target);
          results.add(
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: revision,
              target: op.target,
            ),
          );
      }
    }
    return ConstellationAnchorApplyResult(
      beforeRevision: before,
      afterRevision: ConstellationAnchorRevision(_revision),
      results: results,
    );
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) =>
      throw UnimplementedError();

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) =>
      throw UnimplementedError();
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<
  ({
    ConstellationCubit cubit,
    ConstellationPlacementCase placement,
    _TestAnchorServer server,
  })
>
_harness() async {
  final fieldRepo = _TagFieldRepository(_twoTagField());
  final server = _TestAnchorServer({
    ConstellationAnchorTarget.person('p1'): const ConstellationAnchorPosition(
      xUnits: 1,
      yUnits: 2,
      coordinateSpaceVersion: 1,
    ),
    ConstellationAnchorTarget.person('p2'): const ConstellationAnchorPosition(
      xUnits: 3,
      yUnits: 4,
      coordinateSpaceVersion: 1,
    ),
  });
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    fieldRepo,
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    server,
    store,
    FakeClockPort(),
    FakeWakeUpPort(),
    realtime: sync.case_,
    recordAutomaticHistory: false,
    env: const Env.fromEnvironment(),
    logger: Logger('RearrangeTagPinsTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: ConstellationAnchorCase(
      env: const Env.fromEnvironment(),
      logger: Logger('RearrangeTagPinsTest'),
    ),
    placementCase: placement,
    viewer: _ego,
    forwardCase: buildTestForwardCase(_FakeForwardRepository()),
    ownTagIdsOf: _tagsFromStore,
    loadOnCreate: false,
  );
  await cubit.load();
  addTearDown(() async {
    await cubit.close();
    await placement.dispose();
  });
  return (cubit: cubit, placement: placement, server: server);
}

/// applyRearrangePreview / undoArrangement return when the snapshot step
/// completes; the outbox applies on the next microtask.
Future<void> _settlePlacement(ConstellationPlacementCase placement) async {
  await Future<void>.delayed(Duration.zero);
  await placement.flushPendingPlacements();
}

void main() {
  group('Rearrange everyone tagged-member pins (7abw.7)', () {
    setUp(registerEmptyPeopleTags);

    test('preview and apply pin every tagged person the tag stage seats', () async {
      final h = await _harness();
      final cubit = h.cubit;

      // ignore: cascade_invocations — read state after preview; cascade would not clarify.
      cubit.previewRearrangeAll();
      final state = cubit.state;
      final preview = state.rearrangePreview!;

      final composition = state.composition!;
      final snapshot = cubit.graphController.renderSnapshot;
      final rearrangeOwnTagPeopleByTagId = rearrangeOwnTagPeopleFromComposition(
        viewerId: _ego.id,
        composition: composition,
        ownTagIdsOf: _tagsFromStore,
      );
      final input = layoutInputFromComposition(
        viewerId: _ego.id,
        composition: composition,
        labelPlan: composition.labelPlan,
        nodeSizes: {
          for (final MapEntry(:key, :value) in snapshot.topology.nodesById.entries)
            tenturaLayoutDomainId(key): (
              width: value.size.width,
              height: value.size.height,
            ),
        },
        spacing: 16,
        footprints: cubit.layoutFootprints,
        rearrangeOwnTagPeopleByTagId: rearrangeOwnTagPeopleByTagId,
      );
      final rearranged = computeConstellationRearrangeAll(input);
      final loose = constellationRearrangeLoosePlacementInput(input);
      final free = _placed(loose);
      final tagAreaIds = constellationRearrangeTagStaging(
        input: input,
        freeLayout: free,
      ).areaPositions.keys.toSet();

      expect(tagAreaIds, isNotEmpty, reason: 'fixture should seat tagged people');

      for (final id in tagAreaIds) {
        final tgt = ConstellationAnchorTarget.person(id);
        final point = rearranged.layout.positions[id];
        expect(point, isNotNull);
        expect(
          preview.pinnedWrites[tgt],
          layout_domain.constellationPointToV1Anchor(point!),
        );
      }

      expect(await cubit.applyRearrangePreview(), isTrue);
      await _settlePlacement(h.placement);

      expect(h.server.events, ['save:rebuild', 'apply']);
      final targets = <ConstellationAnchorTarget>{
        for (final batch in h.server.batches)
          for (final op in batch) op.target,
      };
      for (final id in tagAreaIds) {
        expect(targets, contains(ConstellationAnchorTarget.person(id)));
      }

      expect(await cubit.undoArrangement(), isTrue);
      await _settlePlacement(h.placement);
      for (final id in tagAreaIds) {
        expect(cubit.isAnchored(ConstellationAnchorTarget.person(id)), isFalse);
      }
    });

    test('cancel leaves anchors unchanged', () async {
      final h = await _harness();
      final before = Map<ConstellationAnchorTarget, ConstellationAnchorPosition>.from(
        h.server.anchors,
      );
      h.cubit
        ..previewRearrangeAll()
        ..cancelRearrangePreview();
      expect(h.server.anchors, before);
      expect(h.server.events, isEmpty);
    });
  });
}
