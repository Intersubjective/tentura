import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/placement_outbox.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_placement_marker.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

// The constellation shows a "Not saved" marker on a node whose placement the
// server rejected or whose outcome stayed unknown after the automatic retries,
// and the marker's Retry and Discard act on the account's placement outbox.
// Discarding hands the node back to its confirmed position by animation.

final _pinnedPerson = ConstellationAnchorTarget.person('am');
const _dropCentre = Offset(240, 180);
const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.2,
  yUnits: 0.3,
  coordinateSpaceVersion: 1,
);
const _maxBackoff = Duration(seconds: 30);

late Map<String, dynamic> _en;

String _text(String key) => _en[key] as String;

/// The exact copy for [key], rendered inside the marker badge itself.
Finder _inBadge(String key) => find.descendant(
  of: find.byType(ConstellationPlacementMarker),
  matching: find.text(_text(key)),
);

ConstellationAnchor _anchor(
  ConstellationAnchorPosition position,
  int revision,
) => ConstellationAnchor(
  target: _pinnedPerson,
  position: position,
  revision: ConstellationAnchorRevision(BigInt.from(revision)),
  placedAt: DateTime.utc(2026, 9, 9),
);

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

/// Holds every apply until the test rejects it or fails the transport.
final class _AnchorRepository implements ConstellationWriteFake {
  @override
  Future<ConstellationAnchorResetResult> reset({required String clientOpId}) =>
      throw UnimplementedError('reset is not used by this test');

  _AnchorRepository(this._confirmed);

  final ConstellationAnchorProjection _confirmed;
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

  void reject(int index) {
    final call = calls[index];
    call.reply.complete(
      ConstellationAnchorApplyResult(
        beforeRevision: _confirmed.revision,
        afterRevision: _confirmed.revision,
        results: [
          for (final op in call.ops)
            ConstellationAnchorOpResult(
              clientOpId: op.clientOpId,
              status: ConstellationAnchorOpStatus.rejected,
              reason: 'target_unavailable',
            ),
        ],
      ),
    );
  }

  void failTransport(int index) => calls[index].reply.completeError(
    TimeoutException('apply timed out'),
  );

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

typedef _Harness = ({
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  _AnchorRepository server,
  FakeWakeUpPort retries,
  FakeClockPort clock,
  Offset confirmedAt,
});

Future<_Harness> _mount(WidgetTester tester) async {
  final field = constellationReferenceField(anchors: [_anchor(_pinnedAt, 1)]);
  final server = _AnchorRepository(field.resolvedAnchorProjection);
  final retries = FakeWakeUpPort();
  final clock = FakeClockPort();
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final store = ConstellationStoreFixture(
    _FieldRepository(field),
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    server,
    store,
    clock,
    retries,
    realtime: sync.case_,
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationPlacementMarkerBodyTest'),
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
    size: const Size(800, 700),
    locale: const Locale('en'),
  );
  final confirmedAt = cubit.graphController.getPositionOrNullForId('fp:am')!;
  return (
    cubit: cubit,
    placement: placement,
    server: server,
    retries: retries,
    clock: clock,
    confirmedAt: confirmedAt,
  );
}

Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _dropPinnedPerson(WidgetTester tester, _Harness harness) async {
  harness.cubit
    ..beginDragExisting(target: _pinnedPerson)
    ..updateDragPresentation(nodeId: 'fp:am', sceneCentre: _dropCentre);
  await harness.cubit.onExistingNodeDrop(
    target: _pinnedPerson,
    sceneCentre: _dropCentre,
  );
  await _settleFrames(tester);
}

Future<void> _rejectDrop(WidgetTester tester, _Harness harness) async {
  await _dropPinnedPerson(tester, harness);
  harness.server.reject(0);
  await _settleFrames(tester);
}

/// Lets the transport fail until the outbox gives up retrying by itself.
Future<void> _exhaustAutomaticRetries(
  WidgetTester tester,
  _Harness harness,
) async {
  await _dropPinnedPerson(tester, harness);
  harness.server.failTransport(0);
  await _settleFrames(tester);
  for (var call = 1; call < 3; call++) {
    harness.retries.elapse(_maxBackoff * 2);
    await _settleFrames(tester);
    expect(harness.server.calls, hasLength(call + 1));
    harness.server.failTransport(call);
    await _settleFrames(tester);
  }
  harness.retries.elapse(_maxBackoff * 2);
  await _settleFrames(tester);
  expect(harness.server.calls, hasLength(3), reason: 'no fourth attempt');
  expect(
    harness.placement.current.targets[_pinnedPerson]!.inFlight!.status,
    PlacementSlotStatus.commitUnknown,
  );
}

Future<void> _chooseFromMarker(WidgetTester tester, String key) async {
  await tester.tap(find.byType(ConstellationPlacementMarker));
  await _settleFrames(tester);
  await tester.tap(find.text(_text(key)));
  await _settleFrames(tester);
}

double _distance(Offset a, Offset b) => (a - b).distance;

/// Lets wall-clock time pass for both the widget tree and the injected clock.
Future<void> _elapse(
  WidgetTester tester,
  _Harness harness,
  Duration duration,
) async {
  harness.clock.advance(duration);
  await tester.pump(duration);
}

/// Pumps in small steps so no assertion depends on an exact frame count.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
    await tester.pump(step);
  }
}

Future<void> _dropWithoutSettling(WidgetTester tester, _Harness harness) async {
  harness.cubit
    ..beginDragExisting(target: _pinnedPerson)
    ..updateDragPresentation(nodeId: 'fp:am', sceneCentre: _dropCentre);
  await harness.cubit.onExistingNodeDrop(
    target: _pinnedPerson,
    sceneCentre: _dropCentre,
  );
  await tester.pump();
}

ConstellationAnchorApplyResult _acknowledged(
  _Harness harness,
  ({
    List<ConstellationAnchorApplyOp> ops,
    Completer<ConstellationAnchorApplyResult> reply,
  })
  call,
) => ConstellationAnchorApplyResult(
  beforeRevision: ConstellationAnchorRevision(BigInt.one),
  afterRevision: ConstellationAnchorRevision(BigInt.two),
  results: [
    ConstellationAnchorOpResult(
      clientOpId: call.ops.single.clientOpId,
      status: ConstellationAnchorOpStatus.ok,
      resultingTargetRevision: ConstellationAnchorRevision(BigInt.two),
      target: call.ops.single.target,
      anchor: _anchor(call.ops.single.position!, 2),
    ),
  ],
);

void main() {
  setUpAll(() {
    _en =
        jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
  });

  group('Placement marker on the constellation map', () {
    testWidgets('no marker is shown while every placement is saved', (
      tester,
    ) async {
      await _mount(tester);

      expect(find.byType(ConstellationPlacementMarker), findsNothing);
    });

    testWidgets('a write that is still in flight shows no not-saved marker', (
      tester,
    ) async {
      final harness = await _mount(tester);

      await _dropPinnedPerson(tester, harness);

      expect(harness.server.calls, hasLength(1));
      expect(find.byType(ConstellationPlacementMarker), findsNothing);
      expect(
        find.textContaining(_text('constellationPlacementNotSaved')),
        findsNothing,
      );
    });

    testWidgets('a write in flight for over a second shows the saving cue', (
      tester,
    ) async {
      final harness = await _mount(tester);

      await _dropWithoutSettling(tester, harness);
      await _elapse(tester, harness, const Duration(milliseconds: 500));

      expect(harness.server.calls, hasLength(1));
      expect(
        find.textContaining(_text('constellationPlacementSaving')),
        findsNothing,
        reason: 'a quick save stays unannounced',
      );

      await _elapse(tester, harness, const Duration(milliseconds: 700));

      expect(find.byType(ConstellationPlacementMarker), findsOneWidget);
      expect(_inBadge('constellationPlacementSaving'), findsOneWidget);
      expect(
        find.textContaining(_text('constellationPlacementNotSaved')),
        findsNothing,
      );
    });

    testWidgets('the saving cue goes away once the write is acknowledged', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _dropWithoutSettling(tester, harness);
      await _elapse(tester, harness, const Duration(milliseconds: 1500));
      expect(find.byType(ConstellationPlacementMarker), findsOneWidget);

      final call = harness.server.calls.single;
      call.reply.complete(_acknowledged(harness, call));
      await _settleFrames(tester);

      expect(find.byType(ConstellationPlacementMarker), findsNothing);
    });

    testWidgets('a rejected placement is marked as not saved', (tester) async {
      final harness = await _mount(tester);

      await _rejectDrop(tester, harness);

      expect(find.byType(ConstellationPlacementMarker), findsOneWidget);
      expect(_inBadge('constellationPlacementNotSaved'), findsOneWidget);
      expect(
        _distance(
          harness.cubit.graphController.getPositionOrNullForId('fp:am')!,
          harness.confirmedAt,
        ),
        greaterThan(5),
        reason: 'the node stays where the user put it',
      );
    });

    testWidgets('an unknown outcome is not marked while retries remain', (
      tester,
    ) async {
      final harness = await _mount(tester);

      await _dropPinnedPerson(tester, harness);
      harness.server.failTransport(0);
      await _settleFrames(tester);

      expect(
        harness.placement.current.targets[_pinnedPerson]!.inFlight!.attempts,
        1,
      );
      expect(
        find.textContaining(_text('constellationPlacementNotSaved')),
        findsNothing,
      );
    });

    testWidgets('an unknown outcome is marked once automatic retries run out', (
      tester,
    ) async {
      final harness = await _mount(tester);

      await _exhaustAutomaticRetries(tester, harness);

      expect(find.byType(ConstellationPlacementMarker), findsOneWidget);
      expect(_inBadge('constellationPlacementNotSaved'), findsOneWidget);
    });
  });

  group('Retry from the placement marker', () {
    testWidgets('a rejected placement is resent as a new write', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _rejectDrop(tester, harness);
      final rejected = harness.server.calls.single.ops.single;

      await _chooseFromMarker(tester, 'constellationPlacementRetry');

      expect(harness.server.calls, hasLength(2));
      final resent = harness.server.calls[1].ops.single;
      expect(resent.target, _pinnedPerson);
      expect(resent.position, rejected.position);
      expect(resent.clientOpId, isNot(rejected.clientOpId));
    });

    testWidgets('an exhausted unknown write is replayed under its own id', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _exhaustAutomaticRetries(tester, harness);
      final original = harness.server.calls.first.ops.single;

      await _chooseFromMarker(tester, 'constellationPlacementRetry');

      expect(harness.server.calls, hasLength(4));
      final replay = harness.server.calls[3].ops.single;
      expect(replay.clientOpId, original.clientOpId);
      expect(replay.position, original.position);
    });

    testWidgets('the marker goes away once the retry is acknowledged', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _rejectDrop(tester, harness);
      await _chooseFromMarker(tester, 'constellationPlacementRetry');
      expect(harness.server.calls, hasLength(2));

      final call = harness.server.calls[1];
      call.reply.complete(_acknowledged(harness, call));
      await _settleFrames(tester);

      expect(find.byType(ConstellationPlacementMarker), findsNothing);
    });
  });

  group('Discard from the placement marker', () {
    testWidgets('a rejected placement is dropped from the outbox', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _rejectDrop(tester, harness);

      await _chooseFromMarker(tester, 'constellationPlacementDiscard');

      expect(harness.placement.current.targets, isEmpty);
      expect(harness.server.calls, hasLength(1), reason: 'nothing is resent');
      expect(find.byType(ConstellationPlacementMarker), findsNothing);
    });

    testWidgets(
      'a rejected placement animates back to its confirmed position',
      (
        tester,
      ) async {
        final harness = await _mount(tester);
        await _rejectDrop(tester, harness);
        final controller = harness.cubit.graphController;
        final droppedAt = controller.getPositionOrNullForId('fp:am')!;
        expect(_distance(droppedAt, harness.confirmedAt), greaterThan(5));

        await tester.tap(find.byType(ConstellationPlacementMarker));
        await _settleFrames(tester);
        await tester.tap(find.text(_text('constellationPlacementDiscard')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final midway = controller.getPositionOrNullForId('fp:am')!;
        expect(
          _distance(midway, droppedAt),
          greaterThan(1),
          reason: 'the node has started to move from where it was dropped',
        );
        expect(
          _distance(midway, harness.confirmedAt),
          greaterThan(1),
          reason: 'the node has not jumped to the confirmed position',
        );

        await _pumpFor(tester, const Duration(seconds: 3));

        expect(
          _distance(
            controller.getPositionOrNullForId('fp:am')!,
            harness.confirmedAt,
          ),
          lessThan(1.5),
        );
      },
    );

    testWidgets('an exhausted unknown write is replayed under its own id', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _exhaustAutomaticRetries(tester, harness);
      final original = harness.server.calls.first.ops.single;

      await _chooseFromMarker(tester, 'constellationPlacementDiscard');

      expect(harness.server.calls, hasLength(4));
      final replay = harness.server.calls[3].ops.single;
      expect(replay.clientOpId, original.clientOpId);
      expect(replay.position, original.position);
      expect(
        find.textContaining(_text('constellationPlacementNotSaved')),
        findsNothing,
        reason: 'the discard is accepted, so the marker is gone',
      );
    });

    testWidgets('a replay that is rejected leaves nothing to undo', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _exhaustAutomaticRetries(tester, harness);
      await _chooseFromMarker(tester, 'constellationPlacementDiscard');

      harness.server.reject(3);
      await _settleFrames(tester);

      expect(harness.placement.current.targets, isEmpty);
      expect(harness.server.calls, hasLength(4), reason: 'no further write');
      expect(find.byType(ConstellationPlacementMarker), findsNothing);
    });

    testWidgets('a replay that was applied is undone by a compensating write', (
      tester,
    ) async {
      final harness = await _mount(tester);
      await _exhaustAutomaticRetries(tester, harness);
      final controller = harness.cubit.graphController;
      final droppedAt = controller.getPositionOrNullForId('fp:am')!;
      expect(_distance(droppedAt, harness.confirmedAt), greaterThan(5));
      await _chooseFromMarker(tester, 'constellationPlacementDiscard');
      final replay = harness.server.calls[3];
      replay.reply.complete(_acknowledged(harness, replay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final midway = controller.getPositionOrNullForId('fp:am')!;
      expect(
        _distance(midway, droppedAt),
        greaterThan(1),
        reason: 'the node has started to move from where it was dropped',
      );
      expect(
        _distance(midway, harness.confirmedAt),
        greaterThan(1),
        reason: 'the node has not jumped to the confirmed position',
      );

      await _pumpFor(tester, const Duration(seconds: 3));

      expect(harness.server.calls, hasLength(5));
      final undo = harness.server.calls[4].ops.single;
      expect(undo.target, _pinnedPerson);
      expect(undo.position, _pinnedAt, reason: 'back to the confirmed spot');
      expect(undo.clientOpId, isNot(replay.ops.single.clientOpId));
      expect(
        find.textContaining(_text('constellationPlacementNotSaved')),
        findsNothing,
      );
      expect(
        _distance(
          controller.getPositionOrNullForId('fp:am')!,
          harness.confirmedAt,
        ),
        lessThan(1.5),
        reason: 'the node ends on its confirmed position',
      );
    });

    testWidgets(
      'a discarded unknown write whose replay is rejected animates back to '
      'its confirmed position',
      (tester) async {
        final harness = await _mount(tester);
        await _exhaustAutomaticRetries(tester, harness);
        final controller = harness.cubit.graphController;
        final droppedAt = controller.getPositionOrNullForId('fp:am')!;
        expect(_distance(droppedAt, harness.confirmedAt), greaterThan(5));
        await _chooseFromMarker(tester, 'constellationPlacementDiscard');

        harness.server.reject(3);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        final midway = controller.getPositionOrNullForId('fp:am')!;
        expect(
          _distance(midway, droppedAt),
          greaterThan(1),
          reason: 'the node has started to move from where it was dropped',
        );
        expect(
          _distance(midway, harness.confirmedAt),
          greaterThan(1),
          reason: 'the node has not jumped to the confirmed position',
        );

        await _pumpFor(tester, const Duration(seconds: 3));

        expect(
          _distance(
            controller.getPositionOrNullForId('fp:am')!,
            harness.confirmedAt,
          ),
          lessThan(1.5),
        );
      },
    );
  });
}
