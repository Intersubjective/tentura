import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_grid_clusters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_arrange_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

// At Overview a grid cluster is drawn as one label. Dragging that label moves
// everyone counted in it as one group: one batch of anchor writes, one undo.

const _count = 30;
const _scale = 0.4;
const _drag = Offset(90, 54);

final _people = [
  for (var i = 0; i < _count; i++)
    ConstellationPerson(id: 'c$i', displayName: 'Cluster person $i'),
];

final class _OverviewField implements ConstellationRepositoryPort {
  _OverviewField(this._anchors);

  final ArrangeAnchorRepository _anchors;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 26),
    context: '',
    peers: _people,
    directContactIds: [for (final p in _people) p.id],
    edges: [
      for (final p in _people)
        ConstellationTrustEdgeEntity(src: 'ego', dst: p.id, tier: 1),
    ],
    anchorProjection: ConstellationAnchorProjection(
      revision: arrangeRevision(_anchors.revision),
      anchors: [
        for (final entry in _anchors.anchors.entries)
          ConstellationAnchor(
            target: entry.key,
            position: entry.value,
            revision: arrangeRevision(_anchors.revision),
            placedAt: DateTime.utc(2026, 10, 26),
          ),
      ],
      pinnedPeers: [
        for (final p in _people)
          if (_anchors.anchors.containsKey(
            ConstellationAnchorTarget.person(p.id),
          ))
            p,
      ],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _FakeForwardRepository implements ForwardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The placement outbox flushes on a microtask, outside the fake-async zone;
/// gives it real time until [done].
Future<void> _flushWrites(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

typedef _Dragged = ({
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  ArrangeAnchorRepository anchors,
  Map<ConstellationAnchorTarget, ConstellationAnchorPosition> pinnedBefore,
  Set<ConstellationAnchorTarget> cluster,
  Map<String, Offset> sceneBefore,
  Map<String, Offset> sceneAfter,
  Map<String, Offset> screenBefore,
  Map<String, Offset> screenAfter,
});

/// Mounts a Field of thirty people at Overview, picks the most crowded grid
/// cell and drags its label by [_drag].
Future<_Dragged> _dragCrowdedClusterLabel(
  WidgetTester tester, {
  Map<ConstellationAnchorTarget, ConstellationAnchorPosition> pins = const {},
}) async {
  final anchors = ArrangeAnchorRepository(pins);
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _OverviewField(anchors),
    accountId: 'ego',
    realtime: sync.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    anchors,
    store,
    FakeClockPort(DateTime.utc(2026, 10, 26)),
    FakeWakeUpPort(),
    realtime: sync.case_,
    recordAutomaticHistory: false,
    env: const Env.fromEnvironment(),
    logger: Logger('ConstellationOverviewClusterLabelDragTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: ConstellationAnchorCase(
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationOverviewClusterLabelDragTest'),
    ),
    placementCase: placement,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    forwardCase: buildTestForwardCase(_FakeForwardRepository()),
    loadOnCreate: false,
  );
  await cubit.load();
  addTearDown(() async {
    await cubit.close();
    await placement.dispose();
  });
  final holder = ConstellationPresentationFrameHolder();
  await pumpConstellationBody(
    tester,
    cubit,
    size: const Size(1200, 900),
    locale: const Locale('en'),
    presentationFrameHolder: holder,
    disableAnimations: true,
  );
  await tester.pumpAndSettle();
  cubit.graphController.zoomBy(_scale / cubit.graphController.cameraScale);
  await tester.pumpAndSettle();
  expect(holder.frame!.detail, ConstellationDetailLevel.overview);

  final screen = <String, LPoint>{
    for (final entry in holder.frame!.bodies.entries)
      if (entry.key.startsWith('fp:') && entry.key != 'fp:ego')
        entry.key.substring(3): (
          x: entry.value.center.dx,
          y: entry.value.center.dy,
        ),
  };
  final crowded =
      ([...computeConstellationGridClusters(screenPositions: screen)]..sort(
            (a, b) => b.personIds.length.compareTo(a.personIds.length),
          ))
          .first;
  expect(
    crowded.personIds.length,
    greaterThan(2),
    reason: 'the fixture must put several people into one grid cell',
  );
  Map<String, Offset> sceneNow() => {
    for (final p in _people)
      p.id: cubit.graphController.getPositionOrNullForId('fp:${p.id}')!,
  };
  Map<String, Offset> screenNow() => {
    for (final p in _people) p.id: holder.frame!.bodies['fp:${p.id}']!.center,
  };
  final sceneBefore = sceneNow();
  final screenBefore = screenNow();

  final overview = tester.getTopLeft(find.byType(ConstellationViewportOverlay));
  await tester.dragFrom(
    overview + Offset(crowded.centre.x, crowded.centre.y),
    _drag,
  );
  await tester.pump();
  await _flushWrites(tester, () => anchors.applies.isNotEmpty);
  final sceneAfter = sceneNow();
  final screenAfter = screenNow();
  return (
    cubit: cubit,
    placement: placement,
    anchors: anchors,
    pinnedBefore: {...pins},
    cluster: {
      for (final id in crowded.personIds) ConstellationAnchorTarget.person(id),
    },
    sceneBefore: sceneBefore,
    sceneAfter: sceneAfter,
    screenBefore: screenBefore,
    screenAfter: screenAfter,
  );
}

Offset _scenePoint(ConstellationAnchorPosition position) {
  final point = constellationV1AnchorToPoint(position);
  return Offset(point.x, point.y);
}

void main() {
  group('Dragging a grid cluster label at Overview', () {
    testWidgets('pins every person counted in the cluster in one batch', (
      tester,
    ) async {
      final d = await _dragCrowdedClusterLabel(tester);

      expect(d.anchors.applies, hasLength(1), reason: 'one batch of writes');
      expect(
        d.anchors.applies.single.map((op) => op.target).toSet(),
        d.cluster,
        reason: 'exactly the people the label counts, nobody else',
      );
      expect(d.anchors.applies.single, hasLength(d.cluster.length));
      expect(d.anchors.anchors.keys.toSet(), d.cluster);
      expect(d.placement.history.length, 1, reason: 'one history entry');
    });

    testWidgets('moves the whole cluster by the drag, as one rigid group', (
      tester,
    ) async {
      final d = await _dragCrowdedClusterLabel(tester);

      // The drag is in screen points; people move by the same distance in
      // scene units divided by the camera scale.
      final expected = _drag / _scale;
      expect(d.anchors.anchors.keys.toSet(), d.cluster);
      for (final MapEntry(key: target, value: position)
          in d.anchors.anchors.entries) {
        final moved = _scenePoint(position) - d.sceneBefore[target.id]!;
        expect(moved.dx, closeTo(expected.dx, 2), reason: '${target.id} x');
        expect(moved.dy, closeTo(expected.dy, 2), reason: '${target.id} y');
      }
      // What is drawn moves too: every dot of the cluster, in the scene and
      // on the screen, ends up shifted by the same drag.
      for (final target in d.cluster) {
        final shifted = d.sceneAfter[target.id]! - d.sceneBefore[target.id]!;
        expect(shifted.dx, closeTo(expected.dx, 2), reason: '${target.id} dx');
        expect(shifted.dy, closeTo(expected.dy, 2), reason: '${target.id} dy');
        final onScreen = d.screenAfter[target.id]! - d.screenBefore[target.id]!;
        expect(onScreen.dx, closeTo(_drag.dx, 2), reason: '${target.id} px');
        expect(onScreen.dy, closeTo(_drag.dy, 2), reason: '${target.id} py');
      }
    });

    testWidgets('one undo takes the whole cluster back to unpinned', (
      tester,
    ) async {
      final d = await _dragCrowdedClusterLabel(tester);
      expect(
        d.anchors.anchors.keys.toSet(),
        d.cluster,
        reason: 'the drag pinned the whole cluster',
      );

      final undone = await tester.runAsync(d.cubit.undoArrangement);
      await _flushWrites(tester, () => d.anchors.applies.length > 1);

      expect(undone, isTrue);
      expect(d.anchors.anchors, isEmpty, reason: 'one undo unpins everyone');
      expect(d.cubit.canUndoArrangement, isFalse, reason: 'a single step');
    });

    testWidgets(
      'one undo puts already pinned people back where they were pinned',
      (tester) async {
        // Five columns, 0.5 units apart: close enough to share grid cells at
        // this zoom; a mix of pinned and unpinned people in the cluster.
        final pins = {
          for (var i = 0; i < _count; i += 2)
            ConstellationAnchorTarget.person('c$i'): arrangePosition(
              (i % 5) * 0.5,
              (i ~/ 5) * 0.5,
            ),
        };
        final d = await _dragCrowdedClusterLabel(tester, pins: pins);

        expect(
          d.cluster.intersection(d.pinnedBefore.keys.toSet()),
          isNotEmpty,
          reason: 'the cluster holds people who were already pinned',
        );
        expect(
          d.cluster.difference(d.pinnedBefore.keys.toSet()),
          isNotEmpty,
          reason: 'the cluster holds people who were not pinned yet',
        );
        expect(d.anchors.applies, hasLength(1), reason: 'one batch of writes');
        expect(
          d.anchors.applies.single.map((op) => op.target).toSet(),
          d.cluster,
          reason: 'the batch writes exactly the people the label counts',
        );

        final undone = await tester.runAsync(d.cubit.undoArrangement);
        await _flushWrites(tester, () => d.anchors.applies.length > 1);

        expect(undone, isTrue);
        expect(
          d.anchors.anchors,
          d.pinnedBefore,
          reason: 'pinned people return to their old pins, the rest unpin',
        );
        expect(d.cubit.canUndoArrangement, isFalse, reason: 'a single step');
      },
    );
  });
}
