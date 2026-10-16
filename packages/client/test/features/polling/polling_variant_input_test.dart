// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/polling/ui/widget/polling_variant_input.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  Future<GlobalKey<FormState>> pumpTwoOptions(
    WidgetTester tester, {
    required List<String> values,
  }) async {
    final formKey = GlobalKey<FormState>();
    bool isDuplicateAt(int index, String value) {
      for (var i = 0; i < values.length; i++) {
        if (i != index && values[i].trim() == value) return true;
      }
      return false;
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                for (var i = 0; i < values.length; i++)
                  PollingVariantInput(
                    initialValue: values[i],
                    isDuplicate: (v) => isDuplicateAt(i, v),
                    onChanged: (_) {},
                    onRemove: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return formKey;
  }

  testWidgets('repeated option text fails validation with a message', (
    tester,
  ) async {
    final formKey = await pumpTwoOptions(
      tester,
      values: ['Saturday', 'Saturday ', 'Sunday'],
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Options must be different'), findsNWidgets(2));
  });

  testWidgets('distinct options validate', (tester) async {
    final formKey = await pumpTwoOptions(
      tester,
      values: ['Saturday', 'Sunday'],
    );

    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();

    expect(find.text('Options must be different'), findsNothing);
  });
}
