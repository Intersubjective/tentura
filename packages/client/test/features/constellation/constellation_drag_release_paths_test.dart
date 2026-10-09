import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

final _pinnedPerson = ConstellationAnchorTarget.person('am');
final _freePerson = ConstellationAnchorTarget.person('in');
const _freeNodeId = 'fp:in';
final _otherPerson = ConstellationAnchorTarget.person('sm');
final _heldRequest = ConstellationAnchorTarget.beacon('req-ego-3');
const _heldRequestNodeId = 'fr:req-ego-3';

/// The field on screen has this many of the viewer's own requests; a store
/// refresh to [_refreshedEgoRequests] adds requests, and one to
/// [_revokedEgoRequests] takes [_heldRequest] away.
const _mountedEgoRequests = 3;
const _refreshedEgoRequests = 5;
const _revokedEgoRequests = 2;

const _otherPlacedAt = ConstellationAnchorPosition(
  xUnits: 0.6,
  yUnits: 0.5,
  coordinateSpaceVersion: 1,
);

const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.2,
  yUnits: 0.3,
  coordinateSpaceVersion: 1,
);

ConstellationAnchor _pinnedAnchor() => ConstellationAnchor(
  target: _pinnedPerson,
  position: _pinnedAt,
  revision: ConstellationAnchorRevision(BigInt.one),
  placedAt: DateTime.utc(2026, 9, 9),
);

final class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

/// A server that records writes and never answers them.
final class _SilentAnchorRepository
    implements ConstellationAnchorRepositoryPort {
  final applyCalls = <List<ConstellationAnchorApplyOp>>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) {
    applyCalls.add(List.of(ops));
    return Completer<ConstellationAnchorApplyResult>().future;
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

/// Lays every node out at a distinctive spot that moves with every further
/// layout run, so each run that reaches the scene shows up as movement and
/// every run is counted.
final class _CountingAlgorithm implements SceneLayoutAlgorithm {
  _CountingAlgorithm({this.shiftPerRequest = 25});

  final double shiftPerRequest;
  int requests = 0;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    requests++;
    final shift = shiftPerRequest * requests;
    var index = 0;
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      positions: {
        for (final id in request.nodeIds)
          id: ScenePoint(
            x: 120.0 + shift + 70 * index,
            y: 90.0 + shift + 45 * index++,
          ),
      },
      isTerminal: true,
    );
  }
}

typedef _Harness = ({
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  ConstellationFieldStoreCase store,
  _FieldRepository repository,
  _SilentAnchorRepository server,
  _CountingAlgorithm algorithm,
  _Counters counters,
});

/// What the scene did since [reset]: how many presentations were composed and
/// how many layouts ran.
final class _Counters {
  _Counters(this._cubit, this._algorithm) {
    reset();
    _sub = _cubit.stream.listen((state) {
      if (!identical(state.composition, _lastComposition)) {
        _lastComposition = state.composition;
        composes++;
      }
    });
  }

  final ConstellationCubit _cubit;
  final _CountingAlgorithm _algorithm;
  late final StreamSubscription<ConstellationState> _sub;
  Object? _lastComposition;
  int composes = 0;
  var _algorithmRunsAtReset = 0;

  void reset() {
    _lastComposition = _cubit.state.composition;
    composes = 0;
    _algorithmRunsAtReset = _algorithm.requests;
  }

  int get algorithmRuns => _algorithm.requests - _algorithmRunsAtReset;

  Future<void> dispose() => _sub.cancel();
}

Future<_Harness> _mount(WidgetTester tester) async {
  final repository = _FieldRepository(
    constellationReferenceField(
      egoRequestCount: _mountedEgoRequests,
      anchors: [_pinnedAnchor()],
    ),
  );
  final server = _SilentAnchorRepository();
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    repository,
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
    logger: Logger('ConstellationDragReleasePathsTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: kRefEgo,
  );
  addTearDown(cubit.close);
  if (cubit.state.status is! StateIsSuccess) {
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  }
  await pumpConstellationBody(tester, cubit, size: const Size(800, 700));
  await _settleFrames(tester);
  // The scene starts on the real layout, so every node is reachable by a
  // pointer; layouts after this point are the counted ones.
  final algorithm = _CountingAlgorithm();
  cubit.testSceneLayoutAlgorithmOverride = algorithm;
  final counters = _Counters(cubit, algorithm);
  addTearDown(counters.dispose);
  return (
    cubit: cubit,
    placement: placement,
    store: store,
    repository: repository,
    server: server,
    algorithm: algorithm,
    counters: counters,
  );
}

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _nodeFinder(ConstellationAnchorTarget target) =>
    find.byKey(TestIds.key(TestIds.graphNode(target.graphNodeId)));

/// Picks the free person up with a real pointer and moves it past the slop.
Future<TestGesture> _pickUpFreePerson(
  WidgetTester tester,
  _Harness harness, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_nodeFinder(_freePerson)),
    kind: kind,
  );
  await gesture.moveBy(const Offset(40, 30));
  await tester.pump();
  await gesture.moveBy(const Offset(40, 30));
  await tester.pump();
  expect(
    harness.cubit.state.placementPhase,
    ConstellationPlacementPhase.draggingNew,
    reason: 'the pointer must have picked the node up',
  );
  return gesture;
}

/// A store refresh that adds requests to the field on screen.
Future<void> _refreshStoreWithMoreRequests(
  WidgetTester tester,
  _Harness harness,
) async {
  final before = harness.store.current.field!.requests.length;
  harness.repository.field = constellationReferenceField(
    egoRequestCount: _refreshedEgoRequests,
    anchors: [_pinnedAnchor()],
  );
  await harness.store.requestRefresh(ConstellationRefreshReason.load);
  await _settleFrames(tester);
  expect(
    harness.store.current.field!.requests.length,
    greaterThan(before),
    reason: 'the refresh must have added requests',
  );
}

/// A store refresh that takes [_heldRequest] away from the viewer.
Future<void> _refreshStoreRevokingHeldRequest(
  WidgetTester tester,
  _Harness harness,
) async {
  harness.repository.field = constellationReferenceField(
    egoRequestCount: _revokedEgoRequests,
    anchors: [_pinnedAnchor()],
  );
  await harness.store.requestRefresh(ConstellationRefreshReason.load);
  await _settleFrames(tester);
  expect(
    harness.store.current.field!.requests.map((r) => r.id),
    isNot(contains(_heldRequest.id)),
    reason: 'the revocation must have reached the store',
  );
}

/// An outbox write for a node other than the held one.
void _placeOtherPerson(_Harness harness) {
  harness.placement.place(
    parent: _otherPerson,
    position: _otherPlacedAt,
    companions: const [],
  );
  expect(harness.placement.current.targets, contains(_otherPerson));
}

/// Sends the tab-hidden lifecycle change through the binding, the way the
/// browser's visibility change reaches the app.
void _hideTab(WidgetTester tester) {
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
}

/// Hides the tab and brings it back at once. A hidden view schedules no
/// frames, so a transition could not be watched while the tab stays hidden.
void _hideTabAndReturn(WidgetTester tester) {
  _hideTab(tester);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Set<String> _nodeIds(ConstellationCubit cubit) =>
    cubit.graphController.renderSnapshot.topology.nodesById.keys.toSet();

Map<String, Offset?> _displayed(ConstellationCubit cubit) => {
  for (final id in _nodeIds(cubit))
    id: cubit.graphController.getPositionOrNullForId(id),
};

/// Everything displayed except the scene node [nodeId] (the held one).
Map<String, Offset?> _displayedWithout(
  ConstellationCubit cubit,
  String nodeId,
) => _displayed(cubit)..remove(nodeId);

void _expectLaidOut(Map<String, Offset?> positions) {
  expect(
    positions.values.whereType<Offset>().length,
    greaterThanOrEqualTo(3),
    reason:
        'the scene must have laid-out nodes for the comparison to mean '
        'anything',
  );
}

void _expectSamePositions(
  Map<String, Offset?> actual,
  Map<String, Offset?> expected, {
  String? reason,
}) {
  for (final entry in expected.entries) {
    final got = actual[entry.key];
    final want = entry.value;
    if (want == null || got == null) {
      expect(got, want, reason: '${entry.key}: $reason');
    } else {
      expect(got.dx, closeTo(want.dx, 0.5), reason: '${entry.key}: $reason');
      expect(got.dy, closeTo(want.dy, 0.5), reason: '${entry.key}: $reason');
    }
  }
}

/// Runs [release] and checks that what follows is one transition: the first
/// frame still shows [frozen] (no jump), and from then on every node that
/// moves travels to its destination without ever turning back. Returns the
/// settled positions.
Future<Map<String, Offset?>> _expectOneTransitionAfter(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required Map<String, Offset?> frozen,
  required Future<void> Function() release,
}) async {
  await release();
  // Zero elapsed time: the first frame after the release still shows the
  // frozen geometry, so the transition starts from it without a jump.
  await tester.pump();
  _expectSamePositions(
    _displayed(cubit),
    frozen,
    reason: 'the release must not jump the displayed nodes',
  );
  final trace = <Map<String, Offset?>>[];
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    trace.add(_displayed(cubit));
  }
  await _settleFrames(tester);

  final settled = _displayed(cubit);
  var movedNodes = 0;
  for (final id in frozen.keys) {
    final end = settled[id];
    final start = frozen[id];
    if (end == null || start == null || (end - start).distance < 5) {
      continue;
    }
    movedNodes++;
    var previous = double.infinity;
    for (final frame in trace) {
      final at = frame[id];
      if (at == null) continue;
      final distance = (end - at).distance;
      expect(
        distance,
        lessThanOrEqualTo(previous + 0.5),
        reason: '$id must travel to its destination in one transition',
      );
      previous = distance;
    }
  }
  expect(movedNodes, greaterThan(0), reason: 'the scene must relayout');
  return settled;
}

bool _hasWriteFor(_Harness harness, ConstellationAnchorTarget target) =>
    _writesFor(harness, target) > 0;

/// How many placement operations the server was sent for [target], however
/// they were batched.
int _writesFor(_Harness harness, ConstellationAnchorTarget target) => harness
    .server
    .applyCalls
    .expand((ops) => ops)
    .where((op) => op.target == target)
    .length;

/// The positions the scene settles on when the store refresh of
/// [_refreshStoreWithMoreRequests] is applied at once, with no drag at all.
/// The scene is unmounted afterwards so another can be mounted.
Future<Map<String, Offset?>> _settledAfterRefreshWithoutDrag(
  WidgetTester tester,
) async {
  final harness = await _mount(tester);
  await _refreshStoreWithMoreRequests(tester, harness);
  await _settleFrames(tester);
  final settled = _displayed(harness.cubit);
  await tester.pumpWidget(const SizedBox.shrink());
  return settled;
}

/// Mounts the scene with a layout transition in flight.
Future<_Harness> _mountWithTransitionInFlight(WidgetTester tester) async {
  final harness = await _mount(tester);
  harness.cubit.requestConstellationLayoutForTest(
    algorithm: _CountingAlgorithm(shiftPerRequest: 0),
  );
  tester.binding.scheduleFrame();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  final before = _displayed(harness.cubit);
  await tester.pump(const Duration(milliseconds: 16));
  expect(
    _displayed(harness.cubit),
    isNot(equals(before)),
    reason: 'a transition must be in flight when the drag begins',
  );
  return harness;
}

/// Picks the request [_heldRequest] up with a real pointer.
Future<TestGesture> _pickUpHeldRequest(WidgetTester tester, _Harness h) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_nodeFinder(_heldRequest)),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(40, 30));
  await tester.pump();
  await gesture.moveBy(const Offset(40, 30));
  await tester.pump();
  expect(
    h.cubit.state.placementPhase,
    isNot(ConstellationPlacementPhase.idle),
    reason: 'the pointer must have picked the request up',
  );
  return gesture;
}

void main() {
  // A lost pointer capture reaches the scene as a pointer cancel (the browser's
  // pointercancel, or the gesture arena dropping the pointer) or as the view
  // going away under the pointer, so both are driven through the real gesture
  // layer; a pointer that is merely released anywhere is a drop.
  group('Inputs arriving while a node is held are applied on release only', () {
    testWidgets(
      'a store refresh mid-drag composes and lays out nothing until release, '
      'then the added requests appear in one compose, layout and transition',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        final held = _nodeIds(cubit);
        harness.counters.reset();

        await _refreshStoreWithMoreRequests(tester, harness);

        expect(harness.counters.composes, 0);
        expect(harness.counters.algorithmRuns, 0);
        expect(
          _nodeIds(cubit),
          held,
          reason: 'the scene must not change under the pointer',
        );
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);

        await _expectOneTransitionAfter(
          tester,
          cubit,
          frozen: frozen,
          release: gesture.cancel,
        );

        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
        expect(
          _nodeIds(cubit),
          containsAll(['fr:req-ego-4', 'fr:req-ego-5']),
          reason: 'the held refresh must be applied on release',
        );
      },
    );

    testWidgets(
      'an outbox write for another node mid-drag composes nothing until '
      'release, then the scene catches up in one compose, layout and '
      'transition',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        final held = _nodeIds(cubit);
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);
        harness.counters.reset();

        _placeOtherPerson(harness);
        await _settleFrames(tester);

        expect(harness.counters.composes, 0);
        expect(harness.counters.algorithmRuns, 0);
        expect(_nodeIds(cubit), held);
        _expectSamePositions(
          _displayedWithout(cubit, _freeNodeId),
          frozen,
          reason: 'outbox activity must not move the scene under the pointer',
        );

        await _expectOneTransitionAfter(
          tester,
          cubit,
          frozen: frozen,
          release: gesture.cancel,
        );

        expect(
          harness.counters.composes,
          1,
          reason: 'the held outbox change must be applied on release',
        );
        expect(
          harness.counters.algorithmRuns,
          1,
          reason: 'the held outbox change must be laid out once on release',
        );
        expect(
          _hasWriteFor(harness, _freePerson),
          isFalse,
          reason: 'a cancel must not write the held node',
        );
      },
    );
  });

  group('Dropping a held node', () {
    testWidgets(
      'one compose, one layout and one transition apply a store refresh and '
      'an outbox write that arrived mid-drag together with the placement',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);
        _placeOtherPerson(harness);
        await _settleFrames(tester);
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);
        expect(
          harness.counters.composes,
          0,
          reason: 'neither input may reach the scene while it is held',
        );

        await _expectOneTransitionAfter(
          tester,
          cubit,
          frozen: frozen,
          release: gesture.up,
        );

        expect(harness.counters.composes, 1, reason: 'one combined compose');
        expect(harness.counters.algorithmRuns, 1, reason: 'one layout');
        expect(
          _nodeIds(cubit),
          contains('fr:req-ego-5'),
          reason: 'the refresh must be applied by the same compose',
        );
        expect(
          harness.placement.current.targets.keys,
          containsAll([_freePerson, _otherPerson]),
          reason: 'the placement must reach the outbox on the drop',
        );
        // The other node's write is still in flight and the outbox sends one
        // batch at a time, so the drop waits behind it.
        expect(
          harness.placement.current.targets[_freePerson]?.latestPending,
          isNotNull,
        );
      },
    );

    testWidgets(
      'a store refresh alone, held mid-drag, is applied by the drop in one '
      'compose, layout and transition together with the placement',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        final held = _nodeIds(cubit);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);
        expect(harness.counters.composes, 0);
        expect(harness.counters.algorithmRuns, 0);
        expect(_nodeIds(cubit), held);
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);

        await _expectOneTransitionAfter(
          tester,
          cubit,
          frozen: frozen,
          release: gesture.up,
        );

        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
        expect(
          _nodeIds(cubit),
          containsAll(['fr:req-ego-4', 'fr:req-ego-5']),
          reason: 'the held refresh must be applied on the drop',
        );
        expect(harness.placement.current.targets, contains(_freePerson));
        expect(_writesFor(harness, _freePerson), 1);
      },
    );

    testWidgets(
      'with no other input changed, a drop is one compose, one layout and '
      'one transition',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);
        harness.counters.reset();

        await _expectOneTransitionAfter(
          tester,
          cubit,
          frozen: frozen,
          release: gesture.up,
        );

        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
        expect(harness.placement.current.targets, contains(_freePerson));
        expect(_writesFor(harness, _freePerson), 1);
      },
    );
  });

  group('Cancelling a held node', () {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets(
        'losing the ${kind.name} pointer capture writes nothing and applies '
        'the held inputs in one transition to the layout an undisturbed '
        'refresh would give',
        (tester) async {
          final undisturbed = await _settledAfterRefreshWithoutDrag(tester);
          final harness = await _mount(tester);
          final cubit = harness.cubit;
          final gesture = await _pickUpFreePerson(
            tester,
            harness,
            kind: kind,
          );
          harness.counters.reset();
          await _refreshStoreWithMoreRequests(tester, harness);
          expect(
            harness.counters.composes,
            0,
            reason: 'the held input must wait for the release',
          );
          final frozen = _displayedWithout(cubit, _freeNodeId);
          _expectLaidOut(frozen);

          final settled = await _expectOneTransitionAfter(
            tester,
            cubit,
            frozen: frozen,
            release: gesture.cancel,
          );

          expect(harness.server.applyCalls, isEmpty);
          expect(
            harness.placement.current.targets,
            isNot(contains(_freePerson)),
          );
          expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
          expect(harness.counters.composes, 1);
          expect(harness.counters.algorithmRuns, 1);
          _expectSamePositions(
            settled,
            undisturbed,
            reason: 'the cluster must come back to where it would have been',
          );
        },
      );
    }

    testWidgets(
      'the graph view going away under the pointer releases the held node '
      'once, writes nothing and applies the held inputs in one compose',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);
        expect(
          harness.counters.composes,
          0,
          reason: 'the held input must wait for the release',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await _settleFrames(tester);

        expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
        expect(cubit.state.activePlacementTarget, isNull);
        expect(harness.counters.composes, 1);
        expect(harness.server.applyCalls, isEmpty);
        expect(harness.placement.current.targets, isNot(contains(_freePerson)));

        await gesture.up();
        await _settleFrames(tester);

        expect(
          harness.counters.composes,
          1,
          reason: 'the pointer ending late must not release again',
        );
        expect(harness.server.applyCalls, isEmpty);
      },
    );

    testWidgets(
      'with nothing changed meanwhile, a cancel composes and lays out nothing '
      'and the node animates back to where it was picked up',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final committed = cubit.graphController.getPositionOrNullForId(
          _freeNodeId,
        )!;
        final gesture = await _pickUpFreePerson(tester, harness);
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);
        harness.counters.reset();

        await gesture.cancel();
        await _settleFrames(tester);

        expect(harness.counters.composes, 0, reason: 'no compose');
        expect(harness.counters.algorithmRuns, 0, reason: 'no layout');
        _expectSamePositions(_displayedWithout(cubit, _freeNodeId), frozen);
        _expectSamePositions(
          {
            _freeNodeId: cubit.graphController.getPositionOrNullForId(
              _freeNodeId,
            ),
          },
          {_freeNodeId: committed},
          reason: 'the held node must come back to its committed place',
        );
        expect(harness.server.applyCalls, isEmpty);
      },
    );

    testWidgets(
      'with unchanged inputs the scene resumes where it stopped and ends '
      'where an undisturbed run ends, without composing or laying out again',
      (tester) async {
        final undisturbedHarness = await _mountWithTransitionInFlight(tester);
        await _settleFrames(tester);
        final undisturbed = _displayed(undisturbedHarness.cubit);
        await tester.pumpWidget(const SizedBox.shrink());

        final harness = await _mountWithTransitionInFlight(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);
        harness.counters.reset();

        await gesture.cancel();
        await tester.pump();

        _expectSamePositions(
          _displayedWithout(cubit, _freeNodeId),
          frozen,
          reason: 'resuming must not count the time spent paused',
        );
        await _settleFrames(tester);

        expect(harness.counters.algorithmRuns, 0, reason: 'no layout');
        expect(harness.counters.composes, 0, reason: 'no compose');
        expect(
          _displayedWithout(cubit, _freeNodeId),
          isNot(frozen),
          reason: 'the paused transition must continue',
        );
        _expectSamePositions(
          _displayed(cubit),
          undisturbed,
          reason: 'the paused transition must continue to its destination',
        );
        final ended = _displayed(cubit);
        await tester.pump(const Duration(milliseconds: 400));
        _expectSamePositions(
          _displayed(cubit),
          ended,
          reason: 'the resumed transition must have finished',
        );
        expect(harness.server.applyCalls, isEmpty);
      },
    );
  });

  group('The browser tab being hidden during a drag', () {
    testWidgets(
      'behaves as a cancel: nothing is written and the held inputs apply in '
      'one transition',
      (tester) async {
        final undisturbed = await _settledAfterRefreshWithoutDrag(tester);
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);
        expect(
          harness.counters.composes,
          0,
          reason: 'the held input must wait for the release',
        );
        final frozen = _displayedWithout(cubit, _freeNodeId);
        _expectLaidOut(frozen);

        final settled = await _expectOneTransitionAfter(
          tester,
          cubit,
          frozen: frozen,
          release: () async => _hideTabAndReturn(tester),
        );

        expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
        expect(cubit.state.activePlacementTarget, isNull);
        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
        _expectSamePositions(settled, undisturbed);

        // The pointer coming back up after the tab returns is a late end of a
        // drag that no longer exists.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await gesture.up();
        await _settleFrames(tester);

        expect(harness.server.applyCalls, isEmpty);
        expect(harness.placement.current.targets, isNot(contains(_freePerson)));
        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
      },
    );

    testWidgets(
      'with nothing changed meanwhile composes and lays out nothing and the '
      'node comes back to where it was picked up',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final committed = cubit.graphController.getPositionOrNullForId(
          _freeNodeId,
        )!;
        final gesture = await _pickUpFreePerson(tester, harness);
        final frozen = _displayedWithout(cubit, _freeNodeId);
        harness.counters.reset();

        _hideTab(tester);
        await _settleFrames(tester);

        expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
        expect(harness.counters.composes, 0);
        expect(harness.counters.algorithmRuns, 0);
        _expectSamePositions(_displayedWithout(cubit, _freeNodeId), frozen);
        _expectSamePositions(
          {
            _freeNodeId: cubit.graphController.getPositionOrNullForId(
              _freeNodeId,
            ),
          },
          {_freeNodeId: committed},
          reason: 'the held node must come back to its committed place',
        );
        expect(harness.server.applyCalls, isEmpty);
        await gesture.up();
      },
    );
  });

  group('Each way a drag can end releases the scene exactly once', () {
    testWidgets(
      'a tab hidden after a drop neither undoes the drop nor lays out again',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);

        await gesture.up();
        await _settleFrames(tester);
        final afterDrop = (
          composes: harness.counters.composes,
          runs: harness.counters.algorithmRuns,
          positions: _displayed(cubit),
        );

        _hideTab(tester);
        await _settleFrames(tester);

        expect(afterDrop.composes, 1);
        expect(afterDrop.runs, 1);
        expect(harness.counters.composes, afterDrop.composes);
        expect(harness.counters.algorithmRuns, afterDrop.runs);
        _expectSamePositions(_displayed(cubit), afterDrop.positions);
        expect(harness.placement.current.targets, contains(_freePerson));
        expect(
          _writesFor(harness, _freePerson),
          1,
          reason: 'the drop must be written once',
        );
      },
    );

    testWidgets(
      'a pointer cancel followed by a tab hidden releases once and writes '
      'nothing',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);
        expect(
          harness.counters.composes,
          0,
          reason: 'the held input must wait for the release',
        );

        await gesture.cancel();
        await _settleFrames(tester);
        final afterCancel = _displayed(cubit);
        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);

        _hideTab(tester);
        await _settleFrames(tester);

        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
        _expectSamePositions(_displayed(cubit), afterCancel);
        expect(harness.server.applyCalls, isEmpty);
        expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
      },
    );

    testWidgets(
      'a tab hidden followed by the pointer being cancelled releases once '
      'and writes nothing',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);

        _hideTab(tester);
        await _settleFrames(tester);
        final afterHidden = _displayed(cubit);
        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);

        await gesture.cancel();
        await _settleFrames(tester);

        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
        _expectSamePositions(_displayed(cubit), afterHidden);
        expect(harness.server.applyCalls, isEmpty);
        expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
      },
    );

    testWidgets(
      'a tab hidden followed by the pointer coming up is not a drop',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();
        await _refreshStoreWithMoreRequests(tester, harness);

        _hideTab(tester);
        await _settleFrames(tester);
        final afterHidden = _displayed(cubit);

        await gesture.up();
        await _settleFrames(tester);

        expect(harness.counters.composes, 1);
        expect(harness.counters.algorithmRuns, 1);
        _expectSamePositions(_displayed(cubit), afterHidden);
        expect(_hasWriteFor(harness, _freePerson), isFalse);
        expect(
          harness.placement.current.targets,
          isNot(contains(_freePerson)),
        );
        expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
      },
    );

    testWidgets(
      'a drop followed by a tab hidden leaves the written placement alone',
      (tester) async {
        final harness = await _mount(tester);
        final cubit = harness.cubit;
        final gesture = await _pickUpFreePerson(tester, harness);
        harness.counters.reset();

        await gesture.up();
        await _settleFrames(tester);
        final writesAfterDrop = _writesFor(harness, _freePerson);
        final runsAfterDrop = harness.counters.algorithmRuns;
        final composesAfterDrop = harness.counters.composes;

        _hideTab(tester);
        await _settleFrames(tester);

        expect(writesAfterDrop, 1);
        expect(_writesFor(harness, _freePerson), writesAfterDrop);
        expect(harness.counters.algorithmRuns, runsAfterDrop);
        expect(harness.counters.composes, composesAfterDrop);
        expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
        expect(harness.placement.current.targets, contains(_freePerson));
      },
    );
  });

  group('A node becoming invisible to the viewer during its own drag', () {
    final releases =
        <
          ({
            String name,
            Future<void> Function(WidgetTester, TestGesture) release,
          })
        >[
          (
            name: 'a pointer cancel',
            release: (tester, gesture) => gesture.cancel(),
          ),
          (name: 'a drop', release: (tester, gesture) => gesture.up()),
          (
            name: 'a tab hidden',
            release: (tester, gesture) async => _hideTabAndReturn(tester),
          ),
        ];

    for (final path in releases) {
      testWidgets(
        'stays in the scene while it is held and leaves it, in one compose, '
        'layout and transition, without being written, when the drag ends '
        'with ${path.name}',
        (tester) async {
          final harness = await _mount(tester);
          final cubit = harness.cubit;
          final gesture = await _pickUpHeldRequest(tester, harness);
          final held = _nodeIds(cubit);
          expect(held, contains(_heldRequestNodeId));
          harness.counters.reset();

          await _refreshStoreRevokingHeldRequest(tester, harness);

          expect(
            _nodeIds(cubit),
            held,
            reason: 'the scene must not change under the pointer',
          );
          expect(harness.counters.composes, 0);
          expect(harness.counters.algorithmRuns, 0);
          final frozen = _displayedWithout(cubit, _heldRequestNodeId);
          _expectLaidOut(frozen);

          await _expectOneTransitionAfter(
            tester,
            cubit,
            frozen: frozen,
            release: () => path.release(tester, gesture),
          );

          expect(
            _nodeIds(cubit),
            isNot(contains(_heldRequestNodeId)),
            reason: 'the revoked request must be applied on release',
          );
          expect(cubit.state.placementPhase, ConstellationPlacementPhase.idle);
          expect(harness.counters.composes, 1);
          expect(harness.counters.algorithmRuns, 1);
          expect(
            _hasWriteFor(harness, _heldRequest),
            isFalse,
            reason: 'a request the viewer can no longer see must not be sent',
          );
          expect(
            harness.placement.current.targets,
            isNot(contains(_heldRequest)),
            reason: 'a revoked request must not reach the outbox',
          );
        },
      );
    }
  });
}
