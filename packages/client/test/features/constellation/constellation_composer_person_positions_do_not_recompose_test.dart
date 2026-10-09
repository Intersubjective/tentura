// While the graph composer is open, the positions of the people it can address
// follow the field through the interaction layer: a stream of position updates
// must not recompose or lay out the scene, yet the composer's circle still
// sees where each person is.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/util/layout_geometry_adapters.dart';

import '../../support/constellation_composer_screen_harness.dart';

Future<({ConstellationCubit cubit, ConstellationComposerCubit composer})>
_openComposer(WidgetTester tester) async {
  final cubit = await loadComposerHarnessCubit(ComposerHarnessRepository());
  final composer = buildComposerHarnessComposer();
  await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);
  final controller = cubit.graphController;
  composer.start(
    BeaconKind.post,
    controller.viewportLocalToScene(
      controller.viewportSize!.center(Offset.zero),
    ),
  );
  await tester.pumpAndSettle();

  // Positive control: entering the composer did recompose the scene.
  expect(cubit.state.isComposing, isTrue);
  expect(cubit.layoutReconciliationCount, greaterThan(0));
  return (cubit: cubit, composer: composer);
}

void main() {
  // The graph names a person `fp:<id>`; the composer knows them as `<id>`.
  testWidgets(
    'twenty position updates for addressable people run no recomposition or '
    'layout',
    (tester) async {
      final (:cubit, :composer) = await _openComposer(tester);
      final controller = cubit.graphController;
      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = controller.relayoutInvocationCount;
      final composition = cubit.state.composition;

      for (var i = 1; i <= 20; i++) {
        composer.updatePersonPositions({'a': Offset(300 + i * 3.0, 300)});
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        composer.selection.positions['a']?.offset,
        const Offset(360, 300),
        reason: 'the composer holds the last position it was given',
      );
      expect(
        cubit.layoutReconciliationCount,
        reconciliations,
        reason: 'a person moving must not recompose the field',
      );
      expect(
        cubit.state.composition,
        same(composition),
        reason: 'a person moving must not compose the presentation again',
      );
      expect(
        controller.relayoutInvocationCount,
        layoutRuns,
        reason: 'a person moving must not start a scene layout',
      );
    },
  );

  testWidgets(
    'a person moved in the interaction layer reaches the composer without a '
    'recomposition',
    (tester) async {
      final (:cubit, :composer) = await _openComposer(tester);
      final controller = cubit.graphController;
      final start = controller.getPositionOrNullForId('fp:a')!;
      final reconciliations = cubit.layoutReconciliationCount;
      final layoutRuns = controller.relayoutInvocationCount;
      final composition = cubit.state.composition;

      // What a drag does to the scene, with no widget callback involved: the
      // composer must learn of it from the interaction layer itself.
      final token = controller.beginNodePresentationDragForId('fp:a', start);
      for (var i = 1; i <= 20; i++) {
        controller.updateNodePresentationDrag(token, start + Offset(i * 2.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final moved = controller.getPositionOrNullForId('fp:a')!;
      expect(moved, start + const Offset(40, 0), reason: 'the person moved');

      expect(
        composer.selection.positions['a']?.offset,
        moved,
        reason: 'the composer follows the person through the interaction layer',
      );
      expect(
        cubit.layoutReconciliationCount,
        reconciliations,
        reason: 'a person moving must not recompose the field',
      );
      expect(
        cubit.state.composition,
        same(composition),
        reason: 'a person moving must not compose the presentation again',
      );
      expect(
        controller.relayoutInvocationCount,
        layoutRuns,
        reason: 'a person moving must not start a scene layout',
      );
      controller.cancelNodePresentationDrag(token);
      await tester.pump();
    },
  );
}
