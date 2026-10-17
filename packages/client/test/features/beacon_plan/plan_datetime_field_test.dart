// #447: the x that clears a chosen time was announced "No time", the same
// words as the unset picker.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_datetime_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('the clear button names the field it clears', (tester) async {
    final l10n = lookupL10n(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: PlanDateTimeField(
            label: l10n.planFieldStart,
            value: DateTime.utc(2026, 10, 12, 9),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Clear time: Start'), findsOneWidget);
    expect(find.byTooltip(l10n.planFieldClearTime), findsNothing);
  });
}
