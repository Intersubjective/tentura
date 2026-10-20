import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

/// #464: the shared invite lineage must open with the whole path fitted on
/// screen (labels included, and never over a pan/zoom the person already
/// made), and node labels must ellipsise on one line instead of being cut.

class _FakeInviteGenealogyRepository implements InviteGenealogyRepository {
  _FakeInviteGenealogyRepository(this.bootstrapGraph, {this.bootstrapGate});

  final InviteGenealogyGraph bootstrapGraph;

  /// When set, the bootstrap answers only once this completes.
  final Future<void>? bootstrapGate;

  @override
  Future<InviteGenealogyGraph> fetchGenealogyBootstrap({
    String? targetId,
  }) async {
    await bootstrapGate;
    return bootstrapGraph;
  }

  @override
  Future<InviteGenealogyChildrenPage> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async => const (
    nodes: <InviteGenealogyNode>[],
    edges: <InviteGenealogyEdge>[],
  );

  @override
  Future<Map<String, int>> fetchChildCounts({
    required List<String> nodeKeys,
  }) async => const {};

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) => throw UnsupportedError('generic fetch is not used in genealogy mode');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

/// Wraps onto several lines at the 100 px label width without any single
/// word overflowing a line, so only a one-line limit can ellipsise it.
const _longName = 'Ann Bea Cid Dee Eve Fay Gus';

const _viewer = Profile(id: 'Uviewer', displayName: _longName);

/// Root ancestor first, viewer last: `hops` invite edges above the viewer.
InviteGenealogyGraph _lineage(int hops) {
  final keys = [for (var i = 0; i < hops; i++) 'Ganc$i', 'Gviewer'];
  final at = DateTime.utc(2026);
  return InviteGenealogyGraph(
    viewerNodeKey: 'Gviewer',
    nodes: [
      for (final key in keys)
        InviteGenealogyNode(
          nodeKey: key,
          profile: key == 'Gviewer'
              ? _viewer
              : Profile(id: 'U$key', displayName: key),
          userCreatedAt: at,
        ),
    ],
    edges: [
      for (var i = 0; i + 1 < keys.length; i++)
        InviteGenealogyEdge(
          ancestorNodeKey: keys[i],
          descendantNodeKey: keys[i + 1],
          ancestorUserCreatedAt: at,
          descendantUserCreatedAt: at,
          createdAt: at,
        ),
    ],
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump();
}

Future<GraphCubit> _pumpInviteTree(
  WidgetTester tester, {
  required int hops,
  Size size = const Size(1280, 800),
  Size labelSize = GraphCubit.defaultNodeLabelSize,
  bool settle = true,
  Future<void>? bootstrapGate,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = GraphCubit(
    me: _viewer,
    graphSourceRepository: _FakeInviteGenealogyRepository(
      _lineage(hops),
      bootstrapGate: bootstrapGate,
    ),
    genealogyMode: true,
    genealogyAnonymousNodeLabel: 'Anonymous',
    nodeLabelSize: labelSize,
    edgeColors: _edgeColors,
    beaconRepository: _FakeBeaconRepository(),
    profileRepository: _FakeProfileRepository(),
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GraphCubit>.value(value: cubit),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        ],
        child: labelSize == GraphCubit.defaultNodeLabelSize
            ? const GraphScaffold(title: Text('Invite tree'))
            : Scaffold(
                body: GraphBody(
                  legendExpanded: false,
                  onToggleLegend: () {},
                  labelSize: labelSize,
                ),
              ),
      ),
    ),
  );
  if (settle) await _settle(tester);
  return cubit;
}

Rect _labelRect(WidgetTester tester, String label) {
  final finder = find.byWidgetPredicate(
    (w) => w is Text && w.data == label && w.key is ValueKey,
  );
  expect(finder, findsOneWidget, reason: 'label "$label" should be built');
  return tester.getRect(finder);
}

Rect _nodeRect(WidgetTester tester, String nodeKey) {
  final finder = find.byKey(TestIds.key(TestIds.graphNode(nodeKey)));
  expect(finder, findsOneWidget, reason: '$nodeKey should be on screen');
  return tester.getRect(finder);
}

void main() {
  testWidgets(
    'six-hop invite lineage opens fitted: every node, incl. the viewer, '
    'is inside the viewport',
    (tester) async {
      final cubit = await _pumpInviteTree(tester, hops: 6);
      expect(cubit.graphController.nodes, hasLength(7));

      final viewport = tester.getRect(find.byType(GraphBody));
      for (final key in [for (var i = 0; i < 6; i++) 'Ganc$i', 'Gviewer']) {
        final rect = _nodeRect(tester, key);
        expect(
          viewport.contains(rect.topLeft) &&
              viewport.contains(rect.bottomRight),
          isTrue,
          reason: '$key at $rect is outside viewport $viewport',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short invite lineage is not zoomed in past 1:1 on open',
    (tester) async {
      await _pumpInviteTree(tester, hops: 1);

      final viewport = tester.getRect(find.byType(GraphBody));
      final viewer = _nodeRect(tester, 'Gviewer');
      expect(viewport.contains(viewer.center), isTrue);
      // Endpoint nodes are 72 px at scale 1.
      expect(viewer.width, lessThanOrEqualTo(72.5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a long node label is ellipsised on one line instead of wrapping out '
    'of the label box',
    (tester) async {
      await _pumpInviteTree(tester, hops: 1);

      final label = find.byWidgetPredicate(
        (w) => w is Text && w.data == _longName && w.key is ValueKey,
      );
      expect(label, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: label, matching: find.byType(RichText)),
      );
      // The test engine already drops wrapped lines when an ellipsis is set
      // without a line limit, but other renderers (web) wrap and clip the
      // extra lines inside the 20 px label box. Pin the one-line limit on the
      // rendered paragraph so every renderer gets a single ellipsised line.
      expect(
        paragraph.maxLines,
        1,
        reason: 'the label must be limited to one line',
      );
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(
        paragraph.didExceedMaxLines,
        isTrue,
        reason: 'the label should be cut with an ellipsis',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open fit keeps the whole label box on screen, not just the node',
    (tester) async {
      // A label box wider than the viewport at 1:1: only a fit whose bounds
      // include the label (not just node.size / 2 plus padding) zooms out
      // enough to show it whole.
      await _pumpInviteTree(
        tester,
        hops: 1,
        labelSize: const Size(1600, 20),
      );

      final viewport = tester.getRect(find.byType(GraphBody));
      for (final label in ['Ganc0', _longName]) {
        final rect = _labelRect(tester, label);
        expect(
          viewport.contains(rect.topLeft) &&
              viewport.contains(rect.bottomRight),
          isTrue,
          reason: 'label "$label" at $rect is cut by viewport $viewport',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a zoom made before the layout settles is kept: the open fit does not '
    'move the camera afterwards',
    (tester) async {
      // The first layout has no transition (no spawn positions yet), so it
      // settles in the very frame the lineage arrives: the only time to zoom
      // "before the layout settles" is while the lineage is still loading.
      final gate = Completer<void>();
      final cubit = await _pumpInviteTree(
        tester,
        hops: 6,
        settle: false,
        bootstrapGate: gate.future,
      );
      await tester.pump();
      final controller = cubit.graphController;
      expect(controller.nodes, isEmpty, reason: 'bootstrap still loading');

      final pointer = TestPointer(1, PointerDeviceKind.mouse)
        ..hover(tester.getCenter(find.byType(GraphBody)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      // On an empty canvas the framework's InteractiveViewer asserts on its
      // zero-size child after it has reported the interaction start; that
      // assertion is not under test here (see the #464 report follow-ups).
      expect(tester.takeException(), anyOf(isNull, isA<AssertionError>()));
      final held = controller.cameraScale;

      gate.complete();
      await _settle(tester);
      expect(controller.nodes, hasLength(7), reason: 'bootstrap loaded');
      expect(
        controller.cameraScale,
        closeTo(held, 1e-6),
        reason: "the one-shot open fit must not override the person's zoom",
      );
      expect(tester.takeException(), isNull);
    },
  );
}
