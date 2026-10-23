import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/utils/code_unit_length_formatter.dart';

// #603: the counter shared by the title fields that cap in code units. The
// sign-up and Edit profile screens need the app's DI to pump, so their field
// setups are mirrored here: a controller-backed field (sign-up) and an
// initialValue field that writes to state, with the near-limit counter
// (Edit profile).

/// 25 characters, 39 UTF-16 code units; its longest fitting prefix is 31.
final _typed = 'Van friend ${'🚐' * 14}';
final _fits = 'Van friend ${'🚐' * 10}';

Future<void> _pump(WidgetTester tester, Widget field) => tester.pumpWidget(
  MaterialApp(
    theme: TenturaTheme.light(),
    home: Scaffold(body: Form(child: field)),
  ),
);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  testWidgets('controller field: counter shows code units, not characters', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      TextFormField(
        controller: controller,
        maxLength: kTitleMaxLength,
        inputFormatters: const [
          CodeUnitLengthLimitingTextInputFormatter(kTitleMaxLength),
        ],
        buildCounter: tenturaCodeUnitCounter(() => controller.text),
      ),
    );
    expect(find.text('0/32'), findsOneWidget);

    await tester.enterText(find.byType(TextField), _typed);
    await tester.pumpAndSettle();

    expect(controller.text, _fits);
    expect(find.text('31/32'), findsOneWidget);
    expect(find.text('21/32'), findsNothing);
  });

  testWidgets('state-backed field: near-limit counter reads code units', (
    tester,
  ) async {
    var name = 'Mara';
    await _pump(
      tester,
      TextFormField(
        initialValue: name,
        maxLength: kTitleMaxLength,
        inputFormatters: const [
          CodeUnitLengthLimitingTextInputFormatter(kTitleMaxLength),
        ],
        buildCounter: tenturaCodeUnitCounter(
          () => name,
          render: tenturaCounterNearLimit,
        ),
        onChanged: (value) => name = value,
      ),
    );
    // Far from the limit: the near-limit counter stays silent.
    expect(find.text('4/32'), findsNothing);

    await tester.enterText(find.byType(TextField), _typed);
    await tester.pumpAndSettle();

    expect(_fieldText(tester), _fits);
    expect(name, _fits);
    // 21 characters is under 80 % of 32, so a character count would hide
    // the counter; 31 code units is near the limit and shows it.
    expect(find.text('31/32'), findsOneWidget);
  });
}
