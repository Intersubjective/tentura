@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _authorCount = 30;
const _requestsPerAuthor = 6;

final _person = ConstellationAnchorTarget.person('p0');

const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.2,
  yUnits: 0.3,
  coordinateSpaceVersion: 1,
);

ConstellationAnchor _anchor(
  ConstellationAnchorPosition position,
  int revision,
) => ConstellationAnchor(
  target: _person,
  position: position,
  revision: ConstellationAnchorRevision(BigInt.from(revision)),
  placedAt: DateTime.utc(2026, 9, 9),
);

/// Many authors that each have more requests than the label budget draws, so
/// the overlay mounts a "more requests" chip per author.
ConstellationField _crowdedField() {
  final peers = [
    for (var i = 0; i < _authorCount; i++)
      ConstellationPerson(id: 'p$i', displayName: 'Person $i'),
  ];
  final requests = [
    for (var i = 0; i < _authorCount; i++)
      for (var j = 0; j < _requestsPerAuthor; j++)
        ConstellationRequest(
          id: 'req-p$i-$j',
          authorId: 'p$i',
          title: 'Request $j of person $i',
          status: 0,
        ),
  ];
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 9, 12),
    context: '',
    peers: peers,
    edges: [
      for (final peer in peers)
        ConstellationTrustEdgeEntity(src: 'ego', dst: peer.id, tier: 1),
    ],
    requests: requests,
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [_anchor(_pinnedAt, 1)],
      pinnedPeers: [peers.first],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// Holds every apply until the test acknowledges it, like a slow server.
final class _AnchorRepository implements ConstellationWriteFake {
  _AnchorRepository(this._confirmedBase);

  final ConstellationAnchorProjection _confirmedBase;
  final calls =
      <
        ({
          List<ConstellationAnchorApplyOp> ops,
          Completer<ConstellationAnchorApplyResult> reply,
        })
      >[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    final reply = Completer<ConstellationAnchorApplyResult>();
    calls.add((ops: List.of(ops), reply: reply));
    return reply.future;
  }

  /// Acknowledges call [index] with the projection the server would hold
  /// afterwards: the same field content, revision 2, the ops applied.
  void ack(int index) {
    final call = calls[index];
    final revision = ConstellationAnchorRevision(BigInt.two);
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _confirmedBase.revision,
        afterRevision: revision,
        results: [
          for (final op in call.ops)
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: revision,
              target: op.target,
              anchor: _anchor(op.position!, 2),
            ),
        ],
      ),
    );
  }

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) => throw StateError('Placement must use batched apply');

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) => throw StateError('Unpin must use batched apply');
}

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Counts builds of every overflow chip's cubit builder from now on. A chip
/// that is mounted and not replaced by its parent only builds again because
/// its `buildWhen` let a state change through.
({int Function() builds, Map<String, int> Function() byAuthor})
_countChipBuilderBuilds() {
  final byAuthor = <String, int>{};
  final previous = debugOnRebuildDirtyWidget;
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (element.widget is BlocBuilder<ConstellationCubit, ConstellationState>) {
      String? authorId;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is ConstellationOverflowGroup) authorId = widget.authorId;
        return authorId == null;
      });
      if (authorId != null) {
        byAuthor[authorId!] = (byAuthor[authorId] ?? 0) + 1;
      }
    }
  };
  return (
    builds: () => byAuthor.values.fold(0, (a, b) => a + b),
    byAuthor: () => Map.of(byAuthor),
  );
}

void main() {
  group('Overflow chips on a server acknowledgement of a placement', () {
    testWidgets('no mounted chip rebuilds when a drop is acknowledged '
        'unchanged', (tester) async {
      final field = _crowdedField();
      final server = _AnchorRepository(field.resolvedAnchorProjection);
      final sync = buildTestRealtimeSync();
      final store = ConstellationStoreFixture(
        _FieldRepository(field),
        accountId: 'ego',
        realtime: sync.case_,
      ).store;
      final placement = ConstellationPlacementCase(
        server,
        store,
        FakeClockPort(),
        FakeWakeUpPort(),
        realtime: sync.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('OverflowChipsPlacementAckTest'),
      );
      final cubit = ConstellationCubit(
        case_: store,
        placementCase: placement,
        viewer: kRefEgo,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1600, 1000),
      );
      await tester.pumpAndSettle();

      final chipCount = find.byType(ConstellationOverflowGroup).evaluate().length;
      expect(
        chipCount,
        greaterThanOrEqualTo(8),
        reason: 'fixture must mount many overflow chips to make the ack '
            'fan-out measurable',
      );

      const dropCentre = Offset(240, 180);
      cubit
        ..beginDragExisting(target: _person)
        ..updateDragPresentation(nodeId: 'fp:p0', sceneCentre: dropCentre);
      await cubit.onExistingNodeDrop(target: _person, sceneCentre: dropCentre);
      await _settleFrames(tester);
      expect(server.calls, hasLength(1));
      final sent = server.calls.single.ops.single.position!;
      expect(sent, isNot(_pinnedAt));

      // Positive control: the drop itself (before the ack) is allowed to
      // rebuild chips; only the ack is pinned below.
      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = cubit.graphController.relayoutInvocationCount;
      final counter = _countChipBuilderBuilds();

      server.ack(0);
      await _settleFrames(tester);

      expect(
        cubit.state.confirmedProjection!.revision,
        ConstellationAnchorRevision(BigInt.two),
        reason: 'the acknowledgement must have been consumed',
      );
      expect(
        cubit.layoutReconciliationCount,
        reconciliations,
        reason: 'an unchanged ack must not recompose the scene',
      );
      expect(cubit.graphController.relayoutInvocationCount, layoutRuns);
      expect(
        find.byType(ConstellationOverflowGroup).evaluate().length,
        chipCount,
        reason: 'the ack must not change which chips are mounted',
      );
      expect(
        counter.byAuthor(),
        isEmpty,
        reason: 'no overflow chip builder may fire on an unchanged ack',
      );
      expect(counter.builds(), 0);
    });
  });
}
