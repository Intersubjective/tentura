// Pin availability must not rerun the whole placed layout once per Pin
// button. Every ConstellationAnchorTargetButton asks canPinTarget, and each
// ask used to lay out the entire composition, so a drop (or the first frame
// after grabbing a node, when the placement phase change rebuilds every
// button) cost one full layout per visible tile.
//
// Work is pinned with a counter, never wall-clock:
// `constellationPinLayoutRunCount` (constellation_pin_position.dart, a
// `@visibleForTesting` top-level getter) is the number of placed-layout runs
// performed on behalf of pin positions. It is incremented where the placed
// layout actually runs, so it cannot be satisfied by caching only the layout
// *input* (`ConstellationCubit.pinLayoutInputBuildCount` is asserted
// separately and must stay independent of it). One run per composition is
// allowed (a shared, memoised layout); none is also fine (availability
// derived from positions the scene already has).
//
// Behaviour is pinned too: every target stays pinnable, and the position the
// Pin action sends equals the one the unmemoised computation produced, both
// before and after a drop changes the composition.

import 'dart:ui' show Size;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_pin_position.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_anchor_controls.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_composer_screen_harness.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

const _ids = ['a', 'b', 'c', 'd', 'e', 'f'];

final _people = [for (final id in _ids) ConstellationAnchorTarget.person(id)];
final _requests = [
  for (final id in _ids) ConstellationAnchorTarget.beacon('req-$id'),
];

ConstellationField _wideField() {
  final base = composerHarnessField(peers: _ids);
  return ConstellationField(
    loadedAt: base.loadedAt,
    context: base.context,
    peers: base.peers,
    edges: base.edges,
    requests: [
      for (final id in _ids)
        ConstellationRequest(
          id: 'req-$id',
          authorId: id,
          title: 'Need $id',
          status: 0,
          needs: const ['tools'],
        ),
    ],
  );
}

final class _FieldRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => _wideField();
}

/// Holds every apply until the test acknowledges it, like a slow server.
final class _Server implements ConstellationWriteFake {
  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) => throw UnimplementedError('snapshots are not used by this test');

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError('restore is not used by this test');

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnimplementedError('reset is not used by this test');

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

  ConstellationAnchorPosition sentPosition(int call) =>
      calls[call].ops.single.position!;

  void ack(int index, {required int revision}) {
    final call = calls[index];
    final after = ConstellationAnchorRevision(BigInt.from(revision));
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: ConstellationAnchorRevision(
          BigInt.from(revision - 1),
        ),
        afterRevision: after,
        results: [
          for (final op in call.ops)
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.ok,
              resultingTargetRevision: after,
              target: op.target,
              anchor: ConstellationAnchor(
                target: op.target,
                position: op.position!,
                revision: after,
                placedAt: DateTime.utc(2026, 10, 9),
              ),
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

typedef _Screen = ({ConstellationCubit cubit, _Server server});

Future<_Screen> _pumpScreen(WidgetTester tester) async {
  final server = _Server();
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _FieldRepository(),
    accountId: composerHarnessEgo.id,
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    server,
    store,
    FakeClockPort(),
    FakeWakeUpPort(),
    realtime: sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationPinLayoutComputeBudgetTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: composerHarnessEgo,
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  // Tall enough for every person's tile below the list's search field
  // (#253): the assertions cover all of them.
  await pumpComposerHarnessScreen(
    tester,
    cubit: cubit,
    composer: buildComposerHarnessComposer(),
    size: const Size(1280, 1100),
  );
  return (cubit: cubit, server: server);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _showTextView(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  cubit.setViewMode(ConstellationViewMode.text);
  await tester.pumpAndSettle();
  expect(
    find.byType(ConstellationAnchorTargetButton),
    findsAtLeastNWidgets(_ids.length),
  );
}

void main() {
  group('layout runs for pin availability', () {
    testWidgets(
      'querying every person and request shares at most one layout per '
      'composition, whoever asks',
      (tester) async {
        final (:cubit, server: _) = await _pumpScreen(tester);
        final targets = [..._people, ..._requests];

        final runs = constellationPinLayoutRunCount;
        final inputs = cubit.pinLayoutInputBuildCount;
        final first = [for (final t in targets) cubit.canPinTarget(t)];
        expect(first, everyElement(isTrue), reason: 'visible behaviour kept');
        expect(
          constellationPinLayoutRunCount - runs,
          lessThanOrEqualTo(1),
          reason: '12 direct queries against one composition share one layout',
        );

        // The input is now warm: more queries must neither rebuild the input
        // nor run a layout, so a layout run cannot hide behind the input
        // memo.
        final warmRuns = constellationPinLayoutRunCount;
        final warmInputs = cubit.pinLayoutInputBuildCount;
        final second = [for (final t in targets) cubit.canPinTarget(t)];
        expect(second, first);
        expect(cubit.pinLayoutInputBuildCount, warmInputs);
        expect(
          constellationPinLayoutRunCount,
          warmRuns,
          reason: 'a warm input must not mean a layout per query',
        );
        expect(
          cubit.pinLayoutInputBuildCount - inputs,
          lessThanOrEqualTo(1),
          reason: 'the input itself is still shared across queries',
        );
      },
    );

    testWidgets(
      'an unknown target stays unpinnable without a layout per query',
      (tester) async {
        final (:cubit, server: _) = await _pumpScreen(tester);
        final missing = ConstellationAnchorTarget.beacon('req-missing');
        expect(cubit.canPinTarget(missing), isFalse);

        final runs = constellationPinLayoutRunCount;
        for (var i = 0; i < 5; i++) {
          expect(cubit.canPinTarget(missing), isFalse);
        }
        expect(
          constellationPinLayoutRunCount - runs,
          0,
          reason: 'repeated queries of the same composition reuse the layout',
        );
      },
    );

    testWidgets(
      'mounting the text view runs at most one layout for all of its Pin '
      'buttons',
      (tester) async {
        final (:cubit, server: _) = await _pumpScreen(tester);
        final runs = constellationPinLayoutRunCount;

        await _showTextView(tester, cubit);

        expect(
          constellationPinLayoutRunCount - runs,
          lessThanOrEqualTo(1),
          reason: 'per-tile buttons must not each lay out the composition',
        );
      },
    );

    testWidgets(
      'grabbing a node rebuilds the Pin buttons without a layout run',
      (tester) async {
        final (:cubit, server: _) = await _pumpScreen(tester);
        await _showTextView(tester, cubit);
        final composition = cubit.state.composition;
        final warmed = constellationPinLayoutRunCount;

        cubit.beginDragExisting(
          target: ConstellationAnchorTarget.beacon('req-a'),
        );
        await tester.pumpAndSettle();

        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingExisting,
        );
        expect(
          identical(cubit.state.composition, composition),
          isTrue,
          reason: 'precondition: only the placement phase changed',
        );
        expect(
          constellationPinLayoutRunCount - warmed,
          0,
          reason: 'a phase change over an unchanged composition reuses layout',
        );
      },
    );

    testWidgets(
      'dropping a node and acknowledging it runs at most one layout per '
      'composition the buttons see',
      (tester) async {
        final (:cubit, :server) = await _pumpScreen(tester);
        await _showTextView(tester, cubit);
        for (final t in [..._people, ..._requests]) {
          expect(cubit.canPinTarget(t), isTrue);
        }

        var compositions = 0;
        Object? seen = cubit.state.composition;
        final sub = cubit.stream.listen((state) {
          if (!identical(state.composition, seen)) {
            seen = state.composition;
            compositions++;
          }
        });
        addTearDown(sub.cancel);
        final runs = constellationPinLayoutRunCount;

        final target = ConstellationAnchorTarget.beacon('req-a');
        const dropCentre = Offset(240, 180);
        cubit
          ..beginDragExisting(target: target)
          ..updateDragPresentation(
            nodeId: target.graphNodeId,
            sceneCentre: dropCentre,
          );
        await tester.pumpAndSettle();
        await cubit.onExistingNodeDrop(target: target, sceneCentre: dropCentre);
        await _settle(tester);
        expect(server.calls, hasLength(1));
        server.ack(0, revision: 2);
        await _settle(tester);
        await tester.pumpAndSettle();

        expect(
          compositions,
          greaterThan(0),
          reason: 'positive control: the drop recomposed the field',
        );
        expect(
          constellationPinLayoutRunCount - runs,
          lessThanOrEqualTo(compositions),
          reason:
              'the drop, its optimistic state and its ack each cost at '
              'most one shared layout, never one per Pin button',
        );
        expect(
          cubit.isAnchored(target),
          isTrue,
          reason: 'the dropped request is now pinned',
        );
        for (final t in [..._people, ..._requests]) {
          expect(cubit.canPinTarget(t), isTrue, reason: '$t stays pinnable');
        }
      },
    );
  });

  group('pin position sent by the Pin action', () {
    testWidgets(
      'equals the unmemoised layout position for people and requests across '
      'pins and a drop',
      (tester) async {
        final (:cubit, :server) = await _pumpScreen(tester);
        await _showTextView(tester, cubit);

        // Pins one target: the position sent is what a fresh, uncached
        // layout of the composition at the moment of the press yields.
        Future<void> pinAndAck(ConstellationAnchorTarget target) async {
          final expected = _referencePinPosition(cubit, target);
          expect(expected, isNotNull, reason: '$target has a reference');
          expect(cubit.canPinTarget(target), isTrue);
          final before = server.calls.length;
          await cubit.pinFromText(target: target);
          await _settle(tester);
          expect(server.calls, hasLength(before + 1), reason: '$target sent');
          final sent = server.sentPosition(before);
          expect(
            sent.xUnits,
            closeTo(expected!.xUnits, 1e-9),
            reason: '$target x',
          );
          expect(
            sent.yUnits,
            closeTo(expected.yUnits, 1e-9),
            reason: '$target y',
          );
          expect(sent.coordinateSpaceVersion, expected.coordinateSpaceVersion);
          server.ack(before, revision: before + 2);
          await _settle(tester);
          expect(cubit.isAnchored(target), isTrue, reason: '$target pinned');
          expect(cubit.canPinTarget(target), isTrue, reason: 'can unpin');
        }

        // Availability agrees with the reference for every target.
        void expectAvailabilityMatchesReference() {
          for (final t in [..._people, ..._requests]) {
            expect(
              cubit.canPinTarget(t),
              _referencePinPosition(cubit, t) != null,
              reason: '$t availability',
            );
          }
        }

        expectAvailabilityMatchesReference();
        await pinAndAck(ConstellationAnchorTarget.person('c'));
        // Each acknowledged pin recomposes: later presses must not read a
        // layout memoised for the earlier composition.
        await pinAndAck(ConstellationAnchorTarget.beacon('req-b'));
        expectAvailabilityMatchesReference();

        final dropped = ConstellationAnchorTarget.beacon('req-a');
        const dropCentre = Offset(240, 180);
        cubit
          ..beginDragExisting(target: dropped)
          ..updateDragPresentation(
            nodeId: dropped.graphNodeId,
            sceneCentre: dropCentre,
          );
        await cubit.onExistingNodeDrop(
          target: dropped,
          sceneCentre: dropCentre,
        );
        await _settle(tester);
        server.ack(server.calls.length - 1, revision: server.calls.length + 1);
        await _settle(tester);
        expect(cubit.isAnchored(dropped), isTrue);
        expectAvailabilityMatchesReference();

        await pinAndAck(ConstellationAnchorTarget.person('d'));
        await pinAndAck(ConstellationAnchorTarget.beacon('req-e'));
        await pinAndAck(ConstellationAnchorTarget.person('f'));
        expectAvailabilityMatchesReference();
      },
    );
  });
}

/// The pin position from a fresh layout of the current composition, computed
/// without any cubit-side memo: the reference the optimised path must match.
ConstellationAnchorPosition? _referencePinPosition(
  ConstellationCubit cubit,
  ConstellationAnchorTarget target,
) {
  final composition = cubit.state.composition!;
  return computeConstellationPinPosition(
    target: target,
    layoutInput: layoutInputFromComposition(
      viewerId: composerHarnessEgo.id,
      composition: composition,
      labelPlan: composition.labelPlan,
      nodeSizes: const {},
      spacing: 16,
      footprints: cubit.layoutFootprints,
    ),
  );
}
