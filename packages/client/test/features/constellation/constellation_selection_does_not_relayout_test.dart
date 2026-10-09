import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import 'fixtures/constellation_reference_fixture.dart';

/// Layout work done by the scene so far: the cubit's reconciliations and the
/// graph controller's scene layout runs.
({int reconciliations, int layoutRuns}) _layoutWork(
  ConstellationCubit cubit,
) => (
  reconciliations: cubit.layoutReconciliationCount,
  layoutRuns: cubit.graphController.relayoutInvocationCount,
);

Future<ConstellationCubit> _mount(WidgetTester tester) async {
  final cubit = await loadReferenceCubit();
  addTearDown(cubit.close);
  await pumpConstellationBody(tester, cubit);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return cubit;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('Selection leaves the layout alone', () {
    testWidgets('selecting a Request runs no layout', (tester) async {
      final cubit = await _mount(tester);

      // Positive control: the initial load did lay the scene out.
      expect(cubit.layoutReconciliationCount, greaterThan(0));
      expect(cubit.graphController.relayoutInvocationCount, greaterThan(0));
      final before = _layoutWork(cubit);

      cubit.selectRequest('req-am-1');
      await _settle(tester);

      expect(cubit.state.selectedRequestId, 'req-am-1');
      final after = _layoutWork(cubit);
      expect(
        after.reconciliations,
        before.reconciliations,
        reason: 'Selecting a Request must not reconcile the layout',
      );
      expect(
        after.layoutRuns,
        before.layoutRuns,
        reason: 'Selecting a Request must not start a scene layout',
      );
    });

    testWidgets('moving the Request selection runs no layout', (tester) async {
      final cubit = await _mount(tester);
      cubit.selectRequest('req-am-1');
      await _settle(tester);
      final before = _layoutWork(cubit);

      cubit.selectRequest('req-in-1');
      await _settle(tester);

      expect(cubit.state.selectedRequestId, 'req-in-1');
      final after = _layoutWork(cubit);
      expect(after.reconciliations, before.reconciliations);
      expect(after.layoutRuns, before.layoutRuns);
    });

    testWidgets('clearing the Request selection runs no layout', (
      tester,
    ) async {
      final cubit = await _mount(tester);
      cubit.selectRequest('req-am-1');
      await _settle(tester);
      final before = _layoutWork(cubit);

      cubit.selectRequest(null);
      await _settle(tester);

      expect(cubit.state.selectedRequestId, isNull);
      final after = _layoutWork(cubit);
      expect(after.reconciliations, before.reconciliations);
      expect(after.layoutRuns, before.layoutRuns);
    });

    testWidgets('selecting a person runs no layout', (tester) async {
      final cubit = await _mount(tester);
      final before = _layoutWork(cubit);

      cubit.selectPerson('am');
      await _settle(tester);

      expect(cubit.state.selectedPersonId, 'am');
      final after = _layoutWork(cubit);
      expect(
        after.reconciliations,
        before.reconciliations,
        reason: 'Selecting a person must not reconcile the layout',
      );
      expect(
        after.layoutRuns,
        before.layoutRuns,
        reason: 'Selecting a person must not start a scene layout',
      );
    });
  });
}
