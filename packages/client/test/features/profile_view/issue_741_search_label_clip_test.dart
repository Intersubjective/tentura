import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_search_field.dart';
import 'package:tentura/features/profile_view/ui/dialog/edit_capabilities_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

// #741 QA round 1: at 375×667 the profile «Edit labels» search field's
// floating label «Search» / «Поиск» was cut off by the top of the scroll
// area; its clear button said «Delete»; and a tag picked while searching
// did not open its group once the search was cleared.

const _locales = [Locale('en'), Locale('ru')];

Finder _chip(CapabilityTag tag) =>
    find.byKey(TestIds.key(TestIds.capabilityChip(tag.slug)));

final _field = find.byKey(CapabilitySearchField.fieldKey);

Future<void> _open(WidgetTester tester, Locale locale) async {
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (_, child) => TenturaResponsiveScope(child: child!),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
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
}

void main() {
  for (final locale in _locales) {
    final l10n = lookupL10n(locale);
    final lang = locale.languageCode;

    testWidgets('$lang 375×667: the floating search label is not clipped', (
      tester,
    ) async {
      await _open(tester, locale);
      await tester.enterText(_field, lang == 'ru' ? 'пере' : 'ing');
      await tester.pumpAndSettle();

      final label = tester.getRect(
        find.descendant(
          of: _field,
          matching: find.text(l10n.capabilitySearchLabel),
        ),
      );
      final viewport = tester.getRect(
        find.ancestor(of: _field, matching: find.byType(Scrollable)).first,
      );
      expect(
        label.top,
        greaterThanOrEqualTo(viewport.top),
        reason: 'label $label is cut by the scroll area $viewport',
      );
      expect(label.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$lang: the clear button says Clear, not Delete', (
      tester,
    ) async {
      await _open(tester, locale);
      await tester.enterText(_field, 'ing');
      await tester.pumpAndSettle();
      final material = MaterialLocalizations.of(
        tester.element(_field),
      );
      final clear = tester.widget<IconButton>(
        find.descendant(of: _field, matching: find.byType(IconButton)),
      );
      // The app's own «Очистить поиск» / "Clear search" (#741 round 2):
      // Material's stock RU clear tooltip reads «Удалить текст».
      expect(clear.tooltip, l10n.capabilitySearchClear);
      expect(clear.tooltip, isNot(material.deleteButtonTooltip));
      if (locale.languageCode == 'ru') {
        expect(clear.tooltip, 'Очистить поиск');
        expect(clear.tooltip, isNot(contains('Удалить')));
      } else {
        expect(clear.tooltip, 'Clear search');
      }
    });

    testWidgets('$lang: a tag picked while searching opens its group once '
        'the search is cleared', (tester) async {
      await _open(tester, locale);
      await tester.enterText(_field, CapabilityTag.money.labelOf(l10n));
      await tester.pumpAndSettle();
      await tester.tap(_chip(CapabilityTag.money));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: _field, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();

      expect(_chip(CapabilityTag.money), findsOneWidget);
      expect(_chip(CapabilityTag.transport), findsNothing);
    });
  }
}
