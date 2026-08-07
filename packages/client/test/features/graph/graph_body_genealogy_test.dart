import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_scaffold.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(
  id: 'Uviewer',
  displayName: 'Viewer',
  score: 3,
  rScore: 3,
);

class _StubGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _StubGraphCubit({required this.genealogyMode})
    : super(const GraphState(me: _viewer, focus: '', isAnimated: false));

  @override
  final bool genealogyMode;

  @override
  final String? forwardsGraphBeaconId = null;

  @override
  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  @override
  bool get canPopFocus => false;

  @override
  String get originNodeId => _viewer.id;

  @override
  List<String> get focusPath => [_viewer.id];

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

Future<_StubGraphCubit> _pumpGraphBody(
  WidgetTester tester, {
  required bool genealogyMode,
  Size size = const Size(900, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = _StubGraphCubit(genealogyMode: genealogyMode);
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
        child: GraphScaffold(
          title: const Text('Graph'),
        ),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

void main() {
  testWidgets(
    'expanded genealogy mode hides positive-only filter toggle',
    (tester) async {
      await _pumpGraphBody(tester, genealogyMode: true);

      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsNothing);
    },
  );

  testWidgets(
    'expanded relationships mode shows positive-only filter toggle',
    (tester) async {
      await _pumpGraphBody(tester, genealogyMode: false);

      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_off_outlined), findsNothing);
    },
  );

  testWidgets(
    'GraphBody wires withRating for GenealogyUserNode',
    (tester) async {
      final cubit = await _pumpGraphBody(tester, genealogyMode: true);
      const node = GenealogyUserNode(nodeKey: 'Gviewer', user: _viewer);
      cubit.graphController.mutate((mutator) => mutator.addNode(node));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final widgets = tester.widgetList<GraphNodeWidget>(
        find.byType(GraphNodeWidget),
      );
      expect(widgets, isNotEmpty);
      expect(
        widgets.any((w) => w.nodeDetails.id == 'Gviewer' && w.withRating),
        isTrue,
      );
    },
  );
}
