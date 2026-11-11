// The Field does not refit under the user when the server echoes back the tag
// magnet the user has just dropped, but still follows a magnet changed from
// somewhere else.
//
// Real path: the Field body mounted over the real store and
// ConstellationCubit, the real tag magnet use case (save, list, the realtime
// `personTag` hint) over a fake magnet repository that behaves like the
// server: it stores what is saved and lists it back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_arrange_harness.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _workTag = 'work';
const _workPeople = {'p1', 'p2'};

Set<String> _tagsOf(String personId) =>
    _workPeople.contains(personId) ? const {_workTag} : const {};

Set<String> _peopleIn(String tagId) =>
    tagId == _workTag ? _workPeople : const {};

/// A drop position whose v1 anchor round-trip is not exact in doubles:
/// `centre + ((p - centre) / unit) * unit` differs from `p` in the last bit.
const _inexactDrop = Offset(13678.813, kConstellationCanvasCentre - 120);

/// The premise of the echo cases: the drop does not survive the v1 anchor
/// round-trip bit for bit, so the echoed magnet differs from what the user
/// dropped. Fails loudly if the constant ever round-trips exactly.
void _expectDropDoesNotRoundTripExactly() {
  final units = constellationPointToV1Anchor((
    x: _inexactDrop.dx,
    y: _inexactDrop.dy,
  ));
  final back = constellationV1AnchorToPoint(units);
  expect(
    back.x != _inexactDrop.dx || back.y != _inexactDrop.dy,
    isTrue,
    reason:
        'the dropped position must not survive constellationPointToV1Anchor '
        '-> constellationV1AnchorToPoint exactly (got ${back.x}, ${back.y})',
  );
}

/// Somewhere else on the canvas, as another device would have left the magnet.
const _elsewhere = Offset(
  kConstellationCanvasCentre - 420,
  kConstellationCanvasCentre + 380,
);

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    const peers = [
      ConstellationPerson(id: 'p1', displayName: 'Peer one'),
      ConstellationPerson(id: 'p2', displayName: 'Peer two'),
      ConstellationPerson(id: 'p3', displayName: 'Peer three'),
      ConstellationPerson(id: 'p4', displayName: 'Peer four'),
    ];
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 11, 10),
      context: '',
      peers: peers,
      directContactIds: [for (final p in peers) p.id],
      edges: [
        for (final p in peers)
          ConstellationTrustEdgeEntity(src: 'ego', dst: p.id, tier: 1),
      ],
    );
  }
}

/// The server side of the magnet API: stores what is saved, lists it back.
final class _MagnetServer implements ConstellationTagMagnetRepositoryPort {
  List<ConstellationTagMagnet> stored = [];
  int listCalls = 0;
  int upserts = 0;

  @override
  Future<List<ConstellationTagMagnet>> list() async {
    listCalls++;
    return [...stored];
  }

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) async {
    upserts++;
    final magnet = ConstellationTagMagnet(
      tagId: tagId,
      xUnits: xUnits,
      yUnits: yUnits,
      revision: upserts,
    );
    stored = [
      for (final m in stored)
        if (m.tagId != tagId) m,
      magnet,
    ];
    return magnet;
  }

  @override
  Future<void> remove({
    required String tagId,
    required String clientOpId,
  }) async {
    stored = [
      for (final m in stored)
        if (m.tagId != tagId) m,
    ];
  }
}

ConstellationTagMagnet _magnetAt(Offset scene, {int revision = 1}) {
  final units = constellationPointToV1Anchor((x: scene.dx, y: scene.dy));
  return ConstellationTagMagnet(
    tagId: _workTag,
    xUnits: units.xUnits,
    yUnits: units.yUnits,
    revision: revision,
  );
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

typedef _Rig = ({
  ConstellationCubit cubit,
  _MagnetServer server,
  TestRealtimeSyncPort realtime,
});

/// The Field on screen with its initial fit done and the camera untouched.
Future<_Rig> _openField(WidgetTester tester) async {
  final server = _MagnetServer();
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _FieldRepository(),
      accountId: 'ego',
      realtime: realtime.case_,
    ).store,
    viewer: _ego,
    tagMagnetCase: ConstellationTagMagnetCase(
      server,
      realtime.case_,
      env: const Env(),
      logger: Logger('tag-magnet-echo'),
    ),
    ownTagIdsOf: _tagsOf,
    peopleInTag: _peopleIn,
    loadOnCreate: false,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!cubit.isClosed) await cubit.close();
  });
  await tester.runAsync(cubit.load);
  await pumpArrangeBody(tester, cubit, arrangeV2Enabled: true);
  await _pumpFrames(tester, 120);
  expect(
    cubit.fieldInitialFrameCompletedForTest,
    isTrue,
    reason: 'the Field has been fitted once',
  );
  expect(cubit.graphController.userCameraInputRevision.value, 0);
  return (cubit: cubit, server: server, realtime: realtime.port);
}

void _expectAt(Offset? actual, Offset expected, {required String reason}) {
  expect(actual, isNotNull, reason: reason);
  expect((actual! - expected).distance, lessThan(1e-6), reason: reason);
}

RealtimeEntityChange _personTagHint(int revision) => RealtimeEntityChange(
  kind: RealtimeEntityKind.personTag,
  aggregateId: 'ego',
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
  revision: BigInt.from(revision),
);

void main() {
  group('tag magnet change hint after the user dropped a magnet', () {
    test('the drop used by these cases is not exact after the v1 anchor '
        'round-trip', _expectDropDoesNotRoundTripExactly);

    testWidgets("the echo of the user's own drop neither refits the Field "
        'nor moves the magnet', (tester) async {
      final rig = await _openField(tester);

      rig.cubit.placeTagMagnet(
        tagId: _workTag,
        position: _inexactDrop,
        tagsOfPerson: _tagsOf,
      );
      await _pumpFrames(tester, 240);
      expect(rig.server.upserts, 1, reason: 'the drop was saved');
      final cameraAfterDrop = rig.cubit.graphController.cameraRevision.value;
      final listsBefore = rig.server.listCalls;

      rig.realtime.emitChange(_personTagHint(2));
      await _pumpFrames(tester, 180);

      expect(
        rig.server.listCalls,
        greaterThan(listsBefore),
        reason: 'the change hint made the cubit read the magnets back',
      );
      expect(
        rig.cubit.graphController.cameraRevision.value,
        cameraAfterDrop,
        reason: 'the Field is not refit under the user',
      );
      _expectAt(
        rig.cubit.tagMagnets[_workTag],
        _inexactDrop,
        reason: 'the magnet stays where the user dropped it',
      );
    });

    testWidgets('a magnet moved from another device still moves here and '
        'refits the Field', (tester) async {
      _expectDropDoesNotRoundTripExactly();
      final rig = await _openField(tester);
      rig.cubit.placeTagMagnet(
        tagId: _workTag,
        position: _inexactDrop,
        tagsOfPerson: _tagsOf,
      );
      await _pumpFrames(tester, 240);
      final cameraAfterDrop = rig.cubit.graphController.cameraRevision.value;
      final listsBefore = rig.server.listCalls;

      rig.server.stored = [_magnetAt(_elsewhere, revision: 9)];
      rig.realtime.emitChange(_personTagHint(9));
      await _pumpFrames(tester, 180);

      expect(rig.server.listCalls, greaterThan(listsBefore));
      _expectAt(
        rig.cubit.tagMagnets[_workTag],
        _elsewhere,
        reason: 'the magnet follows the change made elsewhere',
      );
      expect(
        rig.cubit.graphController.cameraRevision.value,
        greaterThan(cameraAfterDrop),
        reason: 'the Field is refit to the new layout (camera moved on)',
      );
    });
  });
}
