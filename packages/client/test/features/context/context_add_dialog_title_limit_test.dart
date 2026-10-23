import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/context/ui/dialog/context_add_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

// #603 (follow-up of #356): this field capped with TextField.maxLength, whose
// counter and cap count user-perceived characters, while the validator and
// the server count UTF-16 code units. An emoji counts once in the counter and
// twice in the check, so a name the counter showed as 25/32 was refused.

/// 25 characters, 39 UTF-16 code units (each van is two).
final _typed = 'Van friend ${'🚐' * 14}';

/// Its longest prefix that fits 32 code units without splitting a van.
final _fits = 'Van friend ${'🚐' * 10}';

/// Exactly 32 code units, 22 characters: already fits, left untouched.
final _exact = 'Van friend x${'🚐' * 10}';

/// The cap lands inside the emoji: 32 characters, 33 code units.
final _cutsEmoji = '${'a' * 31}🚐';

class _Validator with StringInputValidator {}

class _Outcome {
  bool closed = false;
  String? result;
}

Future<_Outcome> _open(WidgetTester tester) async {
  final outcome = _Outcome();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                final result = await ContextAddDialog.show(context);
                outcome
                  ..result = result
                  ..closed = true;
              },
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open dialog'));
  await tester.pumpAndSettle();
  return outcome;
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('fixture strings measure as the comments say', () {
    expect(kTitleMaxLength, 32);
    expect(_typed.length, 39);
    expect(_typed.characters.length, 25);
    expect(_fits.length, 31);
    expect(_exact.length, 32);
    expect(_exact.characters.length, 22);
    expect(_cutsEmoji.length, 33);
    expect(_cutsEmoji.characters.length, 32);
  });

  group('New topic dialog title field', () {
    testWidgets('emoji input is capped at 32 code units and is accepted', (
      tester,
    ) async {
      final outcome = await _open(tester);

      await tester.enterText(find.byType(TextField), _typed);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _fits);
      expect(find.text('31/32'), findsOneWidget);
      expect(find.text('25/32'), findsNothing);
      expect(_Validator().titleValidator(l10n, _fieldText(tester)), isNull);

      await tester.tap(find.text(l10n.buttonOk));
      await tester.pumpAndSettle();

      expect(outcome.closed, isTrue);
      expect(outcome.result, _fits);
    });

    testWidgets('a cap inside an emoji drops the whole emoji', (tester) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), _cutsEmoji);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), 'a' * 31);
      expect(find.text('31/32'), findsOneWidget);
    });

    testWidgets('guard: a title that already fits is left untouched', (
      tester,
    ) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), _exact);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _exact);
      expect(_Validator().titleValidator(l10n, _exact), isNull);
    });
  });
}
