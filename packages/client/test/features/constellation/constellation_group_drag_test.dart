import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// Group drag on the Field (#642 follow-up): dragging a node that is part of
// the multi-selection moves every selected draggable node by the same scene
// delta, live, as one rigid group, and the drop writes them all in one batch
// the way a drag of each would. Any other node still moves alone, and the
// selection is left as it was either way.

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

/// The anchor store of the server: applies batches.
final class _Server implements ConstellationAnchorRepositoryPort {
  _Server([
    Map<ConstellationAnchorTarget, (double, double)> seeded = const {},
  ]) {
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
    // The real server refuses the whole batch for one position out of range.
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
  _Fields(this.server, this.people);

  final _Server server;
  final List<ConstellationPerson> people;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 22),
    context: '',
    peers: people,
    edges: [
      for (final person in people)
        ConstellationTrustEdgeEntity(src: 'ego', dst: person.id, tier: 1),
    ],
    // A person with nothing of theirs on the field is not drawn. A Post is
    // pinned when the server stores a position for it.
    posts: [
      for (final person in people)
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
        for (final person in people)
          if (server.anchors.containsKey(
            ConstellationAnchorTarget.person(person.id),
          ))
            person,
      ],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

const _ego = Profile(id: 'ego', displayName: 'Ego');
const _size = Size(1200, 900);

const _threePeople = [
  ConstellationPerson(id: 'a', displayName: 'Ann'),
  ConstellationPerson(id: 'b', displayName: 'Bob'),
  ConstellationPerson(id: 'c', displayName: 'Cat'),
];

final _ann = ConstellationAnchorTarget.person('a');
final _bob = ConstellationAnchorTarget.person('b');
final _cat = ConstellationAnchorTarget.person('c');
final _postA = ConstellationAnchorTarget.beacon('post-a');
final _postB = ConstellationAnchorTarget.beacon('post-b');

typedef _Harness = ({
  _Server server,
  ConstellationCubit cubit,
  ConstellationSelectionCubit selection,
});

Future<_Harness> _mount(
  WidgetTester tester, {
  List<ConstellationPerson> people = _threePeople,
  Map<ConstellationAnchorTarget, (double, double)> seeded = const {},
}) async {
  final server = _Server(seeded);
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _Fields(server, people),
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
    logger: Logger('ConstellationGroupDragTest'),
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

Offset _scene(ConstellationCubit cubit, String personId) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(
    'fp:$personId',
  );
  expect(point, isNotNull, reason: '$personId must be laid out');
  return Offset(point!.x, point.y);
}

Offset _beacon(ConstellationCubit cubit, String beaconId) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(
    'fr:$beaconId',
  );
  expect(point, isNotNull, reason: '$beaconId must be laid out');
  return Offset(point!.x, point.y);
}

/// Scene centre of a written position.
Offset _written(ConstellationAnchorApplyOp op) => Offset(
  _centre + op.position!.xUnits * _unit,
  _centre + op.position!.yUnits * _unit,
);

/// Presses [from], moves to [to] in eight steps and returns the gesture
/// still held.
Future<TestGesture> _press(
  WidgetTester tester,
  Offset from,
  Offset to, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final gesture = await tester.startGesture(from, kind: kind);
  await _frames(tester);
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

void expectOffset(Offset actual, Offset expected, {String? reason}) {
  expect(actual.dx, closeTo(expected.dx, 0.5), reason: reason);
  expect(actual.dy, closeTo(expected.dy, 0.5), reason: reason);
}

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('${kind.name}: dragging a selected node moves the rest of '
        'the selection with it live, and the drop writes them in one batch', (
      tester,
    ) async {
      final h = await _mount(tester);
      h.selection
        ..toggle(_ann)
        ..toggle(_bob);
      await _frames(tester);
      final annStart = _scene(h.cubit, 'a');
      final bobStart = _scene(h.cubit, 'b');
      final catStart = _scene(h.cubit, 'c');
      final bobScreenStart = tester.getCenter(_node('b'));
      final ann = tester.getCenter(_node('a'));

      final gesture = await _press(
        tester,
        ann,
        ann + const Offset(90, 60),
        kind: kind,
      );

      // Live, before the drop: Bob has moved by Ann's own delta.
      final delta = _scene(h.cubit, 'a') - annStart;
      expect(delta.distance, greaterThan(40));
      expectOffset(_scene(h.cubit, 'b'), bobStart + delta);
      expectOffset(_scene(h.cubit, 'c'), catStart, reason: 'not selected');
      expect(
        tester.getCenter(_node('b')),
        isNot(bobScreenStart),
        reason: 'the widget follows on screen',
      );
      expect(h.server.applies, isEmpty, reason: 'nothing written mid-drag');

      await gesture.up();
      await _frames(tester);
      await _flushWrites(tester);

      expect(h.server.applies, hasLength(1), reason: 'one batch');
      final ops = {for (final op in h.server.applies.single) op.target: op};
      expect(ops.keys, unorderedEquals([_ann, _bob]));
      expect(
        ops.values.map((op) => op.kind),
        everyElement(ConstellationAnchorOpKind.upsert),
      );
      final annMoved = _written(ops[_ann]!) - annStart;
      expectOffset(_written(ops[_bob]!) - bobStart, annMoved);
      expect(h.selection.state.targets, {_ann, _bob}, reason: 'kept');
      expect(h.cubit.isAnchored(_bob), isTrue);
    });
  }

  testWidgets('dragging a node outside the selection moves it alone and '
      'leaves the selection as it was', (tester) async {
    final h = await _mount(tester);
    h.selection
      ..toggle(_ann)
      ..toggle(_bob);
    await _frames(tester);
    final annStart = _scene(h.cubit, 'a');
    final bobStart = _scene(h.cubit, 'b');
    final cat = tester.getCenter(_node('c'));

    final gesture = await _press(tester, cat, cat + const Offset(-70, 50));
    expectOffset(_scene(h.cubit, 'a'), annStart);
    expectOffset(_scene(h.cubit, 'b'), bobStart);
    await gesture.up();
    await _frames(tester);
    await _flushWrites(tester);

    expect(h.server.applies, hasLength(1));
    expect(h.server.applies.single.map((op) => op.target), [_cat]);
    expect(h.selection.state.targets, {_ann, _bob});
  });

  testWidgets('Escape during a group drag puts every node back and writes '
      'nothing', (tester) async {
    final h = await _mount(tester);
    h.selection
      ..toggle(_ann)
      ..toggle(_bob);
    await _frames(tester);
    final annStart = _scene(h.cubit, 'a');
    final bobStart = _scene(h.cubit, 'b');
    final ann = tester.getCenter(_node('a'));

    final gesture = await _press(tester, ann, ann + const Offset(80, 80));
    expect((_scene(h.cubit, 'b') - bobStart).distance, greaterThan(40));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    expectOffset(_scene(h.cubit, 'a'), annStart);
    expectOffset(_scene(h.cubit, 'b'), bobStart);
    await gesture.up();
    await _frames(tester);
    await _flushWrites(tester);

    expect(h.server.applies, isEmpty);
    expect(h.selection.state.targets, {_ann, _bob}, reason: 'kept');
  });

  testWidgets('a lost pointer during a group drag puts every node back', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.selection
      ..toggle(_ann)
      ..toggle(_bob);
    await _frames(tester);
    final annStart = _scene(h.cubit, 'a');
    final bobStart = _scene(h.cubit, 'b');
    final ann = tester.getCenter(_node('a'));

    final gesture = await _press(
      tester,
      ann,
      ann + const Offset(80, -60),
      kind: PointerDeviceKind.touch,
    );
    await gesture.cancel();
    await _frames(tester);
    await _flushWrites(tester);

    expectOffset(_scene(h.cubit, 'a'), annStart);
    expectOffset(_scene(h.cubit, 'b'), bobStart);
    expect(h.server.applies, isEmpty);
  });

  testWidgets('the group stops as one when a member reaches the envelope '
      'edge, keeping its shape', (tester) async {
    // Bob is pinned 0.3 units inside the right edge; Ann near the middle.
    final h = await _mount(
      tester,
      seeded: {_ann: (1, 0), _bob: (9.7, 2)},
    );
    h.selection
      ..toggle(_ann)
      ..toggle(_bob);
    await _frames(tester);
    final annStart = _scene(h.cubit, 'a');
    final bobStart = _scene(h.cubit, 'b');
    expect(bobStart.dx, closeTo(_centre + 9.7 * _unit, 1));

    final group = h.selection.state.dragGroupFor(_ann);
    h.cubit.beginDragExisting(target: _ann, group: group);
    final annNode = h.cubit.graphController.nodePayloadForId('fp:a')!;
    final proposed = annStart + const Offset(400, -120);
    final clamped = h.cubit.clampClusterDragPosition(annNode, proposed);
    h.cubit.updateDragPresentation(nodeId: 'fp:a', sceneCentre: clamped);
    await _frames(tester);

    final delta = clamped - annStart;
    // Bob's centre had 0.3 units (51 px) to go; Ann alone had far more.
    expect(delta.dx, closeTo(0.3 * _unit, 0.5));
    expect(delta.dy, closeTo(-120, 0.5), reason: 'slides along the wall');
    expectOffset(_scene(h.cubit, 'b') - bobStart, delta, reason: 'rigid');

    await h.cubit.onExistingNodeDrop(target: _ann, sceneCentre: proposed);
    await _flushWrites(tester);
    final ops = {for (final op in h.server.applies.single) op.target: op};
    expectOffset(_written(ops[_ann]!) - annStart, delta);
    expectOffset(_written(ops[_bob]!) - bobStart, delta);
    expect(ops[_bob]!.position!.xUnits, lessThanOrEqualTo(10));
  });

  testWidgets('a member that starts outside the envelope is not written and '
      'stays put, without holding the group back; pinned Posts follow their '
      'own author', (tester) async {
    // Bob is pinned 0.6 units past the right edge (on the canvas, outside
    // the envelope a position can be stored in), as an old row can be.
    // Ann and Bob each have a pinned Post; Cat is pinned in the middle.
    final h = await _mount(
      tester,
      seeded: {
        _ann: (1, 0),
        _bob: (10.6, 1),
        _cat: (-1, 1.5),
        _postA: (2, 1),
        _postB: (9.5, 2),
      },
    );
    h.selection
      ..toggle(_ann)
      ..toggle(_bob)
      ..toggle(_cat);
    await _frames(tester);
    final annStart = _scene(h.cubit, 'a');
    final bobStart = _scene(h.cubit, 'b');
    final catStart = _scene(h.cubit, 'c');
    final postAStart = _beacon(h.cubit, 'post-a');
    final postBStart = _beacon(h.cubit, 'post-b');
    expect(
      bobStart.dx,
      closeTo(_centre + 10.6 * _unit, 1),
      reason: 'Bob must be laid out outside the envelope',
    );

    h.cubit.beginDragExisting(
      target: _ann,
      group: h.selection.state.dragGroupFor(_ann),
    );
    final annNode = h.cubit.graphController.nodePayloadForId('fp:a')!;
    // Not enough to the left to bring Bob back inside.
    final proposed = annStart + const Offset(-60, 50);
    final clamped = h.cubit.clampClusterDragPosition(annNode, proposed);
    h.cubit.updateDragPresentation(nodeId: 'fp:a', sceneCentre: clamped);
    await _frames(tester);

    // Live: the rest of the group moves the whole way; Bob does not hold it.
    final delta = clamped - annStart;
    expectOffset(delta, const Offset(-60, 50), reason: 'not held back');
    expectOffset(_scene(h.cubit, 'c') - catStart, delta, reason: 'rigid');
    expectOffset(_scene(h.cubit, 'b'), bobStart, reason: 'Bob stays');
    expectOffset(
      _beacon(h.cubit, 'post-a') - postAStart,
      delta,
      reason: "Ann's Post follows Ann",
    );
    expectOffset(
      _beacon(h.cubit, 'post-b'),
      postBStart,
      reason: "Bob's Post follows Bob, not the grabbed node",
    );

    await h.cubit.onExistingNodeDrop(target: _ann, sceneCentre: proposed);
    await _flushWrites(tester);

    // One batch, every position in range (the fake server checks that).
    expect(h.server.applies, hasLength(1));
    final ops = {for (final op in h.server.applies.single) op.target: op};
    expect(ops.keys, isNot(contains(_bob)), reason: 'Bob is not written');
    expect(ops.keys, containsAll([_ann, _cat, _postA]));
    expectOffset(_written(ops[_ann]!) - annStart, delta);
    expectOffset(_written(ops[_cat]!) - catStart, delta);
    expectOffset(_written(ops[_postA]!) - postAStart, delta);
    if (ops[_postB] case final postB?) {
      expectOffset(_written(postB), postBStart, reason: 'Bob did not move');
    }

    // Bob is back where he was, his stored row untouched.
    expectOffset(_scene(h.cubit, 'b'), bobStart, reason: 'snaps back');
    expect(h.server.anchors[_bob]!.position.xUnits, 10.6);
    expectOffset(_beacon(h.cubit, 'post-b'), postBStart);
  });
}
