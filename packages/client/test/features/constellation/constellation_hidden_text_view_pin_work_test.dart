// While the map is shown, the Text view is unmounted from the
// IndexedStack. Its tiles' Pin buttons must not keep computing pin
// availability (a full placed layout, twice for a miss) every time the map
// recomposes: nobody can see them. Switching to the Text view must still show
// current data and working Pin buttons.
//
// Work is pinned with counters, never wall-clock: Pin button (re)builds seen
// through `debugOnRebuildDirtyWidget`, `constellationPinLayoutRunCount`
// (placed-layout runs done for pin positions) and
// `ConstellationCubit.pinLayoutInputBuildCount`. The rebuild count is what
// catches a button that rebuilds and answers from cached layout data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/constellation/domain/constellation_pin_position.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_anchor_controls.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';

import '../../support/constellation_composer_screen_harness.dart';

const _ids = ['a', 'b', 'c', 'd', 'e', 'f'];

ConstellationField _wideField() {
  final base = composerHarnessField(peers: _ids);
  return ConstellationField(
    loadedAt: base.loadedAt,
    context: base.context,
    peers: base.peers,
    edges: base.edges,
    requests: [
      for (final id in _ids)
        ConstellationRequest(
          id: 'req-$id',
          authorId: id,
          title: 'Need $id',
          status: 0,
          needs: const ['tools'],
        ),
    ],
  );
}

/// [_wideField] with person `g` and their request added and person `b`'s
/// request removed.
ConstellationField _changedField() {
  final base = _wideField();
  return ConstellationField(
    loadedAt: base.loadedAt,
    context: base.context,
    peers: [
      ...base.peers,
      const ConstellationPerson(id: 'g'),
    ],
    edges: [
      ...base.edges,
      const ConstellationTrustEdgeEntity(src: 'ego', dst: 'g', tier: 1),
    ],
    requests: [
      for (final request in base.requests)
        if (request.id != 'req-b') request,
      const ConstellationRequest(
        id: 'req-g',
        authorId: 'g',
        title: 'Need g',
        status: 0,
        needs: ['tools'],
      ),
    ],
  );
}

Future<({ConstellationCubit cubit, ConstellationComposerCubit composer})>
_pumpScreen(
  WidgetTester tester, {
  ComposerHarnessRepository? repository,
}) async {
  final cubit = await loadComposerHarnessCubit(
    repository ?? ComposerHarnessRepository(_wideField),
  );
  final composer = buildComposerHarnessComposer();
  await pumpComposerHarnessScreen(tester, cubit: cubit, composer: composer);
  return (cubit: cubit, composer: composer);
}

/// Rebuilds of any [ConstellationAnchorTargetButton] element, or of anything
/// beneath one (its BlocBuilder, tooltip, button), while [body] runs.
Future<int> _pinButtonRebuildsDuring(Future<void> Function() body) async {
  var rebuilds = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    var underButton = element.widget is ConstellationAnchorTargetButton;
    if (!underButton) {
      element.visitAncestorElements((ancestor) {
        underButton = ancestor.widget is ConstellationAnchorTargetButton;
        return !underButton;
      });
    }
    if (underButton) rebuilds++;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilds;
}

Future<void> _recomposeMap(
  WidgetTester tester,
  ConstellationCubit cubit,
  ConstellationComposerCubit composer,
) async {
  final controller = cubit.graphController;
  composer.start(
    BeaconKind.post,
    controller.viewportLocalToScene(
      controller.viewportSize!.center(Offset.zero),
    ),
  );
  await tester.pumpAndSettle();
  cubit.rearrangeFreeNodes();
  await tester.pumpAndSettle();
}

void main() {
  group('Text view hidden behind the map', () {
    testWidgets('restores scroll offset after Text view is unmounted', (
      tester,
    ) async {
      final (:cubit, composer: _) = await _pumpScreen(tester);
      final textView = find.byType(ConstellationTextView, skipOffstage: false);
      final list = find.byKey(
        const PageStorageKey<String>('constellation.text.list'),
      );
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );

      expect(cubit.state.viewMode, ConstellationViewMode.map);
      expect(textView, findsNothing);
      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -580));
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(offset, greaterThan(0));

      for (var cycle = 0; cycle < 2; cycle++) {
        final previousState = tester.state<ScrollableState>(scrollable);
        cubit.setViewMode(ConstellationViewMode.map);
        await tester.pumpAndSettle();
        expect(textView, findsNothing);
        expect(previousState.mounted, isFalse);

        cubit.setViewMode(ConstellationViewMode.text);
        await tester.pumpAndSettle();
        expect(textView, findsOneWidget);
        final restoredState = tester.state<ScrollableState>(scrollable);
        expect(restoredState, isNot(same(previousState)));
        expect(restoredState.position.pixels, closeTo(offset, 0.01));
      }
    });

    testWidgets(
      'recomposing the map does no pin availability work',
      (tester) async {
        final (:cubit, :composer) = await _pumpScreen(tester);
        expect(cubit.state.viewMode, ConstellationViewMode.map);

        final layoutRuns = constellationPinLayoutRunCount;
        final inputBuilds = cubit.pinLayoutInputBuildCount;

        final rebuilds = await _pinButtonRebuildsDuring(
          () => _recomposeMap(tester, cubit, composer),
        );
        expect(cubit.layoutReconciliationCount, greaterThan(0));

        expect(
          rebuilds,
          0,
          reason: 'Pin buttons hidden behind the map are not rebuilt',
        );
        expect(
          constellationPinLayoutRunCount - layoutRuns,
          0,
          reason: 'no visible Pin button asks, so no placed layout runs',
        );
        expect(
          cubit.pinLayoutInputBuildCount - inputBuilds,
          0,
          reason: 'no visible Pin button asks, so no layout input is built',
        );
      },
    );

    testWidgets(
      'a map change that rebuilds no visible Pin button leaves the pin '
      'layout counters unchanged',
      (tester) async {
        final (:cubit, :composer) = await _pumpScreen(tester);
        await _recomposeMap(tester, cubit, composer);

        final layoutRuns = constellationPinLayoutRunCount;
        final inputBuilds = cubit.pinLayoutInputBuildCount;
        final rebuilds = await _pinButtonRebuildsDuring(() async {
          cubit.rearrangeFreeNodes();
          await tester.pumpAndSettle();
          cubit.rearrangeFreeNodes();
          await tester.pumpAndSettle();
        });

        expect(rebuilds, 0);
        expect(constellationPinLayoutRunCount - layoutRuns, 0);
        expect(cubit.pinLayoutInputBuildCount - inputBuilds, 0);
      },
    );

    testWidgets(
      'switching to the Text view shows the field that changed while it was '
      'hidden, with pinnable Pin buttons',
      (tester) async {
        final repository = ComposerHarnessRepository(_wideField);
        final (:cubit, :composer) = await _pumpScreen(
          tester,
          repository: repository,
        );
        await _recomposeMap(tester, cubit, composer);
        await composer.cancel();
        await composer.finish();
        await tester.pumpAndSettle();

        repository.fieldBuilder = _changedField;
        await cubit.load();
        await tester.pumpAndSettle();
        expect(cubit.state.viewMode, ConstellationViewMode.map);
        expect(
          cubit.state.field?.requests.map((r) => r.id),
          contains('req-g'),
          reason: 'the changed field reached the cubit while Text was hidden',
        );

        final rebuilds = await _pinButtonRebuildsDuring(() async {
          cubit.setViewMode(ConstellationViewMode.text);
          await tester.pumpAndSettle();
        });

        expect(
          rebuilds,
          greaterThan(0),
          reason: 'positive control: the new tile for person g builds a button',
        );
        expect(find.text('Need g'), findsWidgets);
        expect(find.text('Need b'), findsNothing);
        for (final id in ['a', 'c', 'd', 'e', 'f', 'g']) {
          expect(find.text('Need $id'), findsWidgets);
        }
        final buttons = tester.widgetList<ConstellationAnchorTargetButton>(
          find.byType(ConstellationAnchorTargetButton),
        );
        expect(buttons, isNotEmpty);
        for (final button in buttons) {
          expect(
            cubit.canPinTarget(button.target),
            isTrue,
            reason: 'visible behaviour kept: ${button.target}',
          );
        }
        expect(
          buttons.map((b) => b.target),
          contains(ConstellationAnchorTarget.beacon('req-g')),
        );
        expect(
          buttons.map((b) => b.target),
          isNot(contains(ConstellationAnchorTarget.beacon('req-b'))),
        );
      },
    );

    testWidgets(
      'visible Text view tiles show enabled Pin buttons without a layout per '
      'tile',
      (tester) async {
        final (:cubit, composer: _) = await _pumpScreen(tester);
        final layoutRuns = constellationPinLayoutRunCount;

        cubit.setViewMode(ConstellationViewMode.text);
        await tester.pumpAndSettle();

        final buttons = find.byType(ConstellationAnchorTargetButton);
        expect(buttons, findsAtLeastNWidgets(_ids.length));
        final pressables = tester.widgetList<OutlinedButton>(
          find.descendant(of: buttons, matching: find.byType(OutlinedButton)),
        );
        expect(pressables.length, greaterThanOrEqualTo(_ids.length));
        expect(
          pressables.map((b) => b.onPressed),
          everyElement(isNotNull),
          reason: 'every visible tile can be pinned',
        );
        expect(
          constellationPinLayoutRunCount - layoutRuns,
          lessThanOrEqualTo(1),
          reason: 'tiles share one placed layout per composition',
        );
      },
    );
  });
}
