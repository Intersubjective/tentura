import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/capability/ui/widget/capability_search_field.dart';
import 'package:tentura/features/profile_view/ui/dialog/edit_capabilities_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #741 (QA round 2): in Russian the search box's clear (×) button was
// announced «Удалить текст» — Material's stock clearButtonTooltip. It is the
// app's own «Очистить поиск» / "Clear search".

const _cases = [
  (Locale('en'), 'Clear search', 'Clear text'),
  (Locale('ru'), 'Очистить поиск', 'Удалить текст'),
];

Widget _app(Locale locale, Widget home) => MaterialApp(
  builder: (_, child) => TenturaResponsiveScope(child: child!),
  locale: locale,
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: home,
);

void main() {
  for (final (locale, clear, stock) in _cases) {
    testWidgets("${locale.languageCode}: the field's × reads «$clear» as "
        'tooltip and screen-reader label, and empties the search', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(375, 667)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var query = '';
      await tester.pumpWidget(
        _app(
          locale,
          Scaffold(
            body: CapabilitySearchField(onChanged: (v) => query = v),
          ),
        ),
      );
      await tester.enterText(find.byKey(CapabilitySearchField.fieldKey), 'ab');
      await tester.pump();

      expect(find.byTooltip(clear), findsOneWidget);
      expect(find.byTooltip(stock), findsNothing);
      // What a screen reader announces for the × button.
      expect(
        find.semantics.byPredicate(
          (node) => node.tooltip == clear || node.label == clear,
        ),
        findsOne,
      );
      expect(
        find.semantics.byPredicate(
          (node) => node.tooltip == stock || node.label == stock,
        ),
        findsNothing,
      );

      await tester.tap(find.byTooltip(clear));
      await tester.pump();
      expect(query, isEmpty);
      expect(find.byTooltip(clear), findsNothing);
      semantics.dispose();
    });

    testWidgets('${locale.languageCode}: Edit labels dialog search × reads '
        '«$clear»', (tester) async {
      tester.view
        ..physicalSize = const Size(375, 667)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          locale,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => EditCapabilitiesDialog.show(
                  context,
                  subjectId: 'U1',
                  subjectName: 'Alice',
                  currentVisible: const [],
                  onSaved: (_, _) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CapabilitySearchField.fieldKey), 'ab');
      await tester.pumpAndSettle();

      expect(find.byTooltip(clear), findsOneWidget);
      expect(find.byTooltip(stock), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
