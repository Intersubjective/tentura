import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_addressee_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  const tooShort = 'Имя приглашения слишком короткое';

  Future<void> openRuEdit(WidgetTester tester, String initialName) async {
    tester.view
      ..physicalSize = const Size(375, 667)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => unawaited(
                  InvitationAddresseeDialog.show(
                    context,
                    isEdit: true,
                    initialName: initialName,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final (name, counter) in const [('   ', '3/32'), ('', '0/32')]) {
    testWidgets(
      'RU too-short error for "$name" wraps beside the $counter counter '
      '(#1221)',
      (tester) async {
        await openRuEdit(tester, name);

        await tester.tap(find.text('Сохранить'));
        await tester.pumpAndSettle();

        expect(find.text(tooShort), findsOneWidget);
        final error = tester.renderObject<RenderParagraph>(
          find.text(tooShort),
        );
        expect(
          error.didExceedMaxLines,
          isFalse,
          reason: 'the whole error is drawn, nothing ellipsized',
        );
        expect(find.text(counter), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
