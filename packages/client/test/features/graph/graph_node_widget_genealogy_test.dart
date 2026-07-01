import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';

const _viewer = Profile(
  id: 'Uviewer',
  displayName: 'Viewer',
  score: 3,
  rScore: 3,
);

class _BadgeTestGraphCubit extends Cubit<GraphState> implements GraphCubit {
  _BadgeTestGraphCubit() : super(const GraphState(me: _viewer, focus: ''));

  void setHiddenNeighborCounts(Map<String, int> counts) {
    emit(state.copyWith(hiddenNeighborCounts: counts));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<_BadgeTestGraphCubit> _pumpGraphNode(
  WidgetTester tester,
  GraphNodeWidget child,
) async {
  final cubit = _BadgeTestGraphCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: BlocProvider<GraphCubit>.value(
        value: cubit,
        child: child,
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

void main() {
  testWidgets('genealogy user nodes pass rating chrome to TenturaAvatar', (
    tester,
  ) async {
    await _pumpGraphNode(
      tester,
      const GraphNodeWidget(
        nodeDetails: GenealogyUserNode(nodeKey: 'Gviewer', user: _viewer),
        withRating: true,
      ),
    );

    final avatar = tester.widget<TenturaAvatar>(find.byType(TenturaAvatar));
    expect(avatar.profile.id, _viewer.id);
    expect(avatar.withRating, isTrue);
  });

  testWidgets('self genealogy node suppresses rating/contact chrome', (
    tester,
  ) async {
    await _pumpGraphNode(
      tester,
      const GraphNodeWidget(
        nodeDetails: GenealogyUserNode(nodeKey: 'Gviewer', user: _viewer),
        withRating: true,
        isSelf: true,
      ),
    );

    final avatar = tester.widget<TenturaAvatar>(find.byType(TenturaAvatar));
    expect(avatar.withRating, isFalse);
    expect(avatar.withContactBadge, isFalse);
    expect(avatar.isSelf, isTrue);
  });

  testWidgets('hidden-neighbor badge follows GraphState count updates', (
    tester,
  ) async {
    final cubit = await _pumpGraphNode(
      tester,
      const GraphNodeWidget(
        nodeDetails: GenealogyUserNode(nodeKey: 'Gviewer', user: _viewer),
      ),
    );

    expect(find.byType(TenturaCountBadge), findsNothing);

    final badgeShown = expectLater(
      cubit.stream,
      emits(
        predicate<GraphState>(
          (state) => state.hiddenNeighborCounts['Gviewer'] == 5,
        ),
      ),
    );
    cubit.setHiddenNeighborCounts({'Gviewer': 5});
    await badgeShown;
    await tester.pump();

    expect(find.byType(TenturaCountBadge), findsOneWidget);
    expect(
      tester.widget<TenturaCountBadge>(find.byType(TenturaCountBadge)).count,
      5,
    );

    final badgeHidden = expectLater(
      cubit.stream,
      emits(
        predicate<GraphState>(
          (state) => state.hiddenNeighborCounts['Gviewer'] == 0,
        ),
      ),
    );
    cubit.setHiddenNeighborCounts({'Gviewer': 0});
    await badgeHidden;
    await tester.pump();

    expect(find.byType(TenturaCountBadge), findsNothing);
  });
}
