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
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
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

// Field multi-select (#642): the rubber-band box is the main tool — with the
// select tool on a one-finger or mouse drag on empty map draws it and two
// fingers move the map; Shift-drag draws it any time. Taps toggle nodes with
// the tool on or with Shift/Ctrl/Cmd held; dragging a node still moves it.
// «Arrange in a sector» (#644) writes the selected people as one batch of
// user placements based on the anchor revision the user sees.

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

const _people = [
  ConstellationPerson(id: 'a', displayName: 'Ann'),
  ConstellationPerson(id: 'b', displayName: 'Bob'),
];

/// The anchor store of the server: applies batches, rejects a write based
/// on a revision older than the last reset, and resets.
final class _Server implements ConstellationAnchorRepositoryPort {
  int revision = 7;
  int resetWatermark = 0;
  final anchors = <ConstellationAnchorTarget, ConstellationAnchor>{};
  final applies = <List<ConstellationAnchorApplyOp>>[];

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) async {
    applies.add(List.of(ops));
    final before = revision;
    final results = <ConstellationAnchorOpResult>[];
    for (final op in ops) {
      final base = op.baseRevision;
      if (base != null && base.compareTo(_revision(resetWatermark)) < 0) {
        results.add(
          ConstellationAnchorOpResult(
            clientOpId: op.clientOpId,
            status: ConstellationAnchorOpStatus.rejected,
            reason: 'reset',
            target: op.target,
          ),
        );
        continue;
      }
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
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
  }) async {
    final before = revision;
    final cleared = anchors.length;
    anchors.clear();
    revision++;
    resetWatermark = revision;
    return ConstellationAnchorResetResult(
      beforeRevision: _revision(before),
      afterRevision: _revision(revision),
      clearedCount: cleared,
    );
  }
}

/// A FULL read of the field, with whatever the server has stored.
final class _Fields implements ConstellationRepositoryPort {
  _Fields(this.server);

  final _Server server;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 22),
    context: '',
    peers: _people,
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
    ],
    posts: [
      for (final person in _people)
        ConstellationPost(
          id: 'post-${person.id}',
          authorId: person.id,
          rootExcerpt: 'Hello',
          lastActivityAt: DateTime.utc(2026, 10, 22),
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

final class _Harness {
  _Harness({
    required this.server,
    required this.store,
    required this.cubit,
    required this.selection,
  });

  final _Server server;
  final ConstellationFieldStoreCase store;
  final ConstellationCubit cubit;
  final ConstellationSelectionCubit selection;

  Set<ConstellationAnchorTarget> get selected => selection.state.targets;
}

Future<_Harness> _mount(WidgetTester tester) async {
  final server = _Server();
  final sync = buildTestRealtimeSync();
  final store = ConstellationStoreFixture(
    _Fields(server),
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
    logger: Logger('ConstellationMultiSelectTest'),
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
  return _Harness(
    server: server,
    store: store,
    cubit: cubit,
    selection: selection,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Two frames: a cubit emission reaches its BlocBuilder in the first.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

final _ann = ConstellationAnchorTarget.person('a');
final _bob = ConstellationAnchorTarget.person('b');

/// A point on empty map well clear of every node, up-left of all of them.
Offset _emptyCorner(WidgetTester tester) {
  final centres = [
    for (final id in ['a', 'b', 'ego', 'post-a', 'post-b'])
      if (_node(id).evaluate().isNotEmpty) tester.getCenter(_node(id)),
  ];
  final left = centres.map((c) => c.dx).reduce((a, b) => a < b ? a : b);
  final top = centres.map((c) => c.dy).reduce((a, b) => a < b ? a : b);
  return Offset(left - 120, top - 120);
}

/// Bottom-right of every node, on empty map.
Offset _farCorner(WidgetTester tester) {
  final centres = [
    for (final id in ['a', 'b', 'ego', 'post-a', 'post-b'])
      if (_node(id).evaluate().isNotEmpty) tester.getCenter(_node(id)),
  ];
  final right = centres.map((c) => c.dx).reduce((a, b) => a > b ? a : b);
  final bottom = centres.map((c) => c.dy).reduce((a, b) => a > b ? a : b);
  return Offset(right + 120, bottom + 120);
}

Future<void> _drag(
  WidgetTester tester,
  Offset from,
  Offset to, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final gesture = await tester.startGesture(
    from,
    kind: kind,
  );
  await _frames(tester);
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await _frames(tester);
}

void main() {
  testWidgets('with the select tool on, a mouse drag on empty map draws a '
      'box that selects what it covers, and the map does not pan', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    final annBefore = tester.getCenter(_node('a'));
    final from = _emptyCorner(tester);
    final to = _farCorner(tester);

    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await _frames(tester);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The rectangle is drawn while dragging.
    final box = find.byKey(const Key('constellation.selection.box_rect'));
    expect(tester.widget<CustomPaint>(box).painter, isNotNull);
    await gesture.up();
    await _frames(tester);

    expect(h.selected, containsAll([_ann, _bob]));
    expect(
      h.selected,
      isNot(contains(ConstellationAnchorTarget.person('ego'))),
    );
    expect(tester.getCenter(_node('a')), annBefore, reason: 'no pan');
    expect(tester.widget<CustomPaint>(box).painter, isNull);
    expect(find.text('${h.selected.length} selected'), findsOneWidget);
    expect(
      find.byKey(const Key('constellation.selection.rings')),
      findsOneWidget,
    );
  });

  testWidgets('a plain drag on empty map still pans with the tool off', (
    tester,
  ) async {
    final h = await _mount(tester);
    final annBefore = tester.getCenter(_node('a'));
    final from = _emptyCorner(tester);

    await _drag(tester, from, from + const Offset(150, 90));
    await _settle(tester);

    expect(h.selected, isEmpty);
    expect(tester.getCenter(_node('a')), isNot(annBefore));
  });

  testWidgets('Shift-drag draws a box any time; Ctrl-drag toggles', (
    tester,
  ) async {
    final h = await _mount(tester);
    final from = _emptyCorner(tester);
    final to = _farCorner(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _drag(tester, from, to);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(h.selected, containsAll([_ann, _bob]));
    expect(h.selection.state.selecting, isFalse);

    // Ctrl-drag over Ann alone flips her out. The box must start on empty
    // map, so Shift (which lets it start with the tool off) is held too.
    final ann = tester.getCenter(_node('a'));
    final annBox = tester.getRect(_node('a')).inflate(4);
    final start = Offset(annBox.left - 40, ann.dy);
    h.selection.setSelecting(true);
    await _frames(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await _drag(tester, start, Offset(annBox.right, annBox.bottom));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(h.selected, isNot(contains(_ann)));
    expect(h.selected, contains(_bob));
  });

  testWidgets('touch: one finger draws a box, two fingers move the map', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    final from = _emptyCorner(tester);
    final annBefore = tester.getCenter(_node('a'));

    final first = await tester.startGesture(from);
    final second = await tester.startGesture(from + const Offset(0, 60));
    await _frames(tester);
    for (var i = 1; i <= 8; i++) {
      await first.moveTo(from + Offset(20.0 * i, 10.0 * i));
      await second.moveTo(from + Offset(20.0 * i, 60 + 10.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await _settle(tester);

    expect(h.selected, isEmpty, reason: 'two fingers never draw a box');
    final moved = tester.getCenter(_node('a')) - annBefore;
    // The touch slop is not part of the pan.
    expect(moved.dx, greaterThan(120));
    expect(moved.dy, greaterThan(50));

    await _drag(
      tester,
      _emptyCorner(tester),
      _farCorner(tester),
      kind: PointerDeviceKind.touch,
    );
    expect(h.selected, containsAll([_ann, _bob]));
  });

  testWidgets('with the tool on a tap toggles a node and opens nothing', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);

    await tester.tap(_node('a'));
    await _frames(tester);
    expect(h.selected, {_ann});
    expect(h.cubit.state.selectedPersonId, isNull);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(_node('a'));
    await _frames(tester);
    expect(h.selected, isEmpty);
    expect(
      find.text(
        'Draw a box or tap people, Requests and Posts. '
        'Move the map with two fingers.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('with the tool off a plain tap opens the person; Shift-, '
      'Ctrl- and Cmd-click toggle instead', (tester) async {
    final h = await _mount(tester);

    await tester.tap(_node('a'));
    await _frames(tester);
    expect(h.cubit.state.selectedPersonId, 'a');
    expect(h.selected, isEmpty);
    h.cubit.selectPerson(null);
    await _frames(tester);

    for (final key in [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(key);
      await tester.tap(_node('b'));
      await tester.sendKeyUpEvent(key);
      await _frames(tester);
      expect(h.selected, {_bob}, reason: '$key adds');
      await tester.sendKeyDownEvent(key);
      await tester.tap(_node('b'));
      await tester.sendKeyUpEvent(key);
      await _frames(tester);
      expect(h.selected, isEmpty, reason: '$key removes');
    }
    expect(h.cubit.state.selectedPersonId, isNull);
  });

  testWidgets('«Done» keeps the selection, «Clear selection» empties it and '
      'Escape steps back', (tester) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    await tester.tap(_node('a'));
    await _frames(tester);

    await tester.tap(find.byKey(const Key('constellation.selection.done')));
    await _frames(tester);
    expect(h.selection.state.selecting, isFalse);
    expect(h.selected, {_ann});
    expect(find.byKey(const Key('constellation.selection.bar')), findsOne);

    await tester.tap(find.byKey(const Key('constellation.selection.clear')));
    await _frames(tester);
    expect(h.selection.state.isActive, isFalse);
    expect(find.byKey(const Key('constellation.selection.bar')), findsNothing);

    h.selection
      ..toggle(_ann)
      ..toggle(_bob);
    await _frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    expect(h.selection.state.isActive, isFalse);
  });

  testWidgets('dragging a node with the tool on still moves it', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    final ann = tester.getCenter(_node('a'));

    await _drag(tester, ann, ann + const Offset(60, 40));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(h.selected, isEmpty, reason: 'a node drag is not a box');
    expect(h.server.applies, hasLength(1));
    expect(h.server.applies.single.first.target, _ann);
  });

  group('box merge by pointer', () {
    /// A box around Bob alone, starting on empty map up-left of him.
    Future<void> boxBob(WidgetTester tester, PointerDeviceKind kind) async {
      final bob = tester.getRect(_node('b'));
      await _drag(
        tester,
        bob.topLeft - const Offset(30, 30),
        bob.bottomRight + const Offset(4, 4),
        kind: kind,
      );
    }

    testWidgets('a touch box adds to what is selected', (tester) async {
      final h = await _mount(tester);
      h.selection
        ..setSelecting(true)
        ..toggle(_ann);
      await _frames(tester);

      await boxBob(tester, PointerDeviceKind.touch);

      expect(h.selected, containsAll([_ann, _bob]));
    });

    testWidgets('a plain mouse box replaces it', (tester) async {
      final h = await _mount(tester);
      h.selection
        ..setSelecting(true)
        ..toggle(_ann);
      await _frames(tester);

      await boxBob(tester, PointerDeviceKind.mouse);

      expect(h.selected, contains(_bob));
      expect(h.selected, isNot(contains(_ann)));
    });
  });

  testWidgets('a second finger joining a box turns it into a pan; the box '
      'is not applied, now or when a finger lifts', (tester) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    final from = _emptyCorner(tester);
    final to = _farCorner(tester);

    final first = await tester.startGesture(from);
    for (var i = 1; i <= 8; i++) {
      await first.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final second = await tester.startGesture(to + const Offset(0, -40));
    await tester.pump();
    final box = find.byKey(const Key('constellation.selection.box_rect'));
    expect(tester.widget<CustomPaint>(box).painter, isNull);
    expect(h.selected, isEmpty);
    await second.moveTo(to + const Offset(30, -10));
    await first.moveTo(to + const Offset(30, 30));
    await tester.pump(const Duration(milliseconds: 16));
    await second.up();
    await tester.pump();
    // The finger left behind keeps moving: still no box.
    await first.moveTo(to + const Offset(-80, -60));
    await tester.pump(const Duration(milliseconds: 16));
    await first.up();
    await _frames(tester);

    expect(h.selected, isEmpty);
  });

  testWidgets('a pinch that starts on a node stays with the map', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    final ann = tester.getCenter(_node('a'));
    final empty = _emptyCorner(tester);

    final first = await tester.startGesture(ann);
    final second = await tester.startGesture(empty);
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await second.moveTo(empty + Offset(-10.0 * i, -10.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final box = find.byKey(const Key('constellation.selection.box_rect'));
    expect(tester.widget<CustomPaint>(box).painter, isNull);
    await second.up();
    await first.up();
    await _frames(tester);

    expect(h.selected, isEmpty);
  });

  testWidgets('with the tool on a tap on a name label toggles its person', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    final label = find.text('Ann');
    expect(label, findsWidgets);
    final node = tester.getRect(_node('a'));
    final at = tester.getCenter(label.first);
    expect(node.contains(at), isFalse, reason: 'the label is off the node');

    await tester.tapAt(at);
    await _frames(tester);

    expect(h.selected, {_ann});
  });

  testWidgets('a change of account clears the selection', (tester) async {
    final h = await _mount(tester);
    h.selection
      ..setSelecting(true)
      ..toggle(_ann);
    await _frames(tester);

    await tester.runAsync(h.cubit.onAccountChanged);
    await _frames(tester);

    expect(h.selection.state.isActive, isFalse);
  });

  group('«Arrange in a sector»', () {
    Future<void> arrange(WidgetTester tester, _Harness h) async {
      h.selection
        ..toggle(_ann)
        ..toggle(_bob);
      await _frames(tester);
      await tester.tap(
        find.byKey(const Key('constellation.selection.arrange')),
      );
      await _frames(tester);
      expect(h.selection.state.sector, isNotNull);
      expect(
        find.byKey(const Key('constellation.selection.sector_aim')),
        findsOneWidget,
      );
      // Point the sector straight down from the viewer.
      final ego = tester.getCenter(_node('ego'));
      await tester.tapAt(ego + const Offset(0, 200));
      await _frames(tester);
      expect(h.selection.state.sector!.direction, closeTo(1.5708, 1e-3));
      await tester.tap(
        find.byKey(const Key('constellation.selection.sector_apply')),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
    }

    testWidgets('is offered for two or more people only', (tester) async {
      final h = await _mount(tester);
      h.selection.toggle(_ann);
      await _frames(tester);
      final button = find.byKey(const Key('constellation.selection.arrange'));
      expect(tester.widget<TextButton>(button).onPressed, isNull);

      h.selection.toggle(_bob);
      await _frames(tester);
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    });

    testWidgets('writes the people as one batch based on the revision the '
        'user sees, and they stay placed after a reload', (tester) async {
      final h = await _mount(tester);

      await arrange(tester, h);

      expect(h.server.applies, hasLength(1), reason: 'one batch');
      final ops = h.server.applies.single;
      expect(ops.map((op) => op.target), unorderedEquals([_ann, _bob]));
      for (final op in ops) {
        expect(op.kind, ConstellationAnchorOpKind.upsert);
        expect(op.baseRevision, _revision(7));
      }
      // Below the viewer: both land in the lower half (scene y grows down).
      for (final op in ops) {
        expect(op.position!.yUnits, greaterThan(0));
      }
      expect(h.selection.state.sector, isNull);
      expect(h.selected, {_ann, _bob}, reason: 'the selection stays');

      await tester.runAsync(
        () => h.store.requestRefresh(ConstellationRefreshReason.load),
      );
      await _settle(tester);
      final projection = h.store.current.field!.resolvedAnchorProjection;
      expect(
        projection.anchors.map((anchor) => anchor.target),
        unorderedEquals([_ann, _bob]),
      );
      expect(h.cubit.isAnchored(_ann), isTrue);
      expect(h.cubit.isAnchored(_bob), isTrue);
    });

    testWidgets('is rejected when a reset happened after the revision it '
        'is based on', (tester) async {
      final h = await _mount(tester);
      // Another device reset the positions; this one has not heard yet.
      h.server.resetWatermark = 9;

      await arrange(tester, h);

      expect(h.server.applies, hasLength(1));
      expect(h.server.anchors, isEmpty);
      final projection = h.store.current.field!.resolvedAnchorProjection;
      expect(projection.anchors, isEmpty);
    });

    testWidgets('«Сбросить позиции» undoes it', (tester) async {
      final h = await _mount(tester);
      await arrange(tester, h);
      expect(h.server.anchors, hasLength(2));

      await tester.runAsync(h.cubit.resetAllPositions);
      await _settle(tester);

      expect(h.server.anchors, isEmpty);
      expect(h.cubit.isAnchored(_ann), isFalse);
      expect(h.cubit.isAnchored(_bob), isFalse);
    });

    testWidgets('Cancel leaves everyone where they are', (tester) async {
      final h = await _mount(tester);
      h.selection
        ..toggle(_ann)
        ..toggle(_bob);
      await _frames(tester);
      await tester.tap(
        find.byKey(const Key('constellation.selection.arrange')),
      );
      await _frames(tester);
      await tester.tap(
        find.byKey(const Key('constellation.selection.sector_cancel')),
      );
      await _settle(tester);

      expect(h.selection.state.sector, isNull);
      expect(h.server.applies, isEmpty);
    });
  });
}
