import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/phone_surface.dart';
import 'fixtures/constellation_arrange_harness.dart';
import 'fixtures/constellation_field_test_harness.dart';

void main() {
  testWidgets(
    'RU phone: Arrange → Rearrange everyone shows preview bar with Apply/Cancel',
    (tester) async {
      await usePhoneSurface(tester);
      final harness = await arrangeHarness();
      await pumpArrangeBody(
        tester,
        harness.cubit,
        arrangeV2Enabled: true,
        locale: const Locale('ru'),
      );

      final ru = L10nRu();
      await tapConstellationArrangeOverflowAction(
        tester,
        ru.constellationRearrangeEveryone,
      );
      harness.cubit.previewRearrangeAll();
      await tester.pumpAndSettle();

      final count = harness.cubit.state.rearrangePreview!.movingCount;
      expect(
        find.text(ru.constellationRearrangePreview(count)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('constellation-rearrange-apply')), findsOneWidget);
      expect(find.byKey(const Key('constellation-rearrange-cancel')), findsOneWidget);
      expect(find.text(ru.planEditApply), findsOneWidget);
      expect(find.text(ru.buttonCancel), findsOneWidget);
    },
  );
}
