import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_content.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(
  id: 'Uviewer',
  displayName: 'Viewer',
  score: 3,
  rScore: 3,
);

class _StubGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _StubGraphCubit({
    this.genealogyMode = false,
    this.forwardsGraphBeaconId,
  }) : super(const GraphState(me: _viewer, focus: '', isAnimated: false));

  @override
  final bool genealogyMode;

  @override
  final String? forwardsGraphBeaconId;

  @override
  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  @override
  void jumpToEgo() {}

  @override
  void togglePositiveOnly() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<_StubGraphCubit> _pumpGraphBody(
  WidgetTester tester, {
  bool genealogyMode = false,
  String? forwardsGraphBeaconId,
  Size size = const Size(900, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = _StubGraphCubit(
    genealogyMode: genealogyMode,
    forwardsGraphBeaconId: forwardsGraphBeaconId,
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
        child: const Scaffold(body: GraphBody()),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

Future<void> _pumpLegendContent(
  WidgetTester tester,
  GraphLegendMode mode,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: GraphLegendContent(mode: mode),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('legend control expands and collapses', (tester) async {
    await _pumpGraphBody(tester);

    expect(find.byIcon(Icons.map_outlined), findsNWidgets(2));
    expect(find.text('Legend'), findsNothing);

    await tester.tap(find.byIcon(Icons.map_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('Legend'), findsOneWidget);
    expect(find.text('People badges'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.text('Legend'), findsNothing);
    expect(find.byIcon(Icons.map_outlined), findsNWidgets(2));
  });

  testWidgets('trust legend shows negative edge row', (tester) async {
    await _pumpLegendContent(tester, GraphLegendMode.trust);

    expect(find.textContaining('negative connection'), findsOneWidget);
    expect(find.textContaining('neighborhood links'), findsOneWidget);
    expect(find.textContaining('more neighbors'), findsOneWidget);
    expect(find.textContaining('help on this forward'), findsNothing);
  });

  testWidgets('forwards legend shows help offerer row', (tester) async {
    await _pumpLegendContent(tester, GraphLegendMode.forwards);

    expect(find.textContaining('help on this forward'), findsOneWidget);
    expect(find.textContaining('sender'), findsOneWidget);
    expect(find.textContaining('more neighbors'), findsNothing);
    expect(find.textContaining('negative connection'), findsNothing);
  });

  testWidgets('genealogy legend shows branch colors and hidden children',
      (tester) async {
    await _pumpLegendContent(tester, GraphLegendMode.genealogy);

    expect(find.textContaining('your invite branch'), findsOneWidget);
    expect(find.textContaining('their invite branch'), findsOneWidget);
    expect(find.textContaining('more invitees'), findsOneWidget);
    expect(find.textContaining('negative connection'), findsNothing);
  });

  testWidgets('expanded layout shows legend in side rail', (tester) async {
    await _pumpGraphBody(tester);

    expect(find.byIcon(Icons.map_outlined), findsNWidgets(2));
  });
}
