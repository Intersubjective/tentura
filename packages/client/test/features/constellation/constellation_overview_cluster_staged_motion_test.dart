import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import 'fixtures/constellation_reference_fixture.dart';

/// Trust communities; everyone inside one trusts everyone else inside it.
typedef _Communities = List<List<String>>;

// Three communities of four people; `a` is pinned and never moves.
const _small = [
  ['a', 'b', 'c', 'd'],
  ['e', 'f', 'g', 'h'],
  ['i', 'j', 'k', 'l'],
];
const _smallPinned = 'a';

// Twenty communities of twenty people: 400 people, nobody pinned.
final _large = [
  for (var c = 0; c < 20; c++)
    [
      for (var i = 0; i < 20; i++)
        'p${(c * 20 + i).toString().padLeft(3, '0')}',
    ],
];

final _loadedAt = DateTime.utc(2026, 10, 26);

ConstellationField _field(
  _Communities communities, {
  String? pinned,
  bool authorsRequests = false,
}) {
  final people = [for (final group in communities) ...group];
  final revision = ConstellationAnchorRevision(BigInt.one);
  return ConstellationField(
    loadedAt: _loadedAt,
    context: '',
    peers: [
      for (final id in people)
        ConstellationPerson(id: id, displayName: 'Person $id'),
    ],
    // Direct contacts are always on the map; authors of a Request are
    // indirect people the render cap has to admit.
    directContactIds: authorsRequests ? const [] : people,
    requests: [
      if (authorsRequests)
        for (final id in people)
          ConstellationRequest(
            id: 'R$id',
            authorId: id,
            title: 'Request $id',
            status: 0,
          ),
    ],
    edges: [
      for (final id in people)
        ConstellationTrustEdgeEntity(src: 'ego', dst: id, tier: 1),
      for (final group in communities)
        for (var i = 0; i < group.length; i++)
          for (var j = i + 1; j < group.length; j++)
            ConstellationTrustEdgeEntity(
              src: group[i],
              dst: group[j],
              tier: 1,
            ),
    ],
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: [
        if (pinned != null)
          ConstellationAnchor(
            target: ConstellationAnchorTarget.person(pinned),
            position: const ConstellationAnchorPosition(
              xUnits: -2,
              yUnits: -1,
              coordinateSpaceVersion: 1,
            ),
            revision: revision,
            placedAt: _loadedAt,
          ),
      ],
      pinnedPeers: [
        if (pinned != null) ConstellationPerson(id: pinned),
      ],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

Future<ConstellationCubit> _mount(
  WidgetTester tester,
  _Communities communities, {
  String? pinned,
  bool authorsRequests = false,
}) async {
  final store = ConstellationStoreFixture(
    _StubRepository(
      _field(communities, pinned: pinned, authorsRequests: authorsRequests),
    ),
    accountId: 'ego',
  ).store;
  final cubit = ConstellationCubit(
    case_: store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
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
    presentationFrameHolder: holder,
  );
  await tester.pumpAndSettle();
  await _zoom(tester, cubit, 1, settle: true);
  return cubit;
}

Future<void> _zoom(
  WidgetTester tester,
  ConstellationCubit cubit,
  double scale, {
  required bool settle,
}) async {
  cubit.graphController.zoomBy(scale / cubit.graphController.cameraScale);
  await tester.pump();
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Map<String, Offset> _positions(
  ConstellationCubit cubit,
  Iterable<String> people,
) => {
  for (final id in people)
    id: () {
      final point = cubit.graphController.renderSnapshot.resolvePosition(
        'fp:$id',
      )!;
      return Offset(point.x, point.y);
    }(),
};

/// Displayed positions of every person on each frame until motion settles.
Future<List<Map<String, Offset>>> _sampleMotion(
  WidgetTester tester,
  ConstellationCubit cubit,
  Iterable<String> people,
) async {
  final frames = <Map<String, Offset>>[];
  for (var frame = 0; frame < 300; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    frames.add(_positions(cubit, people));
    if (!tester.binding.hasScheduledFrame) break;
  }
  expect(tester.binding.hasScheduledFrame, isFalse, reason: 'motion settles');
  return frames;
}

/// How far along its own path [now] is, 0 at [from] and 1 at [to].
double _progress(Offset from, Offset to, Offset now) {
  final path = to - from;
  final moved = now - from;
  return (moved.dx * path.dx + moved.dy * path.dy) /
      (path.dx * path.dx + path.dy * path.dy);
}

/// Per community, the people whose scene position actually changes.
_Communities _movers(
  _Communities communities,
  Map<String, Offset> from,
  Map<String, Offset> to,
) {
  final movers = [
    for (final group in communities)
      [
        for (final id in group)
          if ((to[id]! - from[id]!).distance > 10) id,
      ],
  ]..removeWhere((group) => group.isEmpty);
  return movers;
}

/// Number of distinct values once values within [tolerance] count as one.
int _distinctValues(Iterable<double> values, {double tolerance = 0.01}) {
  final sorted = values.toList()..sort();
  var count = 0;
  double? last;
  for (final value in sorted) {
    if (last == null || value - last > tolerance) count++;
    last = value;
  }
  return count;
}

/// On every frame the people of one community are equally far along their
/// paths: a community moves as one unit.
void _expectCommunitiesMoveAsUnits({
  required _Communities movers,
  required Map<String, Offset> from,
  required Map<String, Offset> to,
  required List<Map<String, Offset>> frames,
}) {
  for (final frame in frames) {
    for (final group in movers) {
      final progress = [
        for (final id in group) _progress(from[id]!, to[id]!, frame[id]!),
      ];
      expect(
        _distinctValues(progress, tolerance: 0.02),
        1,
        reason: 'people of one community move together: $group',
      );
    }
  }
}

void main() {
  group('overview motion is staged by community', () {
    Future<void> expectStartsAtDifferentTimes(
      WidgetTester tester, {
      required Map<String, Offset> from,
      required Future<Map<String, Offset>> Function() act,
      required ConstellationCubit cubit,
    }) async {
      final frames = await _sampleMotion(
        tester,
        cubit,
        _small.expand((g) => g),
      );
      final to = await act();
      final movers = _movers(_small, from, to);
      expect(movers, hasLength(3));
      _expectCommunitiesMoveAsUnits(
        movers: movers,
        from: from,
        to: to,
        frames: frames,
      );

      // The frame on which each community first visibly leaves its start.
      final starts = [
        for (final group in movers)
          frames.indexWhere(
            (frame) =>
                _progress(
                  from[group.first]!,
                  to[group.first]!,
                  frame[group.first]!,
                ) >
                0.02,
          ),
      ];
      expect(starts, everyElement(greaterThanOrEqualTo(0)));
      expect(
        starts.toSet(),
        hasLength(starts.length),
        reason: 'each community starts on its own frame, not together',
      );
    }

    testWidgets('entering overview starts each community at its own time', (
      tester,
    ) async {
      final cubit = await _mount(tester, _small, pinned: _smallPinned);
      final people = _small.expand((group) => group);
      final normal = _positions(cubit, people);

      await _zoom(tester, cubit, 0.4, settle: false);
      await expectStartsAtDifferentTimes(
        tester,
        from: normal,
        cubit: cubit,
        act: () async => _positions(cubit, people),
      );
    });

    testWidgets('leaving overview starts each community at its own time', (
      tester,
    ) async {
      final cubit = await _mount(tester, _small, pinned: _smallPinned);
      final people = _small.expand((group) => group);
      final normal = _positions(cubit, people);
      await _zoom(tester, cubit, 0.4, settle: true);
      final overview = _positions(cubit, people);

      await _zoom(tester, cubit, 0.6, settle: false);
      await expectStartsAtDifferentTimes(
        tester,
        from: overview,
        cubit: cubit,
        act: () async => normal,
      );
    });
  });

  group('overview motion of 400 people', () {
    testWidgets('keeps all 400 people on the map', (tester) async {
      final cubit = await _mount(tester, _large, authorsRequests: true);

      expect(cubit.state.keptPeerIds, hasLength(400));
    });

    testWidgets('moves as twenty community stages, not 400 tweens', (
      tester,
    ) async {
      final cubit = await _mount(tester, _large, authorsRequests: true);
      expect(cubit.state.keptPeerIds, hasLength(400));
      final people = _large.expand((group) => group).toList();
      final normal = _positions(cubit, people);

      await _zoom(tester, cubit, 0.4, settle: false);
      final frames = await _sampleMotion(tester, cubit, people);
      final overview = _positions(cubit, people);

      final movers = _movers(_large, normal, overview);
      expect(movers.length, greaterThan(1));
      _expectCommunitiesMoveAsUnits(
        movers: movers,
        from: normal,
        to: overview,
        frames: frames,
      );

      var mostStagesAtOnce = 0;
      for (final frame in frames) {
        final stagesNow = _distinctValues([
          for (final id in movers.expand((group) => group))
            _progress(normal[id]!, overview[id]!, frame[id]!),
        ]);
        expect(
          stagesNow,
          lessThanOrEqualTo(movers.length),
          reason: 'one progress value per community, never one per person',
        );
        if (stagesNow > mostStagesAtOnce) mostStagesAtOnce = stagesNow;
      }
      expect(
        mostStagesAtOnce,
        greaterThan(1),
        reason: 'communities are staged',
      );
    });
  });
}
