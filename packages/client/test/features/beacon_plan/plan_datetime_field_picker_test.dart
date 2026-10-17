// #446: the time picker was the 12-hour clock with AM/PM while the app shows
// every time as 24-hour (13:10, 22:36).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_datetime_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('the time picker uses the 24-hour clock', (tester) async {
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
            value: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text(l10n.planFieldClearTime));
    await tester.pumpAndSettle();
    // Date picker: keep the initial day.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
  });
}
