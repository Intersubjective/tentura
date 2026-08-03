import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'expand hops, back, and reset stay on the graph screen',
    (tester) async {
      await launchApp(app.main);
      await pumpBounded(tester);

      final runId = uniqueRunId('graph-nav');
      final fixture = await bootstrapFixture(runId: runId);

      await loginAs(tester, fixture.authorEmail);
      await userSubscribe(fixture.helperUserId);

      final urlBefore = currentAppUrl();
      await openConnectionsGraph(tester, fixture.authorUserId);

      // Hop 1: expand the ego neighbourhood (overview paging via cubit).
      await expandEgoNeighbourhood(tester);
      expect(readGraphCubit(tester).canPopFocus, isFalse);

      // Hop 2: focus helper and expand their neighbourhood.
      final helperNodeId = await selectGraphNeighbor(tester);
      await expandFocusedGraphNode(tester);
      final cubit = readGraphCubit(tester);
      expect(cubit.state.focus, helperNodeId);
      expect(cubit.canPopFocus, isTrue);
      expect(cubit.focusPath.length, 2);

      await tapGraphBack(tester);
      expect(readGraphCubit(tester).state.focus, isEmpty);
      expect(readGraphCubit(tester).canPopFocus, isFalse);
      expect(currentAppUrl(), urlBefore);

      await selectGraphNeighbor(tester);
      await expandFocusedGraphNode(tester);
      expect(readGraphCubit(tester).canPopFocus, isTrue);

      await tapGraphResetToEgo(tester);
      final afterReset = readGraphCubit(tester);
      expect(afterReset.state.focus, isEmpty);
      expect(afterReset.canPopFocus, isFalse);
      expect(afterReset.focusPath.length, 1);
      expect(currentAppUrl(), urlBefore);
    },
  );
}
