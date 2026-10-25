import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_arrange_harness.dart';

// Gathering a big selection is one user action: the whole cluster is written
// as one batch and one undo takes the whole gather back.

const _count = 40;

final _people = [
  for (var i = 0; i < _count; i++)
    ConstellationPerson(id: 'g$i', displayName: 'Gatherer $i'),
];

final class _FortyPeopleField implements ConstellationRepositoryPort {
  _FortyPeopleField(this._anchors);

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
      anchors: const [],
      pinnedPeers: const [],
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

typedef _Gathered = ({
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  ArrangeAnchorRepository anchors,
  Set<ConstellationAnchorTarget> targets,
  Map<String, Offset> before,
});

/// Mounts a Field of forty unpinned people, selects them all and taps the
/// selection bar's Gather.
Future<_Gathered> _gatherForty(WidgetTester tester) async {
  final anchors = ArrangeAnchorRepository(const {});
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _FortyPeopleField(anchors),
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
    logger: Logger('ConstellationGatherBatchTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    anchorCase: ConstellationAnchorCase(
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationGatherBatchTest'),
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
  final selection = ConstellationSelectionCubit();
  addTearDown(selection.close);
  await pumpArrangeBody(
    tester,
    cubit,
    arrangeV2Enabled: true,
    selection: selection,
  );
  await tester.pumpAndSettle();
  final targets = {
    for (final p in _people) ConstellationAnchorTarget.person(p.id),
  };
  selection.addAll(targets);
  await tester.pumpAndSettle();
  final before = {
    for (final p in _people)
      p.id: cubit.graphController.getPositionOrNullForId('fp:${p.id}')!,
  };

  final gather = find.text('Gather');
  expect(gather, findsOneWidget, reason: 'the selection bar offers Gather');
  await tester.ensureVisible(gather);
  await tester.tap(gather);
  await tester.pump();
  await _flushWrites(tester, () => anchors.applies.isNotEmpty);
  return (
    cubit: cubit,
    placement: placement,
    anchors: anchors,
    targets: targets,
    before: before,
  );
}

void main() {
  testWidgets(
    'gathering forty people writes one batch and undoes in one step',
    (
      tester,
    ) async {
      final g = await _gatherForty(tester);

      expect(g.anchors.applies, hasLength(1), reason: 'one batch');
      expect(g.anchors.applies.single, hasLength(_count));
      expect(g.anchors.anchors.keys.toSet(), g.targets);
      expect(g.placement.history.length, 1, reason: 'one history entry');

      final undone = await tester.runAsync(g.cubit.undoArrangement);
      await _flushWrites(tester, () => g.anchors.applies.length > 1);

      expect(undone, isTrue);
      expect(g.anchors.anchors, isEmpty, reason: 'one undo unpins everyone');
      expect(g.cubit.canUndoArrangement, isFalse);
    },
  );

  testWidgets('gathering forty people centres the cluster on where they were', (
    tester,
  ) async {
    final g = await _gatherForty(tester);

    Offset centroid(Iterable<Offset> points) =>
        points.reduce((a, b) => a + b) / points.length.toDouble();
    final after = [
      for (final anchor in g.anchors.anchors.values)
        () {
          final point = constellationV1AnchorToPoint(anchor);
          return Offset(point.x, point.y);
        }(),
    ];
    expect(after, hasLength(_count));
    final was = centroid(g.before.values);
    final now = centroid(after);
    expect(now.dx, closeTo(was.dx, 1), reason: 'centroid x');
    expect(now.dy, closeTo(was.dy, 1), reason: 'centroid y');
  });
}
