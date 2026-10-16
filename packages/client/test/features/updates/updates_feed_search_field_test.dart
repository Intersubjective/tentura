// #425: the clear (x) button was announced as "Delete", and the field had no
// label for screen readers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_search_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('the field is labelled and its clear button says so', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController(text: 'couch');
    addTearDown(controller.dispose);
    final l10n = lookupL10n(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: UpdatesFeedSearchField(
            controller: controller,
            hintText: l10n.updatesSearchHint,
            onChanged: (_) {},
            onClear: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip(l10n.updatesSearchClear), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(EditableText)),
      matchesSemantics(
        label: l10n.updatesSearchHint,
        isTextField: true,
        value: 'couch',
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        isEnabled: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
  });
}
