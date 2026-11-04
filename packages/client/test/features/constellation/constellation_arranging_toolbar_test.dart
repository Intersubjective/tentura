import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/phone_surface.dart';
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_arrange_harness.dart';

void main() {
  testWidgets('Arranging toolbar hint renders in RU at phone width', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final harness = await arrangeHarness();
    final selection = constellationSelectionForFieldBodyTests()..enterArranging();
    await pumpArrangeControls(
      tester,
      harness.cubit,
      arrangeV2Enabled: true,
      selection: selection,
      locale: const Locale('ru'),
    );

    final hint = find.byKey(const Key('constellation.arranging.hint'));
    expect(hint, findsOneWidget);
    expect(
      tester.widget<Text>(hint).data,
      L10nRu().constellationArrangingHintTouch,
    );
  });
}
