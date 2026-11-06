import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/test_ids.dart';

import 'fixtures/constellation_arrange_harness.dart';

/// The Arrange control enters Arranging mode; overflow holds reset and history.

final _en = L10nEn();

Finder _arrangeButton() => find.byKey(const Key('constellation.camera.arrange'));
Finder _oldRearrangeButton() =>
    find.byKey(TestIds.key(TestIds.constellationRearrange));
Finder _oldResetButton() =>
    find.byKey(const Key('constellation.camera.reset_positions'));

Future<void> _enterArranging(WidgetTester tester) async {
  if (find
      .byKey(const Key('constellation.arranging.toolbar'))
      .evaluate()
      .isNotEmpty) {
    return;
  }
  await tester.tap(_arrangeButton());
  await tester.pumpAndSettle();
}

Future<void> _openOverflow(WidgetTester tester) async {
  await _enterArranging(tester);
  await tester.tap(find.byKey(const Key('constellation.arranging.more')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the released Field enters Arranging from the camera control', (
    tester,
  ) async {
    final harness = await arrangeHarness();
    await pumpArrangeControls(
      tester,
      harness.cubit,
      arrangeV2Enabled: kFieldArrangeV2Enabled,
    );

    expect(_arrangeButton(), findsOneWidget);
    expect(_oldRearrangeButton(), findsNothing);
    expect(_oldResetButton(), findsNothing);
    expect(
      find.descendant(
        of: _arrangeButton(),
        matching: find.byIcon(Icons.open_with),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _arrangeButton(),
        matching: find.byIcon(Icons.tune),
      ),
      findsNothing,
    );

    await _enterArranging(tester);
    expect(
      find.byKey(const Key('constellation.arranging.toolbar')),
      findsOneWidget,
    );
    expect(find.text(_en.constellationResetPositions), findsNothing);
  });

  group('Arrange copy', () {
    test('names the menu and its undo / redo in both languages', () {
      expect(_en.constellationArrange, 'Arrange');
      expect(_en.constellationUndo, 'Undo');
      expect(_en.constellationRedo, 'Redo');
      final ru = L10nRu();
      expect(ru.constellationArrange, 'Расставить');
      expect(ru.constellationUndo, 'Отменить');
      expect(ru.constellationRedo, 'Повторить');
    });

    test('the reset text no longer says it cannot be undone', () {
      expect(
        _en.constellationResetPositionsBody.toLowerCase(),
        isNot(contains("can't be undone")),
      );
      expect(
        L10nRu().constellationResetPositionsBody,
        isNot(contains('Отменить это нельзя')),
      );
    });
  });

  group('Arrange menu with the gate off', () {
    testWidgets('keeps the Rearrange and Reset buttons and no Arrange', (
      tester,
    ) async {
      final harness = await arrangeHarness();
      await pumpArrangeControls(
        tester,
        harness.cubit,
        arrangeV2Enabled: false,
      );

      expect(_oldRearrangeButton(), findsOneWidget);
      expect(_oldResetButton(), findsOneWidget);
      expect(_arrangeButton(), findsNothing);
    });
  });

  group('Arrange menu with the gate on', () {
    testWidgets('replaces the Rearrange and Reset buttons', (tester) async {
      final harness = await arrangeHarness();
      await pumpArrangeControls(tester, harness.cubit, arrangeV2Enabled: true);

      expect(_arrangeButton(), findsOneWidget);
      expect(_oldRearrangeButton(), findsNothing);
      expect(_oldResetButton(), findsNothing);
    });

    testWidgets('is reachable before anything is placed', (tester) async {
      final harness = await arrangeHarness(initial: const {});
      await pumpArrangeControls(tester, harness.cubit, arrangeV2Enabled: true);

      expect(_arrangeButton(), findsOneWidget);
    });

    testWidgets(
      'toolbar shows undo and redo; overflow lists rearrange and reset',
      (tester) async {
        final harness = await arrangeHarness();
        await pumpArrangeControls(
          tester,
          harness.cubit,
          arrangeV2Enabled: true,
        );

        await _enterArranging(tester);
        expect(
          find.byKey(const Key('constellation.arranging.undo')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('constellation.arranging.redo')),
          findsOneWidget,
        );

        await _openOverflow(tester);
        for (final label in [
          _en.constellationRearrange,
          _en.constellationResetPositions,
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      },
    );

    testWidgets('Undo and Redo do nothing while the history is empty', (
      tester,
    ) async {
      final harness = await arrangeHarness();
      await pumpArrangeControls(tester, harness.cubit, arrangeV2Enabled: true);
      await _enterArranging(tester);

      await tester.tap(find.byKey(const Key('constellation.arranging.undo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('constellation.arranging.redo')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.anchors.applies, isEmpty);
      expect(harness.anchors.restores, isEmpty);
      expect(harness.anchors.resets, isEmpty);
      expect(harness.anchors.anchors, arrangeInitialAnchors());
    });

    testWidgets('Undo undoes the last drag and Redo applies it again', (
      tester,
    ) async {
      final harness = await arrangeHarness();
      await pumpArrangeControls(tester, harness.cubit, arrangeV2Enabled: true);
      harness.placement.place(
        parent: arrangePersonOne,
        position: arrangePosition(9, 9),
        companions: const [],
      );
      await tester.pumpAndSettle();
      expect(harness.anchors.applies, hasLength(1));
      expect(harness.anchors.anchors[arrangePersonOne], arrangePosition(9, 9));

      await _enterArranging(tester);
      await tester.tap(find.byKey(const Key('constellation.arranging.undo')));
      await tester.pumpAndSettle();

      expect(harness.anchors.applies.length, greaterThan(1));
      expect(
        harness.anchors.anchors[arrangePersonOne],
        arrangeInitialAnchors()[arrangePersonOne],
      );

      await harness.cubit.redoArrangement();
      await tester.pumpAndSettle();

      expect(harness.anchors.applies.length, greaterThanOrEqualTo(2));
      expect(harness.anchors.anchors[arrangePersonOne], arrangePosition(9, 9));
    });

    testWidgets('is hidden in the tag view', (tester) async {
      final harness = await arrangeHarness();
      await pumpArrangeControls(
        tester,
        harness.cubit,
        arrangeV2Enabled: true,
        tagViewActive: true,
      );

      expect(_arrangeButton(), findsNothing);
      expect(
        find.byKey(const Key('constellation.arranging.toolbar')),
        findsNothing,
      );
    });

    testWidgets('reset needs no confirmation and is one call that saves '
        'history', (tester) async {
      final harness = await arrangeHarness();
      await pumpArrangeControls(tester, harness.cubit, arrangeV2Enabled: true);
      await _openOverflow(tester);

      await tester.tap(find.text(_en.constellationResetPositions));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(harness.anchors.resets, hasLength(1));
      expect(harness.anchors.resets.single.saveHistory, isTrue);
      expect(harness.anchors.anchors, isEmpty);
    });

    testWidgets('one Undo after a reset brings back every anchor', (
      tester,
    ) async {
      final harness = await arrangeHarness();
      final before = {...harness.anchors.anchors};
      await pumpArrangeControls(tester, harness.cubit, arrangeV2Enabled: true);
      await _openOverflow(tester);
      await tester.tap(find.text(_en.constellationResetPositions));
      await tester.pumpAndSettle();
      expect(harness.anchors.anchors, isEmpty);

      await _enterArranging(tester);
      await harness.cubit.undoArrangement();
      await tester.pumpAndSettle();

      expect(harness.anchors.restores, hasLength(1));
      expect(harness.anchors.anchors, before);
    });
  });
}
