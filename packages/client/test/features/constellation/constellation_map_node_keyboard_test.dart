// Issue #391: Field map nodes must be reachable with Tab and activatable
// with Enter/Space, and expose a focusable semantics node (the web engine
// only gives a DOM node a tabindex when its semantics node is focusable).
// Tab walks the nodes in map reading order (not widget-tree order), and a
// node Tab lands on off screen is brought into view.
// Issue #680: Escape closes the person or Request panel, also right after a
// mouse click, and a click on an empty spot of the map clears the selection.
// Issue #678: a node's semantics rect is never smaller than a tap target.
// Issue #675: what the map paints stays under the chip row above it.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_selection_layers.dart'
    show ConstellationSelectionToggle;
import 'package:tentura/features/constellation/ui/widget/constellation_post_preview_sheet.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/web_default_shortcuts.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/people_tags_widget_harness.dart';

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
  void clearSelection() {
    emit(const GraphPersonContextState());
  }
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

const _ego = Profile(id: 'ego', displayName: 'Ego');

ConstellationField _field({bool withBob = false}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 9, 9),
  context: '',
  peers: [
    const ConstellationPerson(id: 'a', displayName: 'Ann'),
    if (withBob) const ConstellationPerson(id: 'b', displayName: 'Bob'),
  ],
  edges: [
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
    if (withBob)
      const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
  ],
  posts: [
    ConstellationPost(
      id: 'post-a',
      authorId: 'a',
      rootExcerpt: 'Anyone free Saturday?',
      lastActivityAt: DateTime.utc(2026, 9, 9),
    ),
    // The Field only draws content holders (and their path ancestors), so
    // Bob needs a post of his own to be on the map at all.
    if (withBob)
      ConstellationPost(
        id: 'post-b',
        authorId: 'b',
        rootExcerpt: 'Lunch?',
        lastActivityAt: DateTime.utc(2026, 9, 9),
      ),
  ],
);

Future<ConstellationCubit> _loadCubit({bool withBob = false}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(_field(withBob: withBob)),
      accountId: 'ego',
    ).store,
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

const _size = Size(1200, 900);

/// The composer the Field screen always provides, with no session running.
ConstellationComposerCubit _idleComposer() => ConstellationComposerCubit(
  positions: const {},
  eligible: const {},
  createCubitFactory: (kind) => BeaconCreateCubit(kind: kind),
  forwardCubitFactory: (beaconId) =>
      ForwardCubit(beaconId: beaconId, embedded: true),
);

Future<void> _pumpBody(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Map<ShortcutActivator, Intent>? shortcuts,
  ConstellationSelectionCubit? selection,
  ConstellationComposerCubit? composer,
  Widget? outside,
}) async {
  const size = _size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      shortcuts: shortcuts,
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _StubContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
              if (selection != null)
                BlocProvider<ConstellationSelectionCubit>.value(
                  value: selection,
                ),
              if (composer != null)
                BlocProvider<ConstellationComposerCubit>.value(
                  value: composer,
                ),
            ],
            child: outside == null
                ? ConstellationBody(
                    legendExpanded: false,
                    onToggleLegend: () {},
                  )
                : Column(
                    children: [
                      Material(child: outside),
                      Expanded(
                        child: ConstellationBody(
                          legendExpanded: false,
                          onToggleLegend: () {},
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _node(String id) => find.byKey(TestIds.key(TestIds.graphNode(id)));

bool _isAncestorOrSelf(Element ancestor, Element of) {
  if (ancestor == of) return true;
  var found = false;
  of.visitAncestorElements((e) {
    if (e == ancestor) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// True when the primary focus belongs to map node [id] alone: the focused
/// element wraps or sits inside that node, and does not also wrap any of the
/// [others] (so the body-level Focus that wraps the whole map never counts).
bool _focusIsOnNode(WidgetTester tester, String id, List<String> others) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  final target = tester.element(_node(id));
  final owns =
      _isAncestorOrSelf(focused, target) || _isAncestorOrSelf(target, focused);
  if (!owns) return false;
  for (final other in others) {
    if (_isAncestorOrSelf(focused, tester.element(_node(other)))) {
      return false;
    }
  }
  return true;
}

/// A mouse click (press and release, no movement) at [at].
Future<void> _click(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: at);
  await mouse.down(at);
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

/// A point on the map, away from every node and panel, that a pointer
/// there reaches the map itself (not a control drawn over it).
Offset _emptyMapPoint(WidgetTester tester, List<String> nodes) {
  final map = tester.getRect(find.byType(ConstellationViewportOverlay));
  // In select mode the box-select layer lies over the empty map and takes
  // its presses; that layer is the map too.
  final box = find.byKey(const Key('constellation.selection.box'));
  final targets = {
    tester.renderObject(find.byType(InteractiveViewer)),
    if (box.evaluate().isNotEmpty) tester.renderObject(box),
  };
  final centres = [
    for (final id in nodes)
      if (_node(id).evaluate().isNotEmpty) tester.getCenter(_node(id)),
  ];
  final covered = [
    for (final panel in [
      find.byType(GraphPersonContextPanel),
      find.byType(ConstellationPostPreviewSheet),
    ])
      if (panel.evaluate().isNotEmpty) tester.getRect(panel).inflate(24),
  ];
  for (var y = map.top + 40; y < map.bottom - 40; y += 30) {
    for (var x = map.left + 40; x < map.right - 40; x += 30) {
      final p = Offset(x, y);
      if (centres.any((c) => (c - p).distance < 200)) continue;
      if (covered.any((r) => r.contains(p))) continue;
      final hits = tester.hitTestOnBinding(p).path;
      if (hits.any((entry) => targets.contains(entry.target))) return p;
    }
  }
  fail('no empty spot of the map found');
}

/// Takes keyboard focus off the map, as on the web page before any click
/// (QA on #680: the next Tab landed on the first toolbar button).
Future<void> _focusOffMap(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  expect(_focusIsInBody(), isFalse, reason: 'test setup: focus off the map');
}

/// Presses Tab until map node [id] has focus; returns whether it ever did.
Future<bool> _tabTo(
  WidgetTester tester,
  String id,
  List<String> others,
) async {
  for (var i = 0; i < 60; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_focusIsOnNode(tester, id, others)) return true;
  }
  return false;
}

/// Which of [ids] holds primary focus right now, or null.
String? _focusedNodeOf(WidgetTester tester, List<String> ids) {
  for (final id in ids) {
    if (_focusIsOnNode(tester, id, [
      for (final other in ids)
        if (other != id) other,
    ])) {
      return id;
    }
  }
  return null;
}

/// Presses Tab until each of [ids] has held focus once (one full lap) and
/// returns them in the order Tab reached them, rotated to start at
/// [ids].first so where the walk began does not matter.
Future<List<String>> _tabOrderOf(WidgetTester tester, List<String> ids) async {
  final seen = <String>[];
  for (var i = 0; i < 80 && seen.length < ids.length; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final id = _focusedNodeOf(tester, ids);
    if (id != null && !seen.contains(id)) seen.add(id);
  }
  final start = seen.indexOf(ids.first);
  if (start < 0) return seen;
  return [...seen.sublist(start), ...seen.sublist(0, start)];
}

Offset _sceneOf(ConstellationCubit cubit, String graphId) {
  final point = cubit.graphController.renderSnapshot.resolvePosition(graphId);
  expect(point, isNotNull, reason: '$graphId must be laid out');
  return Offset(point!.x, point.y);
}

/// Pans (never zooms) so node [id] (scene id [graphId]) is centred at the
/// global point [target] (as in constellation_preview_reveals_node_test).
Future<void> _parkAtGlobal(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String id,
  required String graphId,
  required Offset target,
}) async {
  final controller = cubit.graphController;
  final gap =
      tester.getCenter(_node(id)) -
      controller.sceneToViewportLocal(_sceneOf(cubit, graphId));
  final wantedLocal = target - gap;
  final viewportCentre = controller.viewportSize!.center(Offset.zero);
  controller.jumpToPosition(
    _sceneOf(cubit, graphId) -
        (wantedLocal - viewportCentre) / controller.cameraScale,
  );
  await tester.pumpAndSettle();
  expect(
    (tester.getCenter(_node(id)) - target).distance,
    lessThan(1.5),
    reason: 'test setup must park $graphId at $target',
  );
}

/// Whether the primary focus sits inside the Field body (not lost to the
/// route or the app).
bool _focusIsInBody() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  var found = false;
  focused.visitAncestorElements((e) {
    if (e.widget is ConstellationBody) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// [node]'s rect in logical screen pixels. The semantics tree's root space
/// is physical pixels, so the walk to the root ends with a divide by the
/// device pixel ratio.
Rect _semanticsRectOnScreen(WidgetTester tester, SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    final transform = n.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  final ratio = tester.view.devicePixelRatio;
  return Rect.fromLTRB(
    rect.left / ratio,
    rect.top / ratio,
    rect.right / ratio,
    rect.bottom / ratio,
  );
}

/// The clip, in global coordinates, that the ancestors of [object] apply to
/// whatever it paints; null when nothing clips it.
Rect? _ancestorPaintClip(RenderObject object) {
  Rect? clip;
  var child = object;
  for (var parent = child.parent; parent != null; parent = parent.parent) {
    final local = parent.describeApproximatePaintClip(child);
    if (local != null) {
      final global = MatrixUtils.transformRect(
        parent.getTransformTo(null),
        local,
      );
      clip = clip == null ? global : clip.intersect(global);
    }
    child = parent;
  }
  return clip;
}

void main() {
  testWidgets('a Post node is reachable with Tab and opens with Enter', (
    tester,
  ) async {
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    await _pumpBody(tester, cubit);
    expect(_node('post-a'), findsOneWidget);
    expect(cubit.state.selectedRequestId, isNull);

    expect(
      await _tabTo(tester, 'post-a', const ['a']),
      isTrue,
      reason: 'Tab never moved focus onto the Post node',
    );
    expect(cubit.state.selectedRequestId, isNull, reason: 'focus alone');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(cubit.state.selectedRequestId, 'post-a');
    expect(cubit.state.selectedPersonId, isNull);
  });

  testWidgets('a person node is reachable with Tab and opens with Space', (
    tester,
  ) async {
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    await _pumpBody(tester, cubit);
    expect(_node('a'), findsOneWidget);
    expect(cubit.state.selectedPersonId, isNull);

    expect(
      await _tabTo(tester, 'a', const ['post-a']),
      isTrue,
      reason: 'Tab never moved focus onto the person node',
    );
    expect(cubit.state.selectedPersonId, isNull, reason: 'focus alone');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(cubit.state.selectedPersonId, 'a');
    expect(cubit.state.selectedRequestId, isNull);
  });

  // The browser keyboard map (#391 QA on dev 7.41.26): Space opened a focused
  // node but Enter did nothing, because on web Enter is ButtonActivateIntent.
  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets(
      'with web shortcuts, ${key.keyLabel} opens a focused Post node',
      (tester) async {
        final cubit = await _loadCubit();
        addTearDown(cubit.close);
        await _pumpBody(tester, cubit, shortcuts: webDefaultShortcuts);
        expect(
          await _tabTo(tester, 'post-a', const ['a']),
          isTrue,
          reason: 'Tab never moved focus onto the Post node',
        );
        expect(cubit.state.selectedRequestId, isNull, reason: 'focus alone');

        await tester.sendKeyEvent(key);
        await tester.pump();

        expect(cubit.state.selectedRequestId, 'post-a');
        expect(cubit.state.selectedPersonId, isNull);
      },
    );

    testWidgets(
      'with web shortcuts, ${key.keyLabel} opens a focused person node',
      (tester) async {
        final cubit = await _loadCubit();
        addTearDown(cubit.close);
        await _pumpBody(tester, cubit, shortcuts: webDefaultShortcuts);
        expect(
          await _tabTo(tester, 'a', const ['post-a']),
          isTrue,
          reason: 'Tab never moved focus onto the person node',
        );

        await tester.sendKeyEvent(key);
        await tester.pump();

        expect(cubit.state.selectedPersonId, 'a');
        expect(cubit.state.selectedRequestId, isNull);
      },
    );
  }

  testWidgets('with web shortcuts, Space still opens a focused person node', (
    tester,
  ) async {
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    await _pumpBody(tester, cubit, shortcuts: webDefaultShortcuts);
    expect(await _tabTo(tester, 'a', const ['post-a']), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(cubit.state.selectedPersonId, 'a');
  });

  testWidgets('map node semantics are focusable and take semantic focus', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    await _pumpBody(tester, cubit);

    final node = tester.getSemantics(_node('post-a'));
    expect(
      node,
      isSemantics(
        isButton: true,
        isFocusable: true,
        isFocused: false,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    // What the web engine sends when the browser Tab lands on the DOM node.
    node.owner!.performAction(
      node.id,
      SemanticsAction.focus,
    );
    await tester.pump();

    expect(_focusIsOnNode(tester, 'post-a', const ['a']), isTrue);
    expect(
      tester.getSemantics(_node('post-a')),
      isSemantics(isFocusable: true, isFocused: true),
    );
    handle.dispose();
  });

  testWidgets('Tab walks the map nodes in reading order, not widget order', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final cubit = await _loadCubit(withBob: true);
    addTearDown(cubit.close);
    await _pumpBody(tester, cubit);
    await tester.pumpAndSettle();
    for (final id in const ['a', 'b', 'post-a', 'post-b']) {
      expect(_node(id), findsOneWidget, reason: '$id must be on the map');
    }

    // Map layout, viewport-local points (top row: Ann left, her Post right;
    // bottom row: Bob further left than both, his Post right):
    //     a(360,330)        post-a(660,330)
    //   b(260,560)          post-b(660,560)
    // Reading order: a, post-a, b, post-b. The positions are presentation
    // overrides set post-b, b, post-a, a, and the graph view appends
    // overridden nodes to its child list in that order, so widget-tree (and
    // paint) order is post-b, b, post-a, a — the reverse; column order
    // (left-to-right) is b, a, post-a/post-b.
    final controller = cubit.graphController;
    final tokens = [
      for (final (graphId, local) in const [
        ('fr:post-b', Offset(660, 560)),
        ('fp:b', Offset(260, 560)),
        ('fr:post-a', Offset(660, 330)),
        ('fp:a', Offset(360, 330)),
      ])
        controller.beginNodePresentationDragForId(
          graphId,
          controller.viewportLocalToScene(local),
        ),
    ];
    await tester.pumpAndSettle();
    final a = tester.getCenter(_node('a'));
    final post = tester.getCenter(_node('post-a'));
    final b = tester.getCenter(_node('b'));
    final postB = tester.getCenter(_node('post-b'));
    expect(
      (a.dy - post.dy).abs() < 1 &&
          a.dx < post.dx &&
          b.dy > a.dy + 150 &&
          (b.dy - postB.dy).abs() < 1 &&
          b.dx < postB.dx,
      isTrue,
      reason: 'test setup must place the nodes ($a, $post, $b, $postB)',
    );

    expect(
      await _tabOrderOf(tester, const ['a', 'post-a', 'b', 'post-b']),
      const ['a', 'post-a', 'b', 'post-b'],
      reason: 'Tab must follow the map: top row left to right, then down',
    );

    // Screen readers and the web DOM (browser Tab) use semantics order.
    final ids = {
      for (final id in const ['a', 'post-a', 'b', 'post-b'])
        tester.getSemantics(_node(id)).id: id,
    };
    final order = [
      for (final node in tester.semantics.simulatedAccessibilityTraversal())
        if (ids.containsKey(node.id)) ids[node.id]!,
    ];
    expect(order, const ['a', 'post-a', 'b', 'post-b']);

    tokens.forEach(controller.cancelNodePresentationDrag);
    await tester.pump();
    handle.dispose();
  });

  testWidgets('Tab onto a node off screen brings it into view', (
    tester,
  ) async {
    final cubit = await _loadCubit(withBob: true);
    addTearDown(cubit.close);
    await _pumpBody(tester, cubit);
    await tester.pumpAndSettle();
    expect(_node('b'), findsOneWidget);

    // Bob's centre 300 px below the bottom edge of the window.
    await _parkAtGlobal(
      tester,
      cubit,
      id: 'b',
      graphId: 'fp:b',
      target: Offset(_size.width / 2, _size.height + 300),
    );
    final screen = Offset.zero & _size;
    expect(
      screen.overlaps(tester.getRect(_node('b'))),
      isFalse,
      reason: 'test setup must put Bob off screen',
    );
    final scaleBefore = cubit.graphController.cameraScale;

    expect(
      await _tabTo(tester, 'b', const ['a', 'post-a', 'post-b']),
      isTrue,
      reason: 'Tab never moved focus onto Bob',
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(_node('b'));
    expect(
      screen.intersect(rect),
      rect,
      reason: 'the focused node must be inside the window ($rect)',
    );
    final controller = cubit.graphController;
    final local = controller.sceneToViewportLocal(_sceneOf(cubit, 'fp:b'));
    expect(
      (Offset.zero & controller.viewportSize!).contains(local),
      isTrue,
      reason: 'the focused node must be inside the camera viewport ($local)',
    );
    expect(
      cubit.graphController.cameraScale,
      closeTo(scaleBefore, 1e-6),
      reason: 'bringing the node into view pans, it does not zoom',
    );
    expect(cubit.state.selectedPersonId, isNull, reason: 'focus alone');
  });

  group('Escape closes the panel (#680)', () {
    testWidgets('Escape closes the person panel; focus stays on the map', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      expect(await _tabTo(tester, 'a', const ['post-a']), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(cubit.state.selectedPersonId, 'a');
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);
      final focusWasOnNode = _focusIsOnNode(tester, 'a', const ['post-a']);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(cubit.state.selectedPersonId, isNull);
      expect(find.byType(GraphPersonContextPanel), findsNothing);
      expect(_focusIsInBody(), isTrue);
      if (focusWasOnNode) {
        expect(_focusIsOnNode(tester, 'a', const ['post-a']), isTrue);
      }
    });

    testWidgets('Escape with focus inside the person panel closes it', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      expect(await _tabTo(tester, 'a', const ['post-a']), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);

      final close = find.byKey(TestIds.key(TestIds.graphPersonContextClose));
      Focus.of(
        tester.element(
          find.descendant(of: close, matching: find.byType(Icon)),
        ),
      ).requestFocus();
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        focused != null &&
            find
                .ancestor(
                  of: find.byElementPredicate((e) => e == focused),
                  matching: find.byType(GraphPersonContextPanel),
                )
                .evaluate()
                .isNotEmpty,
        isTrue,
        reason: 'test setup must put focus inside the panel',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(cubit.state.selectedPersonId, isNull);
      expect(find.byType(GraphPersonContextPanel), findsNothing);
      expect(
        _focusIsInBody(),
        isTrue,
        reason: 'focus must come back to the map, not get lost',
      );
    });

    testWidgets('Escape closes the Post panel', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      expect(await _tabTo(tester, 'post-a', const ['a']), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, 'post-a');
      expect(find.byType(ConstellationPostPreviewSheet), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(cubit.state.selectedRequestId, isNull);
      expect(find.byType(ConstellationPostPreviewSheet), findsNothing);
    });

    testWidgets('Escape right after a mouse click on a person closes the '
        'panel', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      await tester.pumpAndSettle();
      await _focusOffMap(tester);

      await _click(tester, tester.getCenter(_node('a')));
      expect(cubit.state.selectedPersonId, 'a');
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(cubit.state.selectedPersonId, isNull);
      expect(find.byType(GraphPersonContextPanel), findsNothing);
    });

    testWidgets('Escape right after a mouse click on a Post closes the '
        'panel', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      await tester.pumpAndSettle();
      await _focusOffMap(tester);

      await _click(tester, tester.getCenter(_node('post-a')));
      expect(cubit.state.selectedRequestId, 'post-a');
      expect(find.byType(ConstellationPostPreviewSheet), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(cubit.state.selectedRequestId, isNull);
      expect(find.byType(ConstellationPostPreviewSheet), findsNothing);
    });

    testWidgets('a click on the map keeps focus in a text field outside it', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final field = FocusNode(debugLabel: 'outside text field');
      addTearDown(field.dispose);
      await _pumpBody(
        tester,
        cubit,
        outside: TextField(focusNode: field),
      );
      await tester.pumpAndSettle();
      field.requestFocus();
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);

      await _click(tester, tester.getCenter(_node('a')));

      expect(cubit.state.selectedPersonId, 'a');
      expect(field.hasPrimaryFocus, isTrue);
    });
  });

  group('a click on empty map clears the selection (#680)', () {
    testWidgets('closes the person panel', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('a')));
      expect(cubit.state.selectedPersonId, 'a');
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);

      await _click(
        tester,
        _emptyMapPoint(tester, const ['ego', 'a', 'post-a']),
      );

      expect(cubit.state.selectedPersonId, isNull);
      expect(cubit.state.selectedRequestId, isNull);
      expect(find.byType(GraphPersonContextPanel), findsNothing);
    });

    testWidgets('closes the Post panel', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('post-a')));
      expect(cubit.state.selectedRequestId, 'post-a');

      await _click(
        tester,
        _emptyMapPoint(tester, const ['ego', 'a', 'post-a']),
      );

      expect(cubit.state.selectedRequestId, isNull);
      expect(find.byType(ConstellationPostPreviewSheet), findsNothing);
    });

    testWidgets('a drag on empty map pans and keeps the selection', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('a')));
      expect(cubit.state.selectedPersonId, 'a');
      final start = _emptyMapPoint(tester, const ['ego', 'a', 'post-a']);
      final cameraBefore = cubit.graphController.cameraRevision.value;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: start);
      await mouse.down(start);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await mouse.moveBy(const Offset(15, 10));
        await tester.pump();
      }
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();

      expect(
        cubit.graphController.cameraRevision.value,
        greaterThan(cameraBefore),
        reason: 'the drag pans the camera',
      );
      expect(cubit.state.selectedPersonId, 'a');
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);
    });

    testWidgets('in select mode a click on empty map changes nothing', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final selection = ConstellationSelectionCubit();
      addTearDown(selection.close);
      await _pumpBody(tester, cubit, selection: selection);
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('a')));
      expect(cubit.state.selectedPersonId, 'a');
      selection.setSelecting(true);
      await tester.pumpAndSettle();

      await _click(
        tester,
        _emptyMapPoint(tester, const ['ego', 'a', 'post-a']),
      );

      expect(selection.state.selecting, isTrue);
      expect(cubit.state.selectedPersonId, 'a');
    });
  });

  // QA on 7.50.7 (#680): on the Field screen a click on empty map still
  // cleared nothing, Escape after a node click needed two presses, and
  // Escape did not leave select mode turned on from the toolbar.
  group('on the Field screen, which always provides a composer (#680)', () {
    testWidgets('a click on empty map closes the person panel', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final composer = _idleComposer();
      addTearDown(composer.close);
      await _pumpBody(tester, cubit, composer: composer);
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('a')));
      expect(cubit.state.selectedPersonId, 'a');
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);

      await _click(
        tester,
        _emptyMapPoint(tester, const ['ego', 'a', 'post-a']),
      );

      expect(cubit.state.selectedPersonId, isNull);
      expect(find.byType(GraphPersonContextPanel), findsNothing);
    });

    testWidgets('a click on empty map closes the Post panel', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final composer = _idleComposer();
      addTearDown(composer.close);
      await _pumpBody(tester, cubit, composer: composer);
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('post-a')));
      expect(cubit.state.selectedRequestId, 'post-a');

      await _click(
        tester,
        _emptyMapPoint(tester, const ['ego', 'a', 'post-a']),
      );

      expect(cubit.state.selectedRequestId, isNull);
      expect(find.byType(ConstellationPostPreviewSheet), findsNothing);
    });

    testWidgets('a drag on empty map pans and keeps the selection', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final composer = _idleComposer();
      addTearDown(composer.close);
      await _pumpBody(tester, cubit, composer: composer);
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('a')));
      expect(cubit.state.selectedPersonId, 'a');
      final start = _emptyMapPoint(tester, const ['ego', 'a', 'post-a']);
      final cameraBefore = cubit.graphController.cameraRevision.value;

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: start);
      await mouse.down(start);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await mouse.moveBy(const Offset(15, 10));
        await tester.pump();
      }
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();

      expect(
        cubit.graphController.cameraRevision.value,
        greaterThan(cameraBefore),
        reason: 'the drag pans the camera',
      );
      expect(cubit.state.selectedPersonId, 'a');
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);
    });

    testWidgets('with nodes left selected after select mode, Escape closes '
        'the panel first and then clears them', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final selection = ConstellationSelectionCubit()
        ..toggle(ConstellationAnchorTarget.person('a'));
      addTearDown(selection.close);
      final composer = _idleComposer();
      addTearDown(composer.close);
      await _pumpBody(
        tester,
        cubit,
        selection: selection,
        composer: composer,
      );
      await tester.pumpAndSettle();
      await _focusOffMap(tester);
      await _click(tester, tester.getCenter(_node('post-a')));
      expect(cubit.state.selectedRequestId, 'post-a');
      expect(selection.state.isEmpty, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, isNull, reason: 'first Escape');
      expect(find.byType(ConstellationPostPreviewSheet), findsNothing);
      expect(selection.state.isEmpty, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(selection.state.isEmpty, isTrue, reason: 'second Escape');
    });

    testWidgets('with nodes left selected after select mode, a click on '
        'empty map closes the panel', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final selection = ConstellationSelectionCubit()
        ..toggle(ConstellationAnchorTarget.person('a'));
      addTearDown(selection.close);
      final composer = _idleComposer();
      addTearDown(composer.close);
      await _pumpBody(
        tester,
        cubit,
        selection: selection,
        composer: composer,
      );
      await tester.pumpAndSettle();
      await _click(tester, tester.getCenter(_node('post-a')));
      expect(cubit.state.selectedRequestId, 'post-a');

      await _click(
        tester,
        _emptyMapPoint(tester, const ['ego', 'a', 'post-a']),
      );

      expect(cubit.state.selectedRequestId, isNull);
      expect(find.byType(ConstellationPostPreviewSheet), findsNothing);
    });

    testWidgets('Select several turned on from the toolbar: Escape leaves '
        'it', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final selection = ConstellationSelectionCubit();
      addTearDown(selection.close);
      final composer = _idleComposer();
      addTearDown(composer.close);
      await _pumpBody(
        tester,
        cubit,
        selection: selection,
        composer: composer,
        outside: const ConstellationSelectionToggle(),
      );
      await tester.pumpAndSettle();
      await _focusOffMap(tester);

      await _click(
        tester,
        tester.getCenter(find.byKey(const Key('constellation.app_bar.select'))),
      );
      expect(selection.state.selecting, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(selection.state.selecting, isFalse);
      expect(selection.state.isActive, isFalse);
    });

    testWidgets('Select several turned on keeps focus in a text field', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final selection = ConstellationSelectionCubit();
      addTearDown(selection.close);
      final field = FocusNode(debugLabel: 'outside text field');
      addTearDown(field.dispose);
      await _pumpBody(
        tester,
        cubit,
        selection: selection,
        outside: TextField(focusNode: field),
      );
      await tester.pumpAndSettle();
      field.requestFocus();
      await tester.pump();

      selection.setSelecting(true);
      await tester.pumpAndSettle();

      expect(field.hasPrimaryFocus, isTrue);
    });
  });

  testWidgets('at the smallest zoom node semantics rects are still 48 px '
      '(#678)', (tester) async {
    final handle = tester.ensureSemantics();
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    await _pumpBody(tester, cubit);
    await tester.pumpAndSettle();

    final controller = cubit.graphController..zoomBy(0.001);
    await tester.pumpAndSettle();
    controller.jumpToPosition(_sceneOf(cubit, 'fp:a'));
    await tester.pumpAndSettle();
    final drawn = tester.getRect(_node('a'));
    expect(
      drawn.width < kMinInteractiveDimension &&
          drawn.height < kMinInteractiveDimension,
      isTrue,
      reason: 'test setup must zoom out until the marker is small ($drawn)',
    );

    for (final id in const ['a', 'post-a']) {
      final rect = _semanticsRectOnScreen(
        tester,
        tester.getSemantics(_node(id)),
      );
      expect(
        rect.width >= kMinInteractiveDimension - 0.5 &&
            rect.height >= kMinInteractiveDimension - 0.5,
        isTrue,
        reason: '$id semantics rect on screen is $rect',
      );
      expect(
        (rect.center - tester.getCenter(_node(id))).distance,
        lessThan(1.5),
        reason: 'the $id semantics rect is centred on its marker',
      );
    }
    handle.dispose();
  });

  group('the chip row stays on top of the map (#675)', () {
    testWidgets('the map overlay that draws labels is clipped at the map '
        'edge, under the chip row', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(ConstellationVisibilityBar));
      expect(bar.height, greaterThan(0), reason: 'the chip row is shown');
      final overlay = find.byType(ConstellationViewportOverlay);
      final map = tester.getRect(overlay);
      expect(map.top, greaterThanOrEqualTo(bar.bottom - 0.5));

      // A label near the top edge is translated past the overlay's box, so
      // only a clip around it keeps it off the chips.
      final clip = _ancestorPaintClip(tester.renderObject(overlay));
      expect(clip, isNotNull, reason: 'nothing clips the map overlay');
      expect(
        clip!.top,
        greaterThanOrEqualTo(bar.bottom - 0.5),
        reason: 'the clip $clip must not reach the chip row $bar',
      );
      expect(map.inflate(0.5).contains(clip.topLeft), isTrue);
      expect(map.inflate(0.5).contains(clip.bottomRight), isTrue);
    });

    testWidgets('a tap on a chip reaches the chip', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpBody(tester, cubit);
      await tester.pumpAndSettle();
      final chip = find.byKey(const Key('constellation.show.requests'));
      expect(chip, findsOneWidget);

      final result = tester.hitTestOnBinding(tester.getCenter(chip));
      final chipBox = tester.renderObject(chip);
      expect(result.path.any((entry) => entry.target == chipBox), isTrue);
    });
  });
}
