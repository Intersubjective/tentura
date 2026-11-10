import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_remove_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Opens the dialog at iPhone SE size; the returned list collects what
/// [InvitationRemoveDialog.show] completed with.
Future<List<bool?>> _open(WidgetTester tester, String locale) async {
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async =>
                  results.add(await InvitationRemoveDialog.show(context)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  const cases = {
    'en': (
      title: 'Remove this invite?',
      body: 'The link will stop working.',
      remove: 'Remove',
      keep: 'Keep invite',
    ),
    'ru': (
      title: 'Удалить приглашение?',
      body: 'Ссылка перестанет работать.',
      remove: 'Удалить',
      keep: 'Оставить приглашение',
    ),
  };

  for (final MapEntry(key: locale, value: copy) in cases.entries) {
    group('InvitationRemoveDialog $locale at 375x667 (#1074)', () {
      testWidgets('the destructive label uses the title verb', (tester) async {
        await _open(tester, locale);

        expect(find.text(copy.title), findsOneWidget);
        expect(find.text(copy.body), findsOneWidget);
        expect(find.text(copy.remove), findsOneWidget);
        expect(find.text(copy.keep), findsOneWidget);
        expect(
          copy.title.toLowerCase(),
          startsWith(copy.remove.toLowerCase()),
          reason: 'title and destructive action share one verb',
        );
        expect(copy.keep, isNot(contains(copy.remove)));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the destructive action is styled danger', (tester) async {
        await _open(tester, locale);

        // TextButton paints its label through DefaultTextStyle.
        Color? labelColor(String label) =>
            DefaultTextStyle.of(tester.element(find.text(label))).style.color;
        final danger = tester.element(find.text(copy.remove)).tt.danger;

        expect(labelColor(copy.remove), danger);
        expect(labelColor(copy.keep), isNot(danger));
      });

      testWidgets('Remove pops true', (tester) async {
        final results = await _open(tester, locale);

        await tester.tap(find.text(copy.remove));
        await tester.pumpAndSettle();

        expect(results, [true]);
        expect(find.text(copy.title), findsNothing);
      });

      testWidgets('Keep invite pops without removing', (tester) async {
        final results = await _open(tester, locale);

        await tester.tap(find.text(copy.keep));
        await tester.pumpAndSettle();

        expect(results, [null]);
        expect(find.text(copy.title), findsNothing);
      });
    });
  }
}
