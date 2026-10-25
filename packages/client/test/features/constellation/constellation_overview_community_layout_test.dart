import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/layout/constellation_communities.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _people = ['a', 'b', 'c', 'd', 'e', 'f'];
final _loadedAt = DateTime.utc(2026, 10, 26);
final _initialRevision = ConstellationAnchorRevision(BigInt.one);

// Two disconnected triangles among peers make the partition unambiguous for
// any fixed seed. Ego's spokes supply normal Field paths, not community links.
ConstellationField _field() => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: [
    for (final id in _people)
      ConstellationPerson(id: id, displayName: 'Person $id'),
  ],
  directContactIds: _people,
  edges: [
    for (final id in _people)
      ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
    for (final group in [
      const ['a', 'b', 'c'],
      const ['d', 'e', 'f'],
    ])
      for (var i = 0; i < group.length; i++)
        for (var j = i + 1; j < group.length; j++)
          ConstellationTrustEdgeEntity(src: group[i], dst: group[j], tier: 1),
  ],
  anchorProjection: ConstellationAnchorProjection(
    revision: _initialRevision,
    anchors: [
      ConstellationAnchor(
        target: ConstellationAnchorTarget.person('a'),
        position: const ConstellationAnchorPosition(
          xUnits: -2,
          yUnits: -1,
          coordinateSpaceVersion: 1,
        ),
        revision: _initialRevision,
        placedAt: _loadedAt,
      ),
    ],
    pinnedPeers: const [ConstellationPerson(id: 'a', displayName: 'Person a')],
    pinnedRequests: const [],
    supportPeers: const [],
    supportEdges: const [],
    serverFilteredBeaconIds: const [],
    serverFilteredBeaconCount: 0,
  ),
);

class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

class _RecordingAnchors extends Fake
    implements ConstellationAnchorRepositoryPort {
  _RecordingAnchors(this.repository);

  final _FieldRepository repository;
  final calls = <List<ConstellationAnchorApplyOp>>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    calls.add(List.of(ops));
    final projection = repository.field.resolvedAnchorProjection;
    final revision = ConstellationAnchorRevision(
      projection.revision.value + BigInt.one,
    );
    final anchors = [
      for (final op in ops)
        ConstellationAnchor(
          target: op.target,
          position: op.position!,
          revision: revision,
          placedAt: _loadedAt,
        ),
    ];
    final storedAnchors = [
      for (final anchor in projection.anchors)
        if (!ops.any((op) => op.target == anchor.target)) anchor,
      ...anchors,
    ];
    final pinnedPersonIds = {
      for (final anchor in storedAnchors)
        if (anchor.target.kind == ConstellationAnchorTargetKind.person)
          anchor.target.id,
    };
    repository.field = repository.field.copyWith(
      anchorProjection: ConstellationAnchorProjection(
        revision: revision,
        anchors: storedAnchors,
        pinnedPeers: [
          for (final peer in repository.field.peers)
            if (pinnedPersonIds.contains(peer.id)) peer,
        ],
        pinnedRequests: projection.pinnedRequests,
        supportPeers: projection.supportPeers,
        supportEdges: projection.supportEdges,
        serverFilteredBeaconIds: projection.serverFilteredBeaconIds,
        serverFilteredBeaconCount: projection.serverFilteredBeaconCount,
      ),
    );
    return ConstellationAnchorApplyResult(
      beforeRevision: projection.revision,
      afterRevision: revision,
      results: [
        for (var i = 0; i < ops.length; i++)
          ConstellationAnchorOpResult(
            clientOpId: ops[i].clientOpId,
            status: ConstellationAnchorOpStatus.ok,
            resultingTargetRevision: revision,
            target: ops[i].target,
            anchor: anchors[i],
          ),
      ],
    );
  }
}

typedef _MapHarness = ({
  ConstellationCubit cubit,
  ConstellationPresentationFrameHolder holder,
  _RecordingAnchors anchors,
});

Future<_MapHarness> _mount(
  WidgetTester tester, {
  bool reducedMotion = false,
}) async {
  final repository = _FieldRepository(_field());
  final anchors = _RecordingAnchors(repository);
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final store = ConstellationStoreFixture(
    repository,
    accountId: 'ego',
    realtime: realtime.case_,
  ).store;
  final placement = ConstellationPlacementCase(
    anchors,
    store,
    FakeClockPort(_loadedAt),
    FakeWakeUpPort(),
    realtime: realtime.case_,
    recordAutomaticHistory: false,
    env: const Env.fromEnvironment(),
    logger: Logger('OverviewCommunityLayoutTest'),
  );
  addTearDown(placement.dispose);
  final cubit = ConstellationCubit(
    case_: store,
    viewer: kRefEgo,
    placementCase: placement,
    semanticZoomEnabled: true,
  );
  addTearDown(cubit.close);
  if (cubit.state.status is! StateIsSuccess) {
    await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  }
  final holder = ConstellationPresentationFrameHolder();
  await pumpConstellationBody(
    tester,
    cubit,
    size: const Size(1200, 900),
    disableAnimations: reducedMotion,
    presentationFrameHolder: holder,
  );
  await tester.pumpAndSettle();
  await _zoom(tester, cubit, 1);
  expect(holder.frame!.detail, ConstellationDetailLevel.close);
  expect(_positions(cubit).keys, unorderedEquals(_people));
  return (cubit: cubit, holder: holder, anchors: anchors);
}

Future<void> _zoom(
  WidgetTester tester,
  ConstellationCubit cubit,
  double scale, {
  bool settle = true,
}) async {
  cubit.graphController.zoomBy(scale / cubit.graphController.cameraScale);
  await tester.pump();
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
  expect(cubit.graphController.cameraScale, closeTo(scale, 1e-6));
}

// Scene coordinates exclude camera movement: a zoom alone cannot satisfy a
// movement assertion. Read presentation positions, including active tweens.
Offset _position(ConstellationCubit cubit, String graphId) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
  expect(point, isNotNull, reason: '$graphId has a displayed scene position');
  return Offset(point!.x, point.y);
}

Map<String, Offset> _positions(ConstellationCubit cubit) => {
  for (final id in _people) id: _position(cubit, 'fp:$id'),
};

Map<String, Offset> _communityPositions(
  ConstellationCubit cubit,
  Map<String, Offset> normal, {
  ConstellationCommunityLayout? previous,
}) => {
  for (final e in _communityLayout(
    cubit,
    normal,
    previous: previous,
  ).positions.entries)
    e.key: Offset(e.value.x, e.value.y),
};

ConstellationCommunityLayout _communityLayout(
  ConstellationCubit cubit,
  Map<String, Offset> normal, {
  ConstellationCommunityLayout? previous,
}) {
  final ego = _position(cubit, 'fp:ego');
  final layout = computeConstellationCommunities(
    ego: (x: ego.dx, y: ego.dy),
    fieldPositions: {
      for (final e in normal.entries) e.key: (x: e.value.dx, y: e.value.dy),
    },
    trustEdges: [
      for (final e in cubit.state.field!.edges)
        (src: e.src, dst: e.dst, tier: e.tier),
    ],
    pinnedPositions: {
      for (final anchor in cubit.state.field!.resolvedAnchorProjection.anchors)
        if (anchor.target.kind == ConstellationAnchorTargetKind.person)
          anchor.target.id: (
            x: normal[anchor.target.id]!.dx,
            y: normal[anchor.target.id]!.dy,
          ),
    },
    seed: 42,
    previous: previous,
  );
  expect(
    layout.communities.values,
    unorderedEquals([
      unorderedEquals(['a', 'b', 'c']),
      unorderedEquals(['d', 'e', 'f']),
    ]),
    reason: 'fixture has two peer communities independently of seed',
  );
  return layout;
}

void _expectPositions(
  Map<String, Offset> actual,
  Map<String, Offset> expected,
) {
  expect(actual.keys, unorderedEquals(expected.keys));
  for (final id in expected.keys) {
    expect((actual[id]! - expected[id]!).distance, lessThan(0.01), reason: id);
  }
}

// Sample actual presentation coordinates until the framework settles, without
// prescribing an animation duration. An instant jump has no intermediate seat.
Future<void> _expectAnimatedTravel(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required Map<String, Offset> from,
  required Map<String, Offset> to,
}) async {
  final unpinnedIds = _people.where((id) => id != 'a').toSet();
  final travelledIds = <String>{};
  for (var frame = 0; frame < 300; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    final positions = _positions(cubit);
    for (final id in unpinnedIds) {
      if ((positions[id]! - from[id]!).distance > 0.01 &&
          (positions[id]! - to[id]!).distance > 0.01) {
        travelledIds.add(id);
      }
    }
    expect(positions['a'], from['a'], reason: 'the existing pin stays fixed');
    if (!tester.binding.hasScheduledFrame) break;
  }
  expect(tester.binding.hasScheduledFrame, isFalse, reason: 'motion settles');
  for (final id in unpinnedIds) {
    expect(
      travelledIds,
      contains(id),
      reason: '$id must travel through an intermediate scene position',
    );
  }
  _expectPositions(_positions(cubit), to);
  expect(cubit.graphController.isLayoutSettling, isFalse);
}

void main() {
  group('community geometry at overview', () {
    testWidgets('places unpinned people in trust communities and keeps pins '
        'fixed without writing anchors', (tester) async {
      final m = await _mount(tester);
      final normal = _positions(m.cubit);
      final expected = _communityPositions(m.cubit, normal);
      expect((expected['b']! - normal['b']!).distance, greaterThan(10));

      await _zoom(tester, m.cubit, 0.4);

      expect(m.holder.frame!.detail, ConstellationDetailLevel.overview);
      _expectPositions(_positions(m.cubit), expected);
      expect(_positions(m.cubit)['a'], normal['a']);
      expect(m.anchors.calls, isEmpty);
      expect(
        m.cubit.state.field!.resolvedAnchorProjection.anchors,
        hasLength(1),
      );
    });

    testWidgets('reuses the overview layout across zooms with unchanged '
        'membership and trust edges', (tester) async {
      final m = await _mount(tester);
      final normal = _positions(m.cubit);
      final expected = _communityPositions(m.cubit, normal);
      await _zoom(tester, m.cubit, 0.4);
      final runs = m.cubit.graphController.relayoutInvocationCount;
      final topology = m.cubit.graphController.topologyRevision.value;

      // The 4096 px canvas must still cover the viewport; stay above its
      // minimum fit scale while exercising several overview zoom values.
      for (final scale in [0.34, 0.38, 0.4]) {
        await _zoom(tester, m.cubit, scale);
        expect(m.cubit.graphController.relayoutInvocationCount, runs);
        _expectPositions(_positions(m.cubit), expected);
      }
      for (final scale in [0.6, 1.0, 0.4, 1.0, 0.4]) {
        await _zoom(tester, m.cubit, scale);
        if (scale == 0.4) {
          _expectPositions(_positions(m.cubit), expected);
        } else {
          _expectPositions(_positions(m.cubit), normal);
        }
      }
      expect(m.cubit.graphController.topologyRevision.value, topology);
      expect(m.anchors.calls, isEmpty);
    });
  });

  group('travel between overview and normal Field positions', () {
    testWidgets('leaving overview animates in scene space and restores every '
        'normal position', (tester) async {
      final m = await _mount(tester);
      final normal = _positions(m.cubit);
      await _zoom(tester, m.cubit, 0.4);
      final overview = _positions(m.cubit);

      await _zoom(tester, m.cubit, 0.6, settle: false);
      expect(m.holder.frame!.detail, ConstellationDetailLevel.district);
      await _expectAnimatedTravel(tester, m.cubit, from: overview, to: normal);
      expect(m.anchors.calls, isEmpty);
    });

    testWidgets('entering overview reaches community positions and keeps '
        'existing pins fixed', (tester) async {
      final m = await _mount(tester);
      final normal = _positions(m.cubit);
      final expected = _communityPositions(m.cubit, normal);

      await _zoom(tester, m.cubit, 0.4);
      _expectPositions(_positions(m.cubit), expected);
      expect(_positions(m.cubit)['a'], normal['a']);
      expect(m.anchors.calls, isEmpty);
    });

    testWidgets('reduced motion reaches both layouts without advancing the '
        'animation clock', (tester) async {
      final m = await _mount(tester, reducedMotion: true);
      final normal = _positions(m.cubit);
      final expected = _communityPositions(m.cubit, normal);

      await _zoom(tester, m.cubit, 0.4, settle: false);
      _expectPositions(_positions(m.cubit), expected);
      expect(m.cubit.graphController.isLayoutSettling, isFalse);
      await _zoom(tester, m.cubit, 0.6, settle: false);
      _expectPositions(_positions(m.cubit), normal);
      expect(m.cubit.graphController.isLayoutSettling, isFalse);
      await _zoom(tester, m.cubit, 0.4, settle: false);
      _expectPositions(_positions(m.cubit), expected);
      expect(m.cubit.graphController.isLayoutSettling, isFalse);
      expect(m.anchors.calls, isEmpty);
    });
  });

  group('dragging an overview dot', () {
    testWidgets('writes one pin at the drop and excludes that person from '
        'automatic community placement on later zooms', (tester) async {
      final m = await _mount(tester);
      final normal = _positions(m.cubit);
      final initialLayout = _communityLayout(m.cubit, normal);
      await _zoom(tester, m.cubit, 0.4);
      final overview = _positions(m.cubit);
      final overlayOrigin = tester.getTopLeft(
        find.byType(ConstellationViewportOverlay),
      );
      final dot = m.holder.frame!.bodies['fp:b']!.center;
      final gesture = await tester.startGesture(overlayOrigin + dot);
      await tester.pump();
      await gesture.moveBy(const Offset(80, 50));
      await tester.pump(const Duration(milliseconds: 16));
      final drop = _positions(m.cubit)['b']!;
      expect((drop - overview['b']!).distance, greaterThan(50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(m.anchors.calls, hasLength(1));
      final op = m.anchors.calls.single.single;
      expect(op.kind, ConstellationAnchorOpKind.upsert);
      expect(op.target, ConstellationAnchorTarget.person('b'));
      expect(op.position, isNotNull);
      expect(m.cubit.isAnchored(op.target), isTrue);
      expect((_positions(m.cubit)['b']! - drop).distance, lessThan(0.01));
      expect(
        m.anchors.repository.field.resolvedAnchorProjection.pinnedPeers.map(
          (peer) => peer.id,
        ),
        unorderedEquals(['a', 'b']),
      );
      expect(
        m.cubit.state.field!.resolvedAnchorProjection.anchors.map(
          (anchor) => anchor.target,
        ),
        unorderedEquals([
          ConstellationAnchorTarget.person('a'),
          ConstellationAnchorTarget.person('b'),
        ]),
      );

      await _zoom(tester, m.cubit, 1);
      expect((_positions(m.cubit)['b']! - drop).distance, lessThan(0.01));
      final expectedAfterPin = _communityPositions(
        m.cubit,
        _positions(m.cubit),
        previous: initialLayout,
      );
      await _zoom(tester, m.cubit, 0.4);
      expect((_positions(m.cubit)['b']! - drop).distance, lessThan(0.01));
      expect(_positions(m.cubit)['a'], normal['a']);
      expect(m.anchors.calls, hasLength(1));
      // All four unpinned peers must still use community geometry after the
      // zoom round trip; keeping just the two pins in place is insufficient.
      _expectPositions(_positions(m.cubit), expectedAfterPin);
    });
  });
}
