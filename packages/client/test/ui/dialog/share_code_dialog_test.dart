import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('share dialog exposes invitation URL as selectable text', (
    tester,
  ) async {
    const link = 'https://tentura.example/invite/Iabc123';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: ShareCodeDialog(
            header: 'Invitation Code',
            link: link,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(link), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('Copy to clipboard'), findsOneWidget);
    expect(find.text('Share Link'), findsOneWidget);
  });

  testWidgets('share link tap does not throw when render box is ready', (
    tester,
  ) async {
    const link = 'https://tentura.example/invite/Iabc123';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: ShareCodeDialog(
            header: 'Invitation Code',
            link: link,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share Link'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
