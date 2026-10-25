import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// A person's pinned Posts follow their author on the Field exactly as the
// author's pinned Requests do: on a single drag, on a group drag and on
// «Arrange in a sector» they move by the author's delta, live, and are
// written in the same batch. A Post that is moved itself (selected) goes to
// its own place, once; an unpinned Post is left to the layout. A Request
// grown from a Post keeps following its author only, never the Post.

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {
    emit(state.copyWith(selectedProfile: profile, dismissedFocusId: null));
  }

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() => emit(const GraphPersonContextState());
}

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

/// Canvas centre and one envelope unit in scene pixels (10 units = 1700 px).
const _centre = 2048.0;
const _unit = 170.0;

/// The anchor store of the server: applies batches and, like the real one,
/// refuses a position out of range.
final class _Server implements ConstellationAnchorRepositoryPort {
  _Server(Map<ConstellationAnchorTarget, (double, double)> seeded) {
    for (final MapEntry(key: target, value: (x, y)) in seeded.entries) {
      anchors[target] = ConstellationAnchor(
        target: target,
        position: ConstellationAnchorPosition(
          xUnits: x,
          yUnits: y,
          coordinateSpaceVersion: 1,
        ),
        revision: _revision(revision),
        placedAt: DateTime.utc(2026, 10, 22),
      );
    }
  }

  int revision = 7;
  final anchors = <ConstellationAnchorTarget, ConstellationAnchor>{};
  final applies = <List<ConstellationAnchorApplyOp>>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    applies.add(List.of(ops));
    for (final op in ops) {
      expect(
        ConstellationAnchorPosition.validate(
          xUnits: op.position!.xUnits,
          yUnits: op.position!.yUnits,
          coordinateSpaceVersion: op.position!.coordinateSpaceVersion,
        ),
        isA<ConstellationAnchorPositionValid>(),
        reason: '${op.target} written out of range',
      );
    }
    final before = revision;
    final results = <ConstellationAnchorOpResult>[];
    for (final op in ops) {
      revision++;
      final anchor = ConstellationAnchor(
        target: op.target,
        position: op.position!,
        revision: _revision(revision),
        placedAt: DateTime.utc(2026, 10, 22),
      );
      anchors[op.target] = anchor;
      results.add(
        ConstellationAnchorOpResult(
          clientOpId: op.clientOpId,
          status: ConstellationAnchorOpStatus.ok,
          resultingTargetRevision: _revision(revision),
          target: op.target,
          anchor: anchor,
        ),
      );
    }
    return ConstellationAnchorApplyResult(
      beforeRevision: _revision(before),
      afterRevision: _revision(revision),
      results: results,
    );
  }

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
}

/// A FULL read of the field, with whatever the server has stored.
final class _Fields implements ConstellationRepositoryPort {
  _Fields(this.server, this.requests);

  final _Server server;
  final List<ConstellationRequest> requests;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 22),
    context: '',
    peers: _people,
    edges: [
      for (final person in _people)
        ConstellationTrustEdgeEntity(src: 'ego', dst: person.id, tier: 1),
    ],
    requests: requests,
    // A Post is pinned when the server stores a position for it.
    posts: [
      for (final person in _people)
        ConstellationPost(
          id: 'post-${person.id}',
          authorId: person.id,
          rootExcerpt: 'Hello',
          lastActivityAt: DateTime.utc(2026, 10, 22),
          isPinned: server.anchors.containsKey(
            ConstellationAnchorTarget.beacon('post-${person.id}'),
          ),
        ),
    ],
    anchorProjection: ConstellationAnchorProjection(
      revision: _revision(server.revision),
      anchors: server.anchors.values.toList(),
      pinnedPeers: [
        for (final person in _people)
          if (server.anchors.containsKey(
            ConstellationAnchorTarget.person(person.id),
          ))
            person,
      ],
      pinnedRequests: [
        for (final request in requests)
          if (server.anchors.containsKey(
            ConstellationAnchorTarget.beacon(request.id),
          ))
            request,
      ],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _size = Size(1200, 900);

const _people = [
  ConstellationPerson(id: 'a', displayName: 'Ann'),
  ConstellationPerson(id: 'b', displayName: 'Bob'),
  ConstellationPerson(id: 'c', displayName: 'Cat'),
];

final _ann = ConstellationAnchorTarget.person('a');
final _bob = ConstellationAnchorTarget.person('b');
final _postA = ConstellationAnchorTarget.beacon('post-a');
final _postB = ConstellationAnchorTarget.beacon('post-b');
final _grown = ConstellationAnchorTarget.beacon('req-grown');

/// Ann's Request that grew from her Post, pinned.
const _grownRequest = ConstellationRequest(
  id: 'req-grown',
  authorId: 'a',
  title: 'Help',
  status: 0,
  parentBeaconId: 'post-a',
);

/// Ann and her Post pinned apart; Bob pinned, his Post left to the layout.
final _seeded = {
  _ann: (1.0, 0.0),
  _postA: (2.0, 1.0),
  _bob: (-1.0, 1.0),
};

typedef _Harness = ({
  _Server server,
  ConstellationCubit cubit,
  ConstellationSelectionCubit selection,
});

Future<_Harness> _mount(
  WidgetTester tester, {
  bool withGrownRequest = false,
}) async {
  final server = _Server({
    ..._seeded,
    if (withGrownRequest) _grown: (1.0, -1.5),
  });
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _Fields(server, [if (withGrownRequest) _grownRequest]),
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
    logger: Logger('ConstellationPostFollowsAuthorTest'),
  );
  final cubit = ConstellationCubit(
    case_: store,
    placementCase: placement,
    viewer: _ego,
  );
  final selection = ConstellationSelectionCubit();
  addTearDown(() async {
    await selection.close();
    await cubit.close();
    await placement.dispose();
    await sync.port.dispose();
  });
  await tester.runAsync(
    () => cubit.stream.firstWhere((state) => state.status is StateIsSuccess),
  );
  await tester.binding.setSurfaceSize(_size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: _size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<ConstellationSelectionCubit>.value(
                value: selection,
              ),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: Scaffold(
              body: ConstellationBody(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (server: server, cubit: cubit, selection: selection);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Lets the outbox send its batch and the store settle.
Future<void> _flushWrites(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

Offset _at(ConstellationCubit cubit, ConstellationAnchorTarget target) {
  final graphId = switch (target.kind) {
    ConstellationAnchorTargetKind.person => 'fp:${target.id}',
    ConstellationAnchorTargetKind.beacon => 'fr:${target.id}',
  };
  final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
  expect(point, isNotNull, reason: '$graphId must be laid out');
  return Offset(point!.x, point.y);
}

/// Scene centre of a written position.
Offset _written(ConstellationAnchorApplyOp op) => Offset(
  _centre + op.position!.xUnits * _unit,
  _centre + op.position!.yUnits * _unit,
);

/// Drags [target] (with [group]) by [by] in scene pixels through the cubit
/// and drops it; returns the scene positions before the drag of [watch].
Future<Map<ConstellationAnchorTarget, Offset>> _dragBy(
  WidgetTester tester,
  _Harness h,
  ConstellationAnchorTarget target,
  Offset by, {
  required Iterable<ConstellationAnchorTarget> watch,
  Iterable<ConstellationAnchorTarget> group = const [],
  void Function(Map<ConstellationAnchorTarget, Offset> starts)? live,
}) async {
  final starts = {
    for (final t in {target, ...watch}) t: _at(h.cubit, t),
  };
  h.cubit.beginDragExisting(target: target, group: group);
  final graphId = target.kind == ConstellationAnchorTargetKind.person
      ? 'fp:${target.id}'
      : 'fr:${target.id}';
  final proposed = starts[target]! + by;
  h.cubit.updateDragPresentation(nodeId: graphId, sceneCentre: proposed);
  await _frames(tester);
  live?.call(starts);
  await h.cubit.onExistingNodeDrop(target: target, sceneCentre: proposed);
  await _flushWrites(tester);
  return starts;
}

void expectOffset(Offset actual, Offset expected, {String? reason}) {
  expect(actual.dx, closeTo(expected.dx, 0.5), reason: reason);
  expect(actual.dy, closeTo(expected.dy, 0.5), reason: reason);
}

void main() {
  testWidgets('dragging a person moves their pinned Post with them, live, '
      'and writes it in the same batch', (tester) async {
    final h = await _mount(tester);
    expect(_node('post-a'), findsOneWidget);
    expect(h.cubit.isAnchored(_postA), isTrue);
    const by = Offset(90, 60);

    final starts = await _dragBy(
      tester,
      h,
      _ann,
      by,
      watch: [_postA, _postB],
      live: (starts) {
        expectOffset(_at(h.cubit, _postA), starts[_postA]! + by);
        expectOffset(
          _at(h.cubit, _postB),
          starts[_postB]!,
          reason: "another person's Post stays",
        );
      },
    );

    expect(h.server.applies, hasLength(1), reason: 'one batch');
    final ops = {for (final op in h.server.applies.single) op.target: op};
    expect(ops.keys, unorderedEquals([_ann, _postA]));
    expectOffset(_written(ops[_ann]!) - starts[_ann]!, by);
    expectOffset(_written(ops[_postA]!) - starts[_postA]!, by);
    expect(h.cubit.isAnchored(_postA), isTrue);
  });

  testWidgets('an unpinned Post is left to the layout: nothing of it is '
      'written when its author is dragged', (tester) async {
    final h = await _mount(tester);
    expect(_node('post-b'), findsOneWidget);
    expect(h.cubit.isAnchored(_postB), isFalse);

    await _dragBy(tester, h, _bob, const Offset(-60, 40), watch: const []);

    expect(h.server.applies.single.map((op) => op.target), [_bob]);
  });

  testWidgets('on a group drag a selected person brings their pinned Post '
      'along by their own delta', (tester) async {
    final h = await _mount(tester);
    h.selection
      ..toggle(_ann)
      ..toggle(_bob);
    await _frames(tester);
    const by = Offset(-70, 50);

    final starts = await _dragBy(
      tester,
      h,
      _bob,
      by,
      group: h.selection.state.dragGroupFor(_bob),
      watch: [_ann, _postA],
      live: (starts) {
        expectOffset(_at(h.cubit, _ann), starts[_ann]! + by);
        expectOffset(_at(h.cubit, _postA), starts[_postA]! + by);
      },
    );

    expect(h.server.applies, hasLength(1));
    final ops = {for (final op in h.server.applies.single) op.target: op};
    expect(ops.keys, unorderedEquals([_ann, _bob, _postA]));
    expectOffset(_written(ops[_postA]!) - starts[_postA]!, by);
  });

  testWidgets('a selected Post moves with the group, once, not as its '
      "author's companion", (tester) async {
    final h = await _mount(tester);
    h.selection
      ..toggle(_ann)
      ..toggle(_postA);
    await _frames(tester);
    const by = Offset(40, -30);

    final starts = await _dragBy(
      tester,
      h,
      _ann,
      by,
      group: h.selection.state.dragGroupFor(_ann),
      watch: [_postA],
    );

    final batch = h.server.applies.single;
    expect(
      batch.where((op) => op.target == _postA),
      hasLength(1),
      reason: 'written once',
    );
    final ops = {for (final op in batch) op.target: op};
    expect(ops.keys, unorderedEquals([_ann, _postA]));
    expectOffset(_written(ops[_postA]!) - starts[_postA]!, by);
  });

  testWidgets('dragging a pinned Post alone moves only the Post', (
    tester,
  ) async {
    final h = await _mount(tester, withGrownRequest: true);
    const by = Offset(30, 30);

    final starts = await _dragBy(
      tester,
      h,
      _postA,
      by,
      watch: [_ann, _grown],
      live: (starts) {
        expectOffset(_at(h.cubit, _ann), starts[_ann]!);
        expectOffset(
          _at(h.cubit, _grown),
          starts[_grown]!,
          reason: 'a grown Request does not follow its Post',
        );
      },
    );

    expect(h.server.applies.single.map((op) => op.target), [_postA]);
    expectOffset(
      _written(h.server.applies.single.single) - starts[_postA]!,
      by,
    );
  });

  testWidgets('a pinned Request grown from a Post still follows its author, '
      'next to the Post', (tester) async {
    final h = await _mount(tester, withGrownRequest: true);
    expect(_node('req-grown'), findsOneWidget);
    const by = Offset(-50, -40);

    final starts = await _dragBy(
      tester,
      h,
      _ann,
      by,
      watch: [_postA, _grown],
    );

    final batch = h.server.applies.single;
    expect(
      batch.map((op) => op.target),
      unorderedEquals([_ann, _postA, _grown]),
      reason: 'each written once',
    );
    final ops = {for (final op in batch) op.target: op};
    expectOffset(_written(ops[_grown]!) - starts[_grown]!, by);
    expectOffset(_written(ops[_postA]!) - starts[_postA]!, by);
  });

  testWidgets('«Arrange in a sector»: a pinned Post follows its arranged '
      'author; an arranged Post goes to its own place', (tester) async {
    final h = await _mount(tester);
    final annStart = _at(h.cubit, _ann);
    final postStart = _at(h.cubit, _postA);
    final annTarget = annStart + const Offset(120, -80);

    expect(
      h.cubit.placeArrangement({
        _ann: annTarget,
        _bob: _at(h.cubit, _bob) + const Offset(10, 10),
      }),
      isTrue,
    );
    await _flushWrites(tester);

    var ops = {for (final op in h.server.applies.last) op.target: op};
    expect(ops.keys, unorderedEquals([_ann, _bob, _postA]));
    expectOffset(_written(ops[_postA]!), postStart + (annTarget - annStart));

    final postTarget = _at(h.cubit, _postA) + const Offset(-200, 150);
    expect(
      h.cubit.placeArrangement({
        _ann: _at(h.cubit, _ann) + const Offset(30, 30),
        _postA: postTarget,
      }),
      isTrue,
    );
    await _flushWrites(tester);

    ops = {for (final op in h.server.applies.last) op.target: op};
    expect(
      h.server.applies.last.where((op) => op.target == _postA),
      hasLength(1),
    );
    expectOffset(_written(ops[_postA]!), postTarget);
  });

  testWidgets('a touch drag of a person carries the pinned Post on screen', (
    tester,
  ) async {
    final h = await _mount(tester);
    final postScreen = tester.getCenter(_node('post-a'));
    final ann = tester.getCenter(_node('a'));
    // A touch pointer, the default.
    final gesture = await tester.startGesture(ann);
    await _frames(tester);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(ann + const Offset(80, 40) * (i / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getCenter(_node('post-a')), isNot(postScreen));
    await gesture.up();
    await _frames(tester);
    await _flushWrites(tester);

    expect(
      h.server.applies.single.map((op) => op.target),
      unorderedEquals([_ann, _postA]),
    );
  });
}
