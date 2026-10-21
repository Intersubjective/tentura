@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fixtures/constellation_reference_fixture.dart';

const _egoChip = Key('constellation.overflow.ego');
const _amChip = Key('constellation.overflow.am');

/// Mounts two overflow chips (authors `ego` and `am`) side by side, the way
/// the overlay mounts one chip per author with hidden requests.
Future<void> _pumpChips(WidgetTester tester, ConstellationCubit cubit) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 400)),
        child: TenturaResponsiveScope(
          child: BlocProvider.value(
            value: cubit,
            child: const Column(
              children: [
                ConstellationOverflowGroup(
                  authorId: 'ego',
                  authorName: 'Vadim',
                  hiddenCount: 3,
                ),
                ConstellationOverflowGroup(
                  authorId: 'am',
                  authorName: 'agent m9x4u2k7',
                  hiddenCount: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Counts builds of each chip's cubit builder, keyed by author, from now on.
/// The chips are already mounted, so every counted build is a re-build.
Map<String, int> _countChipBuilderRebuilds() {
  final rebuilds = <String, int>{'ego': 0, 'am': 0};
  final previous = debugOnRebuildDirtyWidget;
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    if (element.widget is BlocBuilder<ConstellationCubit, ConstellationState>) {
      String? authorId;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is ConstellationOverflowGroup) authorId = widget.authorId;
        return authorId == null;
      });
      if (authorId != null) rebuilds[authorId!] = rebuilds[authorId]! + 1;
    }
  };
  return rebuilds;
}

String _moreLabel(WidgetTester tester, int count) =>
    L10n.of(tester.element(find.byKey(_egoChip)))!
        .constellationMoreRequests(count);

void main() {
  group('ConstellationOverflowGroup rebuild discipline', () {
    testWidgets('a layout revision bump rebuilds no chip whose expansion '
        'state is unchanged, while the scene is still re-laid out', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await _pumpChips(tester, cubit);
      await tester.pumpAndSettle();
      final rebuilds = _countChipBuilderRebuilds();

      final revisionBefore = cubit.state.graphRevision;
      final layoutAlgorithmBefore = cubit.constellationSceneLayoutAlgorithm;
      cubit.requestConstellationLayoutForTest();
      await tester.pumpAndSettle();

      expect(
        cubit.state.graphRevision,
        greaterThan(revisionBefore),
        reason: 'stimulus must actually emit a new graph revision',
      );
      expect(
        identical(cubit.constellationSceneLayoutAlgorithm, layoutAlgorithmBefore),
        isFalse,
        reason: 'a new revision must still produce a fresh layout algorithm',
      );
      expect(rebuilds, {'ego': 0, 'am': 0});
      expect(find.text(_moreLabel(tester, 3)), findsOneWidget);
      expect(find.text(_moreLabel(tester, 2)), findsOneWidget);
    });

    testWidgets('expanding one author rebuilds only that author chip and '
        'leaves the other chip untouched', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await _pumpChips(tester, cubit);
      await tester.pumpAndSettle();
      final rebuilds = _countChipBuilderRebuilds();
      expect(find.byKey(_egoChip), findsOneWidget);
      expect(find.byKey(_amChip), findsOneWidget);

      final revisionBefore = cubit.state.graphRevision;
      final compositionBefore = cubit.state.composition;
      cubit.toggleSatelliteOverflow('am');
      await tester.pumpAndSettle();

      expect(cubit.isSatelliteOverflowExpanded('am'), isTrue);
      expect(
        cubit.state.graphRevision,
        greaterThan(revisionBefore),
        reason: 'stimulus must rebuild the scene',
      );
      expect(
        identical(cubit.state.composition, compositionBefore),
        isFalse,
        reason: 'stimulus must recompose the presentation',
      );
      expect(rebuilds['am'], greaterThan(0));
      expect(rebuilds['ego'], 0);
      expect(find.text('Show fewer'), findsOneWidget);
      expect(find.text(_moreLabel(tester, 3)), findsOneWidget);
      expect(find.text(_moreLabel(tester, 2)), findsNothing);
    });

    testWidgets('toggling its own author still rebuilds the chip and flips '
        'its label', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await _pumpChips(tester, cubit);
      await tester.pumpAndSettle();
      final rebuilds = _countChipBuilderRebuilds();

      cubit.toggleSatelliteOverflow('ego');
      await tester.pumpAndSettle();
      expect(rebuilds['ego'], greaterThan(0));
      expect(find.text('Show fewer'), findsOneWidget);

      final afterExpand = rebuilds['ego']!;
      cubit.toggleSatelliteOverflow('ego');
      await tester.pumpAndSettle();
      expect(rebuilds['ego'], greaterThan(afterExpand));
      expect(find.text('Show fewer'), findsNothing);
      expect(find.text(_moreLabel(tester, 3)), findsOneWidget);
    });

    testWidgets('in the real overlay, expanding an author still re-places '
        'the chips and keeps the other author chip mounted', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      final holder = ConstellationPresentationFrameHolder();
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        presentationFrameHolder: holder,
      );
      await tester.pumpAndSettle();
      expect(holder.frame!.chips, isNotEmpty, reason: 'fixture mounts chips');
      final chipAuthors = holder.frame!.chips.keys.toSet();
      expect(chipAuthors, contains('ego'));

      constellationPlacementCount = 0;
      cubit.toggleSatelliteOverflow('ego');
      await tester.pumpAndSettle();

      expect(
        constellationPlacementCount,
        greaterThan(0),
        reason: 'an expansion must still re-run chip placement',
      );
      expect(cubit.isSatelliteOverflowExpanded('ego'), isTrue);
      expect(holder.frame!.chips.keys.toSet().containsAll(chipAuthors), isTrue);
    });
  });
}
