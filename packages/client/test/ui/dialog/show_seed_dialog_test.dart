import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

// #466: the recovery seed dialog showed the raw secret as its title with no
// word on what it is, and the only "I saved it" step came in a second dialog
// after the secret had already left the screen.

const _seed = 'Zm9vYmFyYmF6cXV4Zm9vYmFyYmF6cXV4Zm9vYmFyYmE';

final _en = L10nEn();

void _useTallView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1280, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: home,
);

/// The enabled state of the material button whose label is [label].
bool _buttonEnabled(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    )
    .enabled;

void main() {
  testWidgets('seed dialog names the recovery seed and warns with the secret', (
    tester,
  ) async {
    _useTallView(tester);
    await tester.pumpWidget(
      _app(const Scaffold(body: ShowSeedDialog(seed: _seed))),
    );
    await tester.pumpAndSettle();

    // The secret is still shown...
    expect(find.text(_seed), findsOneWidget);

    // ...but it is not the dialog title any more.
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    final title = dialog.title;
    expect(
      title is Text && title.data == _seed,
      isFalse,
      reason: 'the raw seed must not be the dialog title',
    );

    // It says what this is, under its one name...
    expect(
      find.textContaining(RegExp('recovery seed', caseSensitive: false)),
      findsWidgets,
    );
    // ...and warns in the same dialog as the secret, before it.
    expect(find.text(_en.seedDialogWarning), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(_en.seedDialogWarning)).dy,
      lessThan(tester.getTopLeft(find.text(_seed)).dy),
      reason: 'the warning must sit above the seed, not under it',
    );
  });

  testWidgets('Close is disabled until the saved-it checkbox is ticked', (
    tester,
  ) async {
    _useTallView(tester);
    await tester.pumpWidget(
      _app(const Scaffold(body: ShowSeedDialog(seed: _seed))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text(_en.seedBackupConfirm), findsOneWidget);
    expect(_buttonEnabled(tester, _en.buttonClose), isFalse);

    // The label itself is tappable (CheckboxListTile or equivalent).
    await tester.ensureVisible(find.text(_en.seedBackupConfirm));
    await tester.tap(find.text(_en.seedBackupConfirm));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(_buttonEnabled(tester, _en.buttonClose), isTrue);

    // Copy stays available before confirming.
    expect(find.text(_en.copyToClipboard), findsOneWidget);
  });

  testWidgets('show() closes only after the person confirms', (tester) async {
    _useTallView(tester);
    var closed = false;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await ShowSeedDialog.show(context, seed: _seed);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ShowSeedDialog), findsOneWidget);

    // Tapping the barrier must not skip the saved-it step.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(ShowSeedDialog), findsOneWidget);
    expect(closed, isFalse);

    // Close before confirming does nothing.
    await tester.ensureVisible(find.text(_en.buttonClose));
    await tester.tap(find.text(_en.buttonClose), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(ShowSeedDialog), findsOneWidget);
    expect(closed, isFalse);

    await tester.ensureVisible(find.text(_en.seedBackupConfirm));
    await tester.tap(find.text(_en.seedBackupConfirm));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(_en.buttonClose));
    await tester.tap(find.text(_en.buttonClose));
    await tester.pumpAndSettle();

    expect(find.byType(ShowSeedDialog), findsNothing);
    expect(closed, isTrue);
  });
}
