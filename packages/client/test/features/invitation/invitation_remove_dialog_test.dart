import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_remove_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('destructive Remove pairs with Keep invite dismiss (#1074)', (
    tester,
  ) async {
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
                onPressed: () => InvitationRemoveDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Remove this invite?'), findsOneWidget);
    expect(find.text('The link will stop working.'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Keep invite'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
