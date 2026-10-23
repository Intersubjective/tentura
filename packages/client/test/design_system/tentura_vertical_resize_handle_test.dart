import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('TenturaVerticalResizeHandle reports horizontal drag delta', (
    tester,
  ) async {
    final deltas = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(
              height: 200,
              child: Row(
                children: [
                  const Expanded(child: SizedBox.expand()),
                  TenturaVerticalResizeHandle(
                    onDragDelta: deltas.add,
                  ),
                  const SizedBox(
                    width: 120,
                    child: ColoredBox(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final handle = find.byType(TenturaVerticalResizeHandle);
    expect(handle, findsOneWidget);

    await tester.drag(handle, const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(deltas, isNotEmpty);
    expect(deltas.reduce((a, b) => a + b), closeTo(-40, 1));
  });

  group('#670 the pane divider is announced in the app language', () {
    Future<void> pumpHandle(
      WidgetTester tester, {
      required Locale locale,
      String? semanticLabel,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(
              height: 200,
              child: Row(
                children: [
                  const Expanded(child: SizedBox.expand()),
                  TenturaVerticalResizeHandle(
                    onDragDelta: (_) {},
                    semanticLabel: semanticLabel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('ru: the divider reads Russian, not Resize', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHandle(tester, locale: const Locale('ru'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Изменить ширину панелей'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Resize')), findsNothing);
      semantics.dispose();
    });

    testWidgets('en: the divider reads Resize panes', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHandle(tester, locale: const Locale('en'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Resize panes'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('an explicit label still wins', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpHandle(
        tester,
        locale: const Locale('ru'),
        semanticLabel: 'Custom',
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Custom'), findsOneWidget);
      semantics.dispose();
    });
  });
}
