import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/graph_mode.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'scene_layout_test_support.dart';

// #601 (from #396): in "How this request spread" the viewer was read out
// twice — once by the node button and once by the visible name under it —
// and the viewer node's name was the untranslated projection "Me".

/// The ego projection [GraphCubit] builds for the viewer (displayName "Me").
const _me = Profile(id: 'Ume', displayName: 'Me');
const _olga = Profile(id: 'Uolga', displayName: 'Olga');

class _ForwardsCubit extends Cubit<GraphState> implements GraphCubit {
  _ForwardsCubit()
    : super(const GraphState(me: _me, focus: '', isAnimated: false));

  @override
  final bool genealogyMode = false;

  @override
  final String? forwardsGraphBeaconId = 'Btest';

  @override
  GraphMode get mode => GraphMode.forwards;

  @override
  final graphController = testGraphController();

  @override
  bool get canPopFocus => false;

  @override
  List<String> get focusPath => const [];

  @override
  Set<String> get forwardsRootIds => const {};

  @override
  String get originNodeId => _me.id;

  @override
  void jumpToEgo({bool resetScale = false}) {}

  @override
  void popFocus() {}

  @override
  void resetToEgo() {}

  @override
  void fitCurrentPath() {}

  @override
  void togglePositiveOnly() {}

  @override
  void selectNode(NodeDetails node, {bool ensureStructuralEdges = true}) {}

  @override
  Future<void> expandNode(NodeDetails node) async {}

  @override
  bool canExpandNode(String id) => false;

  @override
  bool canPageMore(String id) => false;

  @override
  bool isCurrentFocus(String id) => false;

  @override
  void handleNodeTap(NodeDetails node) {}

  @override
  bool hasEverFocused(String id) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Future<void> _settleGraph(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _pumpForwardsGraph(WidgetTester tester, Locale locale) async {
  await tester.binding.setSurfaceSize(const Size(900, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = _ForwardsCubit();
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MultiBlocProvider(
        providers: [
          BlocProvider<GraphCubit>.value(value: cubit),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          BlocProvider<ProfileCubit>.value(value: _FakeProfileCubit()),
        ],
        child: GraphScaffold(title: const Text('Forwards')),
      ),
    ),
  );
  await _settleGraph(tester);

  final meNode = UserNode(user: _me, pinned: true, size: 80);
  final olgaNode = UserNode(user: _olga);
  final beaconNode = BeaconNode(
    beacon: Beacon(
      id: 'Btest',
      title: 'Help needed',
      author: _me,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );
  cubit.graphController.reconcileTopology(
    {meNode, olgaNode, beaconNode},
    {
      EdgeDetails(source: beaconNode, destination: meNode, color: Colors.blue),
      EdgeDetails(source: meNode, destination: olgaNode, color: Colors.blue),
    },
  );
  await _settleGraph(tester);
}

/// Every semantics node in the tree, in screen-reader traversal order.
List<SemanticsNode> _readingOrder(WidgetTester tester) {
  final root = tester
      .getSemantics(find.byType(GraphNodeWidget).first)
      .owner!
      .rootSemanticsNode!;
  final out = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    out.add(node);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(root);
  return out;
}

/// How many semantics nodes a screen reader announces as exactly [label].
int _announced(WidgetTester tester, String label) => _readingOrder(
  tester,
).where((n) => n.label.trim() == label).length;

SemanticsNode _button(WidgetTester tester, String label) => _readingOrder(
  tester,
).singleWhere((n) => n.label == label && n.hasFlag(SemanticsFlag.isButton));

/// Runs [body] with semantics on, disposing the handle before the
/// end-of-test check (addTearDown runs too late for it).
Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

void main() {
  group('#601 forwards graph semantics', () {
    testWidgets('the viewer is announced once, as a button', (tester) async {
      await _withSemantics(tester, () async {
        await _pumpForwardsGraph(tester, const Locale('en'));

        expect(find.byType(GraphNodeWidget), findsNWidgets(3));
        expect(_announced(tester, 'Me'), 1);
        expect(_button(tester, 'Me'), isNotNull);
      });
    });

    testWidgets('every person is announced once, by their node button', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await _pumpForwardsGraph(tester, const Locale('en'));

        expect(_announced(tester, 'Olga'), 1);
        expect(_button(tester, 'Olga'), isNotNull);
      });
    });

    testWidgets('the request node carries a semantics label (guard)', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await _pumpForwardsGraph(tester, const Locale('en'));

        expect(_button(tester, 'Request: Help needed'), isNotNull);
      });
    });

    testWidgets('the viewer node is named in the app language', (
      tester,
    ) async {
      await _withSemantics(tester, () async {
        await _pumpForwardsGraph(tester, const Locale('ru'));
        final l10n = L10n.of(tester.element(find.byType(GraphScaffold)))!;

        expect(l10n.labelMe, isNot('Me'));
        expect(_announced(tester, 'Me'), 0);
        expect(_announced(tester, l10n.labelMe), 1);
        expect(_button(tester, l10n.labelMe), isNotNull);
        // The visible name under the marker is translated too.
        expect(find.text(l10n.labelMe), findsOneWidget);
        expect(find.text('Me'), findsNothing);
      });
    });
  });
}
