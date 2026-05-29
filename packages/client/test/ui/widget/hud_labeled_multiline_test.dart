import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

void main() {
  Future<void> pumpHudRow(
    WidgetTester tester, {
    required String text,
    VoidCallback? onShowDetail,
    VoidCallback? onEdit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: HudLabeledMultiline(
                label: 'NOW',
                text: text,
                mutedColor: Colors.grey,
                onShowDetail: onShowDetail,
                onEdit: onEdit,
                editSemanticLabel: 'Edit current line',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('short text hides show more suffix', (tester) async {
    await pumpHudRow(
      tester,
      text: 'Short line',
      onShowDetail: () {},
    );

    expect(find.text('show more'), findsNothing);
  });

  testWidgets('long text shows show more suffix', (tester) async {
    await pumpHudRow(
      tester,
      text:
          'This is a very long current line that should exceed two lines when rendered in the HUD multiline widget at a narrow width.',
      onShowDetail: () {},
    );

    expect(find.text('show more'), findsOneWidget);
  });

  testWidgets('content tap fires onShowDetail', (tester) async {
    var detailTaps = 0;
    await pumpHudRow(
      tester,
      text: 'Tap me for details',
      onShowDetail: () => detailTaps++,
    );

    await tester.tap(find.text('Tap me for details'));
    await tester.pumpAndSettle();

    expect(detailTaps, 1);
  });

  testWidgets('label and subline taps fire onShowDetail', (tester) async {
    var detailTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: HudLabeledMultiline(
                label: 'NOW',
                text: 'Current focus',
                subline: 'Blocked: credentials',
                mutedColor: Colors.grey,
                onShowDetail: () => detailTaps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('NOW'));
    await tester.pumpAndSettle();
    expect(detailTaps, 1);

    await tester.tap(find.text('Blocked: credentials'));
    await tester.pumpAndSettle();
    expect(detailTaps, 2);
  });

  testWidgets('edit tap fires onEdit without detail callback', (tester) async {
    var editTaps = 0;
    var detailTaps = 0;
    await pumpHudRow(
      tester,
      text: 'Editable line',
      onShowDetail: () => detailTaps++,
      onEdit: () => editTaps++,
    );

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(editTaps, 1);
    expect(detailTaps, 0);
  });
}
