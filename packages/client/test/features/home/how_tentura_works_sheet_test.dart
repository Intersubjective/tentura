import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/home/ui/sheet/how_tentura_works_sheet.dart';
import 'package:tentura/features/home/ui/widget/how_tentura_works_content.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> _pumpReopenHost(
  WidgetTester tester, {
  required void Function(BuildContext context) onOpenSheet,
  Size surfaceSize = const Size(800, 1200),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: MediaQueryData(size: surfaceSize),
        child: TenturaResponsiveScope(
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: OutlinedButton.icon(
                    onPressed: () => onOpenSheet(context),
                    icon: const Icon(Icons.help_outline),
                    label: Text(L10n.of(context)!.orientationReopen),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('showHowTenturaWorksSheet', () {
    late L10n l10n;

    setUp(() {
      l10n = lookupL10n(const Locale('en'));
    });

    testWidgets('opens from Profile-style reopen button with reopen copy', (
      tester,
    ) async {
      await _pumpReopenHost(
        tester,
        onOpenSheet: showHowTenturaWorksSheet,
      );

      await tester.tap(find.text(l10n.orientationReopen));
      await tester.pumpAndSettle();

      expect(find.text(l10n.orientationReopen), findsWidgets);
      expect(find.text(l10n.orientationIntroReopen), findsOneWidget);
      expect(find.text(l10n.orientationHowStep1), findsOneWidget);
      expect(find.text(l10n.orientationWhereWork), findsOneWidget);
    });

    testWidgets('nav rows are visible but inert when onOpenTab is null', (
      tester,
    ) async {
      await _pumpReopenHost(
        tester,
        onOpenSheet: showHowTenturaWorksSheet,
      );

      await tester.tap(find.text(l10n.orientationReopen));
      await tester.pumpAndSettle();

      expect(find.text(l10n.orientationWhereWork), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HowTenturaWorksContent),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );

      final semanticsLabel = l10n.orientationWhereSemantics(
        l10n.myWork,
        l10n.orientationWhereWork,
      );
      await tester.tap(find.bySemanticsLabel(semanticsLabel));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
