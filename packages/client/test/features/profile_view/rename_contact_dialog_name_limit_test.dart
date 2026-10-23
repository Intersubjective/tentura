import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile_view/ui/dialog/rename_contact_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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

// Save goes through the contacts use case, so these tests check the field and
// run the dialog's own Form validation instead of tapping Save.

Future<void> _open(WidgetTester tester) async {
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
              onPressed: () => unawaited(
                RenameContactDialog.show(
                  context,
                  profile: const Profile(id: 'U2', displayName: 'Carol'),
                ),
              ),
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open dialog'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

bool _validates(WidgetTester tester) =>
    tester.state<FormState>(find.byType(Form)).validate();

void main() {
  final l10n = lookupL10n(const Locale('en'));

  group('Rename contact dialog name field', () {
    testWidgets('emoji input is capped at 32 code units and validates', (
      tester,
    ) async {
      await _open(tester);
      expect(_fieldText(tester), 'Carol');

      await tester.enterText(find.byType(TextField), _typed);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _fits);
      expect(find.text('31/32'), findsOneWidget);
      expect(find.text('25/32'), findsNothing);

      expect(_validates(tester), isTrue);
      await tester.pump();
      expect(find.text(l10n.displayNameTooLong), findsNothing);
    });

    testWidgets('a cap inside an emoji drops the whole emoji', (tester) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), _cutsEmoji);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), 'a' * 31);
      expect(find.text('31/32'), findsOneWidget);
    });

    testWidgets('guard: a name that already fits is left untouched', (
      tester,
    ) async {
      await _open(tester);

      await tester.enterText(find.byType(TextField), _exact);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _exact);
      expect(_validates(tester), isTrue);
    });
  });
}
