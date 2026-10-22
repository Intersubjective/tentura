// The Text view hidden behind the map must not rebuild when the map's
// composition changes, and the per-tile Pin buttons must not each recompute
// the whole layout input: pinnability is derived once per composition, and a
// new composition still invalidates it.
//
// The recompute / rebuild counters (`pinLayoutInputBuildCount` on the cubit,
// `debugBuildCount` on the text view) are read dynamically so a missing
// counter fails the test at run time, not at load time.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_state.dart';
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

int _pinInputBuilds(ConstellationCubit cubit) =>
    (cubit as dynamic).pinLayoutInputBuildCount as int;

int _textViewBuilds(ConstellationCubit cubit) =>
    (cubit as dynamic).textViewBuildCount as int;

Future<({ConstellationCubit cubit, dynamic composer})> _pumpScreen(
  WidgetTester tester,
) async {
  final cubit = await loadComposerHarnessCubit(
    ComposerHarnessRepository(_wideField),
  );
  final composer = buildComposerHarnessComposer();
  // Tall enough for every person's tile below the list's search field
  // (#253): the assertions cover all of them.
  await pumpComposerHarnessScreen(
    tester,
    cubit: cubit,
    composer: composer,
    size: const Size(1280, 1100),
  );
  return (cubit: cubit, composer: composer);
}

void main() {
  group('pin availability across many targets', () {
    testWidgets(
      'request targets stay pinnable and share one layout input per '
      'composition',
      (tester) async {
        final (:cubit, composer: _) = await _pumpScreen(tester);
        final targets = [
          for (final id in _ids) ConstellationAnchorTarget.beacon('req-$id'),
        ];

        final before = _pinInputBuilds(cubit);
        final first = [for (final t in targets) cubit.canPinTarget(t)];
        final second = [for (final t in targets) cubit.canPinTarget(t)];

        expect(first, second);
        expect(first, everyElement(isTrue), reason: 'visible behaviour kept');
        expect(
          cubit.canPinTarget(
            ConstellationAnchorTarget.beacon('req-missing'),
          ),
          isFalse,
          reason: 'an unknown target is still not pinnable',
        );
        expect(
          _pinInputBuilds(cubit) - before,
          lessThanOrEqualTo(1),
          reason: '13+ queries against one composition share one layout input',
        );
      },
    );

    testWidgets(
      'a new composition rebuilds the pin layout input',
      (tester) async {
        final (:cubit, :composer) = await _pumpScreen(tester);
        final target = ConstellationAnchorTarget.beacon('req-a');
        expect(cubit.canPinTarget(target), isTrue);
        final before = _pinInputBuilds(cubit);

        final controller = cubit.graphController;
        composer.start(
          BeaconKind.post,
          controller.viewportLocalToScene(
            controller.viewportSize!.center(Offset.zero),
          ),
        );
        await tester.pumpAndSettle();
        final reconciled = cubit.layoutReconciliationCount;
        expect(reconciled, greaterThan(0));

        // While composing, the composition carries no requests, so a request
        // is not pinnable (unchanged behaviour); only the cache is under test.
        expect(cubit.canPinTarget(target), isFalse);
        cubit.canPinTarget(target);
        expect(
          _pinInputBuilds(cubit) - before,
          1,
          reason: 'the changed composition invalidates the cached input once',
        );
      },
    );

    testWidgets(
      'recomposing the visible map builds the pin layout input at most once '
      'per reconciliation, not once per tile',
      (tester) async {
        final (:cubit, :composer) = await _pumpScreen(tester);
        expect(cubit.state.viewMode, ConstellationViewMode.map);
        final inputs = _pinInputBuilds(cubit);
        final reconciliations = cubit.layoutReconciliationCount;

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

        final reconciled = cubit.layoutReconciliationCount - reconciliations;
        expect(reconciled, greaterThan(0));
        expect(
          _pinInputBuilds(cubit) - inputs,
          lessThanOrEqualTo(reconciled),
          reason: 'six tile buttons share the input of each composition',
        );
        expect(
          cubit.canPinTarget(ConstellationAnchorTarget.beacon('req-a')),
          isFalse,
          reason: 'composing strips requests from the composition',
        );
      },
    );

    testWidgets(
      'every request tile in the text view shares one pin layout input',
      (tester) async {
        final (:cubit, composer: _) = await _pumpScreen(tester);
        cubit.setViewMode(ConstellationViewMode.text);
        await tester.pumpAndSettle();
        expect(
          find.byType(ConstellationAnchorTargetButton),
          findsAtLeastNWidgets(_ids.length),
        );

        final before = _pinInputBuilds(cubit);
        // Force every tile's button to rebuild against the same composition.
        cubit.setViewMode(ConstellationViewMode.map);
        await tester.pumpAndSettle();
        cubit.setViewMode(ConstellationViewMode.text);
        await tester.pumpAndSettle();

        expect(
          _pinInputBuilds(cubit) - before,
          lessThanOrEqualTo(1),
          reason: 'per-tile buttons must not each recompute the layout input',
        );
      },
    );
  });

  group('hidden text view', () {
    testWidgets(
      'does not rebuild when the map recomposes',
      (tester) async {
        final (:cubit, :composer) = await _pumpScreen(tester);
        expect(cubit.state.viewMode, ConstellationViewMode.map);

        final before = _textViewBuilds(cubit);
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
        expect(cubit.layoutReconciliationCount, greaterThan(0));

        expect(
          _textViewBuilds(cubit),
          before,
          reason: 'a view hidden behind the map is not rebuilt',
        );
      },
    );

    testWidgets(
      'rebuilds when the user switches to it',
      (tester) async {
        final (:cubit, composer: _) = await _pumpScreen(tester);
        final before = _textViewBuilds(cubit);
        cubit.setViewMode(ConstellationViewMode.text);
        await tester.pumpAndSettle();
        expect(
          _textViewBuilds(cubit),
          greaterThan(before),
          reason: 'positive control: a visible view does build',
        );
      },
    );

    testWidgets(
      'shows current requests when the user switches to it',
      (tester) async {
        final (:cubit, composer: _) = await _pumpScreen(tester);
        cubit.setViewMode(ConstellationViewMode.text);
        await tester.pumpAndSettle();
        expect(find.text('Need a'), findsWidgets);
      },
    );
  });
}
