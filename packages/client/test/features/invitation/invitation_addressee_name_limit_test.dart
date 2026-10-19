import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_addressee_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';

// #356: the invite-name field capped with TextField.maxLength, whose counter
// counts user-perceived characters, while `displayNameValidator` and the
// server (`ContactCase.normalizeName`: `trimmed.length > kTitleMaxLength`)
// count UTF-16 code units. An emoji counts once in the counter and twice in
// the check, so a name the counter showed as 25/32 was refused on Save with
// "Display name is too long".

const _tooLong = 'Display name is too long';

/// The issue repro: 25 characters, 39 UTF-16 code units (each van is two).
final _typed = 'Van friend ${'🚐' * 14}';

/// Its longest prefix that fits 32 code units without splitting a van:
/// 21 characters, 31 code units.
final _fits = 'Van friend ${'🚐' * 10}';

/// Exactly 32 code units, 22 characters.
final _exact = 'Van friend x${'🚐' * 10}';

/// The cap lands inside the emoji: 32 characters, 33 code units.
final _cutsEmoji = '${'a' * 31}🚐';

class _Validator with StringInputValidator {}

/// True when [s] holds a UTF-16 surrogate that is not half of a pair.
bool _hasLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 >= s.length) return true;
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

/// What the dialog returned once it closed.
class _Outcome {
  bool closed = false;
  String? result;
}

Future<_Outcome> _openEditDialog(
  WidgetTester tester, {
  String initialName = 'Mom',
}) async {
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
                final result = await InvitationAddresseeDialog.show(
                  context,
                  isEdit: true,
                  initialName: initialName,
                );
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
  test('fixture strings measure as the comments say', () {
    expect(kTitleMaxLength, 32);
    expect(_typed.length, 39);
    expect(_typed.characters.length, 25);
    expect(_fits.length, 31);
    expect(_fits.characters.length, 21);
    expect(_exact.length, 32);
    expect(_exact.characters.length, 22);
    expect(_cutsEmoji.length, 33);
    expect(_cutsEmoji.characters.length, 32);
  });

  test('guard: the validator keeps counting code units like the server', () {
    final validator = _Validator();
    final l10n = lookupL10n(const Locale('en'));
    expect(validator.displayNameValidator(l10n, _exact), isNull);
    // 25 characters but 39 code units: the server refuses it, so must we.
    expect(
      validator.displayNameValidator(l10n, _typed),
      l10n.displayNameTooLong,
    );
  });

  group('Edit invite name dialog', () {
    testWidgets('the issue repro is capped at 32 code units and saves', (
      tester,
    ) async {
      final outcome = await _openEditDialog(tester);

      await tester.enterText(find.byType(TextField), _typed);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _fits);
      expect(find.text('31/32'), findsOneWidget);
      expect(find.text('25/32'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(_tooLong), findsNothing);
      expect(outcome.closed, isTrue, reason: 'dialog closed on Save');
      expect(outcome.result, _fits.trim());
      expect(outcome.result!.length, lessThanOrEqualTo(kTitleMaxLength));
    });

    testWidgets('the counter counts code units, and a 32/32 name saves', (
      tester,
    ) async {
      final outcome = await _openEditDialog(tester);

      await tester.enterText(find.byType(TextField), _exact);
      await tester.pumpAndSettle();

      // Untouched: it already fits, emoji and all.
      expect(_fieldText(tester), _exact);
      expect(find.text('32/32'), findsOneWidget);
      expect(find.text('22/32'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(_tooLong), findsNothing);
      expect(outcome.closed, isTrue);
      expect(outcome.result, _exact);
    });

    testWidgets('a cap inside an emoji drops the whole emoji', (
      tester,
    ) async {
      final outcome = await _openEditDialog(tester);

      await tester.enterText(find.byType(TextField), _cutsEmoji);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), 'a' * 31);
      expect(find.text('31/32'), findsOneWidget);
      expect(find.text('32/32'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(_tooLong), findsNothing);
      expect(outcome.closed, isTrue);
      expect(outcome.result, 'a' * 31);
      expect(_hasLoneSurrogate(outcome.result!), isFalse);
    });
  });
}
