// Issue #391: Field map nodes must be reachable with Tab and activatable
// with Enter/Space, and expose a focusable semantics node (the web engine
// only gives a DOM node a tabindex when its semantics node is focusable).
// Tab walks the nodes in map reading order (not widget-tree order), and a
// node Tab lands on off screen is brought into view.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/web_default_shortcuts.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

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

Future<void> _pumpBody(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Map<ShortcutActivator, Intent>? shortcuts,
}) async {
  const size = _size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
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
            ],
            child: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
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
}
