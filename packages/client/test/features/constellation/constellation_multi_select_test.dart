import 'dart:async';
import 'dart:math' as math;

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
import 'package:tentura/features/constellation/domain/constellation_sector_arrangement.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/ui/util/layout_geometry_adapters.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_graph_scene.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_selection_layers.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// Field multi-select (#642): the rubber-band box is the main tool — with the
// select tool on a one-finger or mouse drag on empty map draws it and two
// fingers move the map; Shift-drag draws it any time. Taps toggle nodes with
// the tool on or with Shift/Ctrl/Cmd held; dragging a node still moves it.
// «Arrange in a sector» (#644): the centre, radius, edges and direction are
// dragged on the map over a preview, and Apply writes the selected people,
// Requests and Posts as user placements based on the anchor revision the
// user sees.

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

/// One stored-position unit in scene pixels.
const _unitPixels = kConstellationRingUnitPixels;

const _people = [
  ConstellationPerson(id: 'a', displayName: 'Ann'),
  ConstellationPerson(id: 'b', displayName: 'Bob'),
];

/// The anchor store of the server: applies batches, rejects a write based
/// on a revision older than the last reset or with a position out of range,
/// and resets.
final class _Server implements ConstellationAnchorRepositoryPort {
  int revision = 7;

  /// Requests on the field (none unless a test adds them).
  final requests = <ConstellationRequest>[];
  int resetWatermark = 0;
  final anchors = <ConstellationAnchorTarget, ConstellationAnchor>{};
  final applies = <List<ConstellationAnchorApplyOp>>[];

  /// Targets whose written position the server refused as out of range.
  final outOfRange = <ConstellationAnchorTarget>[];

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
      final position = op.position!;
      if (ConstellationAnchorPosition.validate(
            xUnits: position.xUnits,
            yUnits: position.yUnits,
            coordinateSpaceVersion: position.coordinateSpaceVersion,
          )
          is! ConstellationAnchorPositionValid) {
        outOfRange.add(op.target);
        results.add(
          ConstellationAnchorOpResult(
            clientOpId: op.clientOpId,
            status: ConstellationAnchorOpStatus.rejected,
            reason: 'out of range',
            target: op.target,
          ),
        );
        continue;
      }
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
    requests: List.of(server.requests),
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
      pinnedRequests: [
        for (final request in server.requests)
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

Future<_Harness> _mount(
  WidgetTester tester, {
  void Function(_Server server)? seed,
}) async {
  final server = _Server();
  seed?.call(server);
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

  group('empty selection hint by pointer (#681)', () {
    final l10n = lookupL10n(const Locale('en'));

    String hint(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('constellation.selection.count')))
        .data!;

    Future<void> connectMouse(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      // Off the surface, so it hovers nothing (no tooltip timers).
      await mouse.addPointer(location: const Offset(-1, -1));
      addTearDown(mouse.removePointer);
    }

    testWidgets('with a mouse it says how to select with a mouse', (
      tester,
    ) async {
      await connectMouse(tester);
      final h = await _mount(tester);
      h.selection.setSelecting(true);
      await _frames(tester);

      expect(hint(tester), l10n.constellationSelectionHintMouse);
      expect(hint(tester), isNot(contains('two fingers')));
    });

    testWidgets('on touch it keeps the two-finger hint', (tester) async {
      final h = await _mount(tester);
      h.selection.setSelecting(true);
      await _frames(tester);

      expect(tester.binding.mouseTracker.mouseIsConnected, isFalse);
      expect(hint(tester), l10n.constellationSelectionHint);
    });

    testWidgets('follows a mouse plugged in or out while the bar is shown', (
      tester,
    ) async {
      final h = await _mount(tester);
      h.selection.setSelecting(true);
      await _frames(tester);
      expect(hint(tester), l10n.constellationSelectionHint);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      // Off the surface, so it hovers nothing (no tooltip timers).
      await mouse.addPointer(location: const Offset(-1, -1));
      await _frames(tester);
      expect(hint(tester), l10n.constellationSelectionHintMouse);

      await mouse.removePointer();
      await _frames(tester);
      expect(hint(tester), l10n.constellationSelectionHint);
    });
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

  testWidgets('lifting one finger of a two-finger pan keeps moving the map '
      'with the other, without a jump', (tester) async {
    final h = await _mount(tester);
    h.selection.setSelecting(true);
    await _frames(tester);
    final from = _emptyCorner(tester);

    final first = await tester.startGesture(from);
    final second = await tester.startGesture(from + const Offset(0, 80));
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await first.moveTo(from + Offset(10.0 * i, 0));
      await second.moveTo(from + Offset(10.0 * i, 80));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await second.up();
    await tester.pump();
    final annBefore = tester.getCenter(_node('a'));
    for (var i = 1; i <= 5; i++) {
      await first.moveTo(from + Offset(60 + 20.0 * i, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await _frames(tester);

    expect(h.selected, isEmpty);
    final moved = tester.getCenter(_node('a')) - annBefore;
    expect(moved.dx, closeTo(100, 1));
    expect(moved.dy, closeTo(0, 1));
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
    final postA = ConstellationAnchorTarget.beacon('post-a');
    final postB = ConstellationAnchorTarget.beacon('post-b');

    Finder handle(String name) => find.byKey(Key('constellation.sector.$name'));

    /// Selects [targets], opens the sector editor and points it up, clear of
    /// the bar at the bottom.
    Future<void> open(
      WidgetTester tester,
      _Harness h,
      Iterable<ConstellationAnchorTarget> targets,
    ) async {
      h.selection.addAll(targets);
      await _frames(tester);
      await tester.tap(
        find.byKey(const Key('constellation.selection.arrange')),
      );
      await _frames(tester);
      expect(h.selection.state.sector, isNotNull);
      expect(
        find.byKey(const Key('constellation.selection.sector_editor')),
        findsOneWidget,
      );
      h.selection.aimSector(direction: -math.pi / 2);
      await _frames(tester);
    }

    /// What the editor previews now, by anchor target.
    Map<ConstellationAnchorTarget, Offset> preview(
      WidgetTester tester,
      _Harness h,
    ) {
      final context = tester.element(
        find.byKey(const Key('constellation.selection.sector_editor')),
      );
      final items = constellationSectorItems(h.cubit, h.selection.state);
      final layout = constellationSectorPreview(
        selection: h.selection.state,
        items: items,
        minSpacing: constellationSectorSpacing(
          context,
          h.cubit,
          items.targets.values,
        ),
      )!;
      return {
        for (final MapEntry(key: graphId, value: point)
            in layout.targets.entries)
          items.targets[graphId]!: Offset(point.x, point.y),
      };
    }

    Future<void> apply(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const Key('constellation.selection.sector_apply')),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
    }

    /// [from] turned by [radians] around [centre].
    Offset turned(Offset from, Offset centre, double radians) {
      final offset = from - centre;
      return centre +
          Offset(
            offset.dx * math.cos(radians) - offset.dy * math.sin(radians),
            offset.dx * math.sin(radians) + offset.dy * math.cos(radians),
          );
    }

    Future<void> arc(
      WidgetTester tester,
      Offset from,
      Offset centre,
      double radians,
    ) async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await _frames(tester);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(turned(from, centre, radians * i / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await _frames(tester);
    }

    testWidgets('is offered for two or more nodes, people or not', (
      tester,
    ) async {
      final h = await _mount(tester);
      h.selection.toggle(_ann);
      await _frames(tester);
      final button = find.byKey(const Key('constellation.selection.arrange'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(Icons.pie_chart_outline),
        ),
        findsOneWidget,
        reason: 'the button shows a sector icon',
      );

      h.selection.toggle(postA);
      await _frames(tester);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('the button keeps its icon at phone width', (tester) async {
      final h = await _mount(tester);
      await tester.binding.setSurfaceSize(const Size(320, 640));
      h.selection.addAll([_ann, _bob]);
      await _frames(tester);
      final button = find.byKey(const Key('constellation.selection.arrange'));
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final icon = find.descendant(
        of: button,
        matching: find.byIcon(Icons.pie_chart_outline),
      );
      expect(icon, findsOneWidget);
      expect(tester.getRect(icon).right, lessThanOrEqualTo(320));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(40));
    });

    testWidgets('starts around the viewer, with a preview and every '
        'handle', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);

      final ego = tester.getCenter(_node('ego'));
      expect(
        tester.getCenter(handle('centre')),
        offsetMoreOrLessEquals(ego, epsilon: 1),
      );
      for (final name in ['radius', 'outer', 'start', 'end', 'direction']) {
        expect(handle(name), findsOneWidget, reason: name);
        final size = tester.getSize(handle(name));
        expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      }
      expect(find.byKey(const Key('constellation.sector.shape')), findsOne);
      expect(preview(tester, h).keys, unorderedEquals([_ann, _bob]));
      expect(h.server.applies, isEmpty, reason: 'nothing written yet');
      // The band starts as compact as holds them without overlaps.
      final sector = h.selection.state.sector!;
      final context = tester.element(
        find.byKey(const Key('constellation.selection.sector_editor')),
      );
      final items = constellationSectorItems(h.cubit, h.selection.state);
      expect(
        sector.outerRadius,
        closeTo(
          constellationSectorCompactOuterRadius(
            innerRadius: sector.radius,
            span: sector.span,
            count: 2,
            minSpacing: constellationSectorSpacing(
              context,
              h.cubit,
              items.targets.values,
            ),
          ),
          1e-9,
        ),
      );
    });

    testWidgets('dragging the centre handle moves the sector anywhere', (
      tester,
    ) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final before = h.selection.state.sector!;
      final scale = h.cubit.graphController.cameraScale;

      final from = tester.getCenter(handle('centre'));
      await _drag(tester, from, from + const Offset(120, 40));

      final after = h.selection.state.sector!;
      expect(after.centre.x - before.centre.x, closeTo(120 / scale, 2));
      expect(after.centre.y - before.centre.y, closeTo(40 / scale, 2));
      expect(after.radius, before.radius);
      expect(after.span, before.span);
      expect(
        tester.getCenter(handle('centre')),
        offsetMoreOrLessEquals(from + const Offset(120, 40), epsilon: 2),
      );
      for (final point in preview(tester, h).values) {
        expect(
          (point - after.centre.offset).distance,
          greaterThanOrEqualTo(after.radius - 1e-6),
        );
      }
    });

    testWidgets('dragging inside the sector moves it as well', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final before = h.selection.state.sector!;
      final centre = tester.getCenter(handle('centre'));
      // On the first ring, a quarter of the way from the middle line (where
      // the radius handles are) to the end edge.
      final inside = turned(
        tester.getCenter(handle('radius')),
        centre,
        before.span / 4,
      );

      await _drag(tester, inside, inside + const Offset(-50, 30));

      final after = h.selection.state.sector!;
      expect(after.centre, isNot(before.centre));
      expect(after.direction, closeTo(before.direction, 1e-9));
    });

    testWidgets('the inner arc handle changes the inner radius', (
      tester,
    ) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final before = h.selection.state.sector!;
      final scale = h.cubit.graphController.cameraScale;
      final centre = tester.getCenter(handle('centre'));
      final from = tester.getCenter(handle('radius'));
      final outward = (from - centre) / (from - centre).distance;

      await _drag(tester, from, from + outward * 90);

      final after = h.selection.state.sector!;
      expect(after.radius - before.radius, closeTo(90 / scale, 3));
      expect(after.centre, before.centre);
      for (final point in preview(tester, h).values) {
        expect(
          (point - after.centre.offset).distance,
          greaterThanOrEqualTo(after.radius - 1e-6),
        );
      }
    });

    testWidgets('the outer arc handle sets how far out the sector reaches, '
        'and the nodes spread over it', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final before = h.selection.state.sector!;
      final scale = h.cubit.graphController.cameraScale;
      final centre = tester.getCenter(handle('centre'));
      final from = tester.getCenter(handle('outer'));
      final outward = (from - centre) / (from - centre).distance;

      await _drag(tester, from, from + outward * 150);

      final after = h.selection.state.sector!;
      expect(after.outerRadius - before.outerRadius, closeTo(150 / scale, 3));
      expect(after.radius, before.radius, reason: 'the inner edge stays');
      expect(after.centre, before.centre);
      expect(
        tester.getCenter(handle('outer')),
        offsetMoreOrLessEquals(from + outward * 150, epsilon: 3),
        reason: 'the handle follows the pointer',
      );
      for (final point in preview(tester, h).values) {
        final distance = (point - after.centre.offset).distance;
        expect(distance, greaterThanOrEqualTo(after.radius - 1e-6));
        expect(distance, lessThanOrEqualTo(after.outerRadius + 1e-6));
      }
    });

    testWidgets('the outer arc handle stops at the inner radius, however '
        'tight', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final centre = tester.getCenter(handle('centre'));
      // Widen the band first, then pull it all the way in.
      var from = tester.getCenter(handle('outer'));
      var outward = (from - centre) / (from - centre).distance;
      await _drag(tester, from, from + outward * 150);
      from = tester.getCenter(handle('outer'));
      outward = (from - centre) / (from - centre).distance;
      await _drag(tester, from, from - outward * 400);

      final after = h.selection.state.sector!;
      expect(after.outerRadius, after.radius, reason: 'one ring');
      for (final point in preview(tester, h).values) {
        expect(
          (point - after.centre.offset).distance,
          closeTo(after.radius, 1e-6),
        );
      }
    });

    testWidgets('the inner arc handle dragged past the outer one pushes it '
        'along', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final before = h.selection.state.sector!;
      final scale = h.cubit.graphController.cameraScale;
      final centre = tester.getCenter(handle('centre'));
      final from = tester.getCenter(handle('radius'));
      final outward = (from - centre) / (from - centre).distance;
      final push = (before.outerRadius - before.radius) * scale + 80;

      await _drag(tester, from, from + outward * push);

      final after = h.selection.state.sector!;
      expect(after.radius, greaterThan(before.outerRadius));
      expect(after.outerRadius, after.radius);
    });

    testWidgets('no two handles overlap, at any width or zoom', (
      tester,
    ) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final controller = h.cubit.graphController;
      final scales = <double>{};
      // As drawn, then zoomed out, then zoomed in (zoomBy multiplies).
      for (final zoom in [1.0, 0.25, 16.0]) {
        controller.zoomBy(zoom);
        await _frames(tester);
        scales.add(controller.cameraScale);
        for (final degrees in [15, 30, 90, 180, 270, 330, 345, 360]) {
          h.selection.aimSector(span: degrees * math.pi / 180);
          await _frames(tester);
          final names = [
            'centre',
            'radius',
            'outer',
            'direction',
            'end',
            if (degrees < 360) 'start',
          ];
          final at = {for (final name in names) name: handle(name)};
          for (final MapEntry(key: name, value: finder) in at.entries) {
            expect(finder, findsOneWidget, reason: name);
          }
          for (var i = 0; i < names.length; i++) {
            for (var j = i + 1; j < names.length; j++) {
              final a = tester.getCenter(at[names[i]]!);
              final b = tester.getCenter(at[names[j]]!);
              expect(
                (a - b).distance,
                greaterThanOrEqualTo(kMinInteractiveDimension - 1e-6),
                reason:
                    '${names[i]} and ${names[j]} at $degrees°, zoom '
                    '${controller.cameraScale}',
              );
            }
          }
        }
      }
      expect(scales, hasLength(3), reason: 'three zoom levels tried');
    });

    testWidgets('the edge handles set the width from either side and the '
        'direction handle turns it', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final centre = tester.getCenter(handle('centre'));

      var before = h.selection.state.sector!;
      await arc(tester, tester.getCenter(handle('end')), centre, 0.4);
      var after = h.selection.state.sector!;
      expect(after.span - before.span, closeTo(0.4, 0.03));
      expect(after.start, closeTo(before.start, 0.03));

      before = after;
      await arc(tester, tester.getCenter(handle('start')), centre, 0.3);
      after = h.selection.state.sector!;
      expect(before.span - after.span, closeTo(0.3, 0.03));
      expect(after.end, closeTo(before.end, 0.03));

      before = after;
      await arc(tester, tester.getCenter(handle('direction')), centre, -0.5);
      after = h.selection.state.sector!;
      expect(after.direction - before.direction, closeTo(-0.5, 0.03));
      expect(after.span, closeTo(before.span, 1e-9));
      for (final point in preview(tester, h).values) {
        final offset = point - after.centre.offset;
        final along =
            (math.atan2(offset.dy, offset.dx) - after.start) % (2 * math.pi);
        expect(along, lessThanOrEqualTo(after.span + 1e-9));
      }
    });

    testWidgets('near the whole circle each edge handle still moves its own '
        'edge', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      // Pointing down puts the seam at the top, clear of the bar.
      h.selection.aimSector(direction: math.pi / 2, span: 2 * math.pi - 0.3);
      await _frames(tester);
      final centre = tester.getCenter(handle('centre'));
      final before = h.selection.state.sector!;

      await arc(tester, tester.getCenter(handle('start')), centre, 0.2);

      final after = h.selection.state.sector!;
      expect(after.end, closeTo(before.end, 0.03), reason: 'end stays');
      expect(before.span - after.span, closeTo(0.2, 0.03));
    });

    testWidgets('a widened sector goes all the way round and stops there', (
      tester,
    ) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      // The end handle goes all the way round: keep the sector small and in
      // the middle of the map above the bar, whatever the bar's height, so
      // the handle is never under the bar where a press would miss it.
      final barTop = tester
          .getTopLeft(find.byKey(const Key('constellation.selection.bar')))
          .dy;
      final controller = h.cubit.graphController;
      final middle = Offset(_size.width / 2, barTop / 2);
      final sector = h.selection.state.sector!;
      h.selection.editSector(
        sector.copyWith(
          centre: controller.viewportLocalToScene(middle).lPoint,
          radius: 0,
          outerRadius: 0,
        ),
      );
      await _frames(tester);
      final centre = tester.getCenter(handle('centre'));

      // Well past the whole circle, in steps.
      for (var i = 0; i < 4; i++) {
        final from = tester.getCenter(handle('end'));
        expect(
          from.dy + kMinInteractiveDimension / 2,
          lessThan(barTop),
          reason: 'the test needs the end handle clear of the bar',
        );
        expect(from.dy, greaterThan(kMinInteractiveDimension / 2));
        await arc(tester, from, centre, 1.5);
      }

      expect(h.selection.state.sector!.isFullCircle, isTrue);
      expect(handle('start'), findsNothing, reason: 'one seam');
    });

    testWidgets('writes the people as one batch, where the preview showed, '
        'based on the revision the user sees; they stay after a reload', (
      tester,
    ) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final from = tester.getCenter(handle('centre'));
      await _drag(tester, from, from + const Offset(60, 80));
      final expected = preview(tester, h);

      await apply(tester);

      expect(h.server.applies, hasLength(1), reason: 'one batch');
      final ops = h.server.applies.single;
      expect(ops.map((op) => op.target), unorderedEquals([_ann, _bob]));
      for (final op in ops) {
        expect(op.kind, ConstellationAnchorOpKind.upsert);
        expect(op.baseRevision, _revision(7));
        final want = constellationPointToV1Anchor(
          expected[op.target]!.lPoint,
        );
        expect(op.position!.xUnits, closeTo(want.xUnits, 1e-9));
        expect(op.position!.yUnits, closeTo(want.yUnits, 1e-9));
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

    testWidgets('Posts arrange alone, and mixed with people', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [postA, postB]);
      expect(preview(tester, h).keys, unorderedEquals([postA, postB]));

      await apply(tester);

      expect(
        h.server.applies.single.map((op) => op.target),
        unorderedEquals([postA, postB]),
      );

      h.selection.clear();
      await open(tester, h, [_ann, postA, postB]);
      expect(preview(tester, h).keys, unorderedEquals([_ann, postA, postB]));
      await apply(tester);
      expect(
        h.server.applies.last.map((op) => op.target),
        unorderedEquals([_ann, postA, postB]),
      );
    });

    group('a pinned Request of an arranged person', () {
      final request = ConstellationAnchorTarget.beacon('req-a');

      void seed(_Server server) {
        server.requests.add(
          const ConstellationRequest(
            id: 'req-a',
            authorId: 'a',
            title: 'Help',
            status: 0,
          ),
        );
        server.anchors[request] = ConstellationAnchor(
          target: request,
          position: const ConstellationAnchorPosition(
            xUnits: 1.5,
            yUnits: 0.5,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
          revision: _revision(7),
          placedAt: DateTime.utc(2026, 10, 22),
        );
      }

      Offset drawnAt(_Harness h, ConstellationAnchorTarget target) {
        final point = h.cubit.graphController.renderSnapshot.resolvePosition(
          constellationGraphNodeIdForTarget(target),
        )!;
        return Offset(point.x, point.y);
      }

      Offset personAt(_Harness h, String id) {
        final point = h.cubit.graphController.renderSnapshot.resolvePosition(
          constellationGraphNodeIdForTarget(
            ConstellationAnchorTarget.person(id),
          ),
        )!;
        return Offset(point.x, point.y);
      }

      testWidgets('follows its author by the same move when it is not '
          'arranged itself', (tester) async {
        final h = await _mount(tester, seed: seed);
        expect(_node('req-a'), findsOneWidget);
        await open(tester, h, [_ann, _bob]);
        final expected = preview(tester, h);
        final delta = expected[_ann]! - personAt(h, 'a');
        final requestStart = drawnAt(h, request);

        await apply(tester);

        final ops = h.server.applies.single;
        expect(
          ops.map((op) => op.target),
          unorderedEquals([_ann, _bob, request]),
        );
        final op = ops.firstWhere((op) => op.target == request);
        final want = constellationPointToV1Anchor(
          (requestStart + delta).lPoint,
        );
        expect(op.position!.xUnits, closeTo(want.xUnits, 1e-6));
        expect(op.position!.yUnits, closeTo(want.yUnits, 1e-6));
      });

      testWidgets('goes to its own place when it is arranged with its '
          'author', (tester) async {
        final h = await _mount(tester, seed: seed);
        await open(tester, h, [_ann, request]);
        final expected = preview(tester, h);
        expect(expected.keys, unorderedEquals([_ann, request]));

        await apply(tester);

        final op = h.server.applies.single.firstWhere(
          (op) => op.target == request,
        );
        final want = constellationPointToV1Anchor(expected[request]!.lPoint);
        expect(op.position!.xUnits, closeTo(want.xUnits, 1e-9));
        expect(op.position!.yUnits, closeTo(want.yUnits, 1e-9));
      });
    });

    testWidgets('a selected node that is not on the map is left out, and '
        'the bar says so', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [
        _ann,
        _bob,
        ConstellationAnchorTarget.person('x'),
      ]);

      expect(preview(tester, h).keys, unorderedEquals([_ann, _bob]));
      expect(
        find.textContaining("1 selected item can't be placed"),
        findsOneWidget,
      );
      await apply(tester);
      expect(
        h.server.applies.single.map((op) => op.target),
        unorderedEquals([_ann, _bob]),
      );
    });

    testWidgets('places off the field can still be applied: the bar warns, '
        'and those nodes are written at the edge of the field', (
      tester,
    ) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final sector = h.selection.state.sector!;
      const envelopeLeft =
          kConstellationCanvasCentre +
          kConstellationCoordinateMinUnits * kConstellationRingUnitPixels;
      // Against the left edge of the stored-position envelope, pointing out.
      h.selection.editSector(
        sector.copyWith(
          centre: (x: envelopeLeft + 20, y: kConstellationCanvasCentre),
          direction: math.pi,
        ),
      );
      await _frames(tester);
      final expected = preview(tester, h);
      expect(
        expected.values.every((point) => point.dx < envelopeLeft),
        isTrue,
        reason: 'the test needs every place off the field',
      );

      final warning = find.byKey(
        const Key('constellation.selection.sector_off_field'),
      );
      expect(warning, findsOneWidget);
      expect(
        find.text(
          'Some places fall outside the field: those items will be placed '
          'at the edge of the field.',
        ),
        findsOneWidget,
      );
      final applyButton = find.byKey(
        const Key('constellation.selection.sector_apply'),
      );
      expect(tester.widget<FilledButton>(applyButton).onPressed, isNotNull);

      await apply(tester);

      expect(h.server.applies, hasLength(1), reason: 'one batch');
      expect(h.server.outOfRange, isEmpty, reason: 'nothing refused');
      final ops = h.server.applies.single;
      expect(ops.map((op) => op.target), unorderedEquals([_ann, _bob]));
      for (final op in ops) {
        final position = op.position!;
        expect(position.xUnits, greaterThan(kConstellationCoordinateMinUnits));
        expect(
          position.xUnits,
          closeTo(kConstellationCoordinateMinUnits, 2 / _unitPixels),
          reason: '${op.target} rests at the left edge',
        );
        // Only the axis that was off the field is moved.
        final want = constellationPointToV1Anchor(expected[op.target]!.lPoint);
        expect(position.yUnits, closeTo(want.yUnits, 1e-9));
      }
      expect(h.server.anchors.keys, unorderedEquals([_ann, _bob]));
      expect(h.selection.state.sector, isNull, reason: 'the editor closes');
    });

    testWidgets('is rejected when a reset happened after the revision it '
        'is based on', (tester) async {
      final h = await _mount(tester);
      // Another device reset the positions; this one has not heard yet.
      h.server.resetWatermark = 9;

      await open(tester, h, [_ann, _bob]);
      await apply(tester);

      expect(h.server.applies, hasLength(1));
      expect(h.server.anchors, isEmpty);
      final projection = h.store.current.field!.resolvedAnchorProjection;
      expect(projection.anchors, isEmpty);
    });

    testWidgets('«Сбросить позиции» undoes it', (tester) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      await apply(tester);
      expect(h.server.anchors, hasLength(2));

      await tester.runAsync(h.cubit.resetAllPositions);
      await _settle(tester);

      expect(h.server.anchors, isEmpty);
      expect(h.cubit.isAnchored(_ann), isFalse);
      expect(h.cubit.isAnchored(_bob), isFalse);
    });

    for (final how in ['Cancel', 'Escape']) {
      testWidgets('$how after editing leaves everyone where they are', (
        tester,
      ) async {
        final h = await _mount(tester);
        final annBefore = tester.getCenter(_node('a'));
        await open(tester, h, [_ann, _bob]);
        final from = tester.getCenter(handle('centre'));
        await _drag(tester, from, from + const Offset(80, 30));
        final radius = tester.getCenter(handle('radius'));
        await _drag(tester, radius, radius + const Offset(-40, -40));

        if (how == 'Cancel') {
          await tester.tap(
            find.byKey(const Key('constellation.selection.sector_cancel')),
          );
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await _settle(tester);

        expect(h.selection.state.sector, isNull);
        expect(h.selected, {_ann, _bob}, reason: 'the selection stays');
        expect(h.server.applies, isEmpty);
        expect(
          find.byKey(const Key('constellation.selection.sector_editor')),
          findsNothing,
        );
        expect(tester.getCenter(_node('a')), annBefore);
      });
    }

    testWidgets('two fingers still move the map while editing', (
      tester,
    ) async {
      final h = await _mount(tester);
      await open(tester, h, [_ann, _bob]);
      final before = h.selection.state.sector!;
      final annBefore = tester.getCenter(_node('a'));
      final from = _farCorner(tester);

      final first = await tester.startGesture(from);
      final second = await tester.startGesture(from + const Offset(0, 60));
      await _frames(tester);
      for (var i = 1; i <= 8; i++) {
        await first.moveTo(from + Offset(-15.0 * i, -5.0 * i));
        await second.moveTo(from + Offset(-15.0 * i, 60 - 5.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await first.up();
      await second.up();
      await _settle(tester);

      expect(h.selection.state.sector, before, reason: 'the sector stays');
      expect(tester.getCenter(_node('a')), isNot(annBefore));
    });
  });
}
