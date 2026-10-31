import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_search_field.dart';
import 'package:tentura/features/profile_view/ui/dialog/edit_capabilities_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';

// #741: the profile capabilities picker is as long as Requirements, so it
// gets the same search box, and opens on its first group.

const _sizes = {'375x667': Size(375, 667), 'desktop': Size(1280, 800)};
const _locales = [Locale('en'), Locale('ru')];

Finder _chip(CapabilityTag tag) =>
    find.byKey(TestIds.key(TestIds.capabilityChip(tag.slug)));

void main() {
  for (final locale in _locales) {
    for (final size in _sizes.entries) {
      final l10n = lookupL10n(locale);
      testWidgets('${locale.languageCode} ${size.key}: search finds a tag '
          'outside the first group', (tester) async {
        tester.view
          ..physicalSize = size.value
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

        // Nothing chosen: the first group is open.
        expect(_chip(CapabilityTag.transport), findsOneWidget);
        expect(_chip(CapabilityTag.money), findsNothing);

        await tester.enterText(
          find.byKey(CapabilitySearchField.fieldKey),
          CapabilityTag.money.labelOf(l10n),
        );
        await tester.pumpAndSettle();
        expect(_chip(CapabilityTag.money), findsOneWidget);
        expect(_chip(CapabilityTag.transport), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
