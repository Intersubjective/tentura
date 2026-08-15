import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_addressee_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  const dualPurpose =
      'This link works if they are new to Tentura or already have an account.';
  const singleUse = 'This invite can be used only once.';
  const fieldLabel = 'Private name for this person';
  const helper = 'Only you can see this. You can change it later.';

  Future<void> pumpAndOpen(
    WidgetTester tester, {
    bool isEdit = false,
    String initialName = '',
  }) async {
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
                onPressed: () {
                  unawaited(
                    InvitationAddresseeDialog.show(
                      context,
                      isEdit: isEdit,
                      initialName: initialName,
                    ),
                  );
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
  }

  testWidgets('create dialog shows private label, helper, and dual-purpose', (
    tester,
  ) async {
    await pumpAndOpen(tester);

    expect(find.text('For whom is this invite?'), findsOneWidget);
    expect(find.text(dualPurpose), findsOneWidget);
    expect(find.text(singleUse), findsOneWidget);
    expect(find.text(fieldLabel), findsOneWidget);
    expect(find.text(helper), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets('edit dialog omits dual-purpose copy', (tester) async {
    await pumpAndOpen(tester, isEdit: true, initialName: 'Mom');

    expect(find.text('Edit invite name'), findsOneWidget);
    expect(find.text(dualPurpose), findsNothing);
    expect(find.text(singleUse), findsNothing);
    expect(find.text(fieldLabel), findsOneWidget);
    expect(find.text(helper), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Russian create copy wraps on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                onPressed: () {
                  unawaited(InvitationAddresseeDialog.show(context));
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

    const label = 'Приватное имя для этого человека';
    const helper = 'Видно только вам. Можно сменить позже.';
    expect(find.text(label), findsOneWidget);
    expect(find.text(helper), findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.renderObject<RenderParagraph>(find.text(helper)).didExceedMaxLines,
      isFalse,
    );
  });
}
