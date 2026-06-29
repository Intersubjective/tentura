import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('dismiss dialog cancel does not use disposed controller', (
    tester,
  ) async {
    String? result = 'pending';

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showInboxDismissDialog(context);
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

    expect(find.text('Remove from inbox?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
