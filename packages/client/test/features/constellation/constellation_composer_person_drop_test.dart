// While composing, the viewer may drag people onto the circle (or anywhere)
// instead of moving the circle over them. A dropped person stays where it was
// dropped for the rest of the session; nothing is written while composing.
// Once the Post or Request is sent, everyone returns to their place except a
// person who had no pin and was dropped inside the circle: they get a pin at
// the drop, so their node stays put. A cancelled session writes nothing.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/util/layout_geometry_adapters.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_composer_screen_harness.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';

const _pinnedAt = ConstellationAnchorPosition(
  xUnits: 0.45,
  yUnits: 0.45,
  coordinateSpaceVersion: 1,
);

ConstellationField _field({required bool pinA}) {
  final base = composerHarnessField();
  if (!pinA) return base;
  return base.copyWith(
    anchorProjection: ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.one),
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person('a'),
          position: _pinnedAt,
          revision: ConstellationAnchorRevision(BigInt.one),
          placedAt: DateTime.utc(2026, 10, 9),
        ),
      ],
      pinnedPeers: const [ConstellationPerson(id: 'a')],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

/// A server that records writes and never answers them.
final class _SilentAnchorRepository implements ConstellationWriteFake {
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

  final applyCalls = <List<ConstellationAnchorApplyOp>>[];

  List<ConstellationAnchorApplyOp> get ops => [
    for (final call in applyCalls) ...call,
  ];

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

typedef _Harness = ({
  ConstellationCubit cubit,
  ConstellationComposerCubit composer,
  _SilentAnchorRepository server,
});

/// [peopleLoaded] seeds the composer with its audience, as a harness can;
/// the screen's composer starts with none and loads it when a session opens.
Future<_Harness> _mount(
  WidgetTester tester, {
  required bool pinA,
  bool peopleLoaded = true,
}) async {
  final repository = ComposerHarnessRepository(() => _field(pinA: pinA));
  final server = _SilentAnchorRepository();
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final store = ConstellationStoreFixture(
    repository,
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
    logger: Logger('ConstellationComposerPersonDropTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: composerHarnessEgo,
    forwardCase: buildTestForwardCase(ComposerHarnessForwardRepository()),
  );
  addTearDown(cubit.close);
  if (cubit.state.status is! StateIsSuccess) {
    await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  }
  final composer = buildComposerHarnessComposer(
    peopleSnapshot: cubit.composerPeople,
    eligible: peopleLoaded ? const {'a'} : const {},
  );
  await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);
  await tester.pumpAndSettle();
  return (cubit: cubit, composer: composer, server: server);
}

/// Opens the composer with a small circle away from person `a`.
Future<void> _startComposer(WidgetTester tester, _Harness h) async {
  final controller = h.cubit.graphController;
  final a = controller.getPositionOrNullForId('fp:a')!;
  final ego = controller.getPositionOrNullForId('fp:ego')!;
  // Away from the person and the viewer, inside the canvas.
  final away = a + (a - ego) / (a - ego).distance * 160;
  h.composer.start(BeaconKind.post, away);
  await tester.pumpAndSettle();
  h.composer.setRadius(30);
  await tester.pumpAndSettle();
  expect(h.cubit.state.isComposing, isTrue);
  expect(h.composer.selection.selected, isNot(contains('a')));
}

/// Drags person `a` onto the circle's centre and returns where it lands.
Future<Offset> _dragAOntoCircle(WidgetTester tester, _Harness h) async {
  final controller = h.cubit.graphController;
  final before = controller.getPositionOrNullForId('fp:a')!;
  final target = h.composer.selection.center.offset;
  final viewportDelta =
      controller.sceneToViewportLocal(target) -
      controller.sceneToViewportLocal(before);
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(TestIds.key(TestIds.graphNode('a')))),
    kind: PointerDeviceKind.mouse,
  );
  const steps = 10;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(viewportDelta / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
  return controller.getPositionOrNullForId('fp:a')!;
}

void main() {
  testWidgets(
    'a pinned person stays on its pin when the composer opens before its '
    'people have loaded',
    (tester) async {
      final h = await _mount(tester, pinA: true, peopleLoaded: false);
      final controller = h.cubit.graphController;
      final pin = constellationV1AnchorToPoint(_pinnedAt);
      final pinOffset = Offset(pin.x, pin.y);
      expect(
        (controller.getPositionOrNullForId('fp:a')! - pinOffset).distance,
        lessThan(1),
      );
      final ego = controller.getPositionOrNullForId('fp:ego')!;
      // The first composing pass has no audience yet, so the person leaves
      // the scene and comes back once the composer has loaded its people.
      h.composer.start(
        BeaconKind.post,
        pinOffset + (pinOffset - ego) / (pinOffset - ego).distance * 160,
      );
      await tester.pumpAndSettle();

      expect(h.cubit.state.isComposing, isTrue);
      expect(h.composer.selection.eligible, contains('a'));
      expect(
        (controller.getPositionOrNullForId('fp:a')! - pinOffset).distance,
        lessThan(1),
        reason: 'opening the composer does not move a pinned person',
      );
    },
  );

  testWidgets('a dropped person stays and joins the recipients', (
    tester,
  ) async {
    final h = await _mount(tester, pinA: false);
    await _startComposer(tester, h);

    final dropped = await _dragAOntoCircle(tester, h);
    expect(
      (dropped - h.composer.selection.center.offset).distance,
      lessThan(4),
      reason: 'the person lands on the circle',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(
      h.cubit.graphController.getPositionOrNullForId('fp:a'),
      dropped,
      reason: 'the person does not snap back',
    );
    expect(h.composer.selection.selected, contains('a'));
    expect(h.server.ops, isEmpty, reason: 'nothing is written while composing');
  });

  testWidgets('sending pins an unpinned person dropped inside the circle', (
    tester,
  ) async {
    final h = await _mount(tester, pinA: false);
    await _startComposer(tester, h);
    final dropped = await _dragAOntoCircle(tester, h);
    await tester.pumpAndSettle();

    await h.composer.finish();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(h.cubit.state.isComposing, isFalse);
    final upserts = [
      for (final op in h.server.ops)
        if (op.kind == ConstellationAnchorOpKind.upsert) op,
    ];
    expect(upserts.map((op) => op.target), [
      ConstellationAnchorTarget.person('a'),
    ]);
    final pinned = constellationV1AnchorToPoint(upserts.single.position!);
    expect(
      (Offset(pinned.x, pinned.y) - dropped).distance,
      lessThan(0.5),
      reason: 'the pin is where the person was dropped',
    );
    expect(
      (h.cubit.graphController.getPositionOrNullForId('fp:a')! - dropped)
          .distance,
      lessThan(4),
      reason: 'the newly pinned person keeps its place',
    );
  });

  testWidgets('a cancelled session writes nothing and puts people back', (
    tester,
  ) async {
    final h = await _mount(tester, pinA: false);
    await _startComposer(tester, h);
    final dropped = await _dragAOntoCircle(tester, h);
    await tester.pumpAndSettle();

    await h.composer.cancel();
    await h.composer.finish();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(h.cubit.state.isComposing, isFalse);
    expect(h.server.ops, isEmpty);
    expect(
      (h.cubit.graphController.getPositionOrNullForId('fp:a')! - dropped)
          .distance,
      greaterThan(20),
      reason: 'the person returns to its place',
    );
  });

  testWidgets('a pinned person returns to its pin after sending', (
    tester,
  ) async {
    final h = await _mount(tester, pinA: true);
    final pin = constellationV1AnchorToPoint(_pinnedAt);
    final pinOffset = Offset(pin.x, pin.y);
    expect(
      (h.cubit.graphController.getPositionOrNullForId('fp:a')! - pinOffset)
          .distance,
      lessThan(1),
      reason: 'the person starts at its pin',
    );
    await _startComposer(tester, h);
    final dropped = await _dragAOntoCircle(tester, h);
    await tester.pumpAndSettle();
    expect((dropped - pinOffset).distance, greaterThan(20));
    expect(h.composer.selection.selected, contains('a'));

    await h.composer.finish();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(h.server.ops, isEmpty, reason: 'the existing pin is not moved');
    expect(
      (h.cubit.graphController.getPositionOrNullForId('fp:a')! - pinOffset)
          .distance,
      lessThan(1),
      reason: 'the person is back at its pin',
    );
  });
}
