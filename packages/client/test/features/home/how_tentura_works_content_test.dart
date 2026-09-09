import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/home/ui/widget/how_tentura_works_content.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _title = 'Welcome to Tentura';
const _intro =
    'Someone you know vouched for you. Tentura is where people get things done.';

Future<void> _pumpContent(
  WidgetTester tester, {
  required String title,
  required String intro,
  void Function(HomeTab)? onOpenTab,
  Size surfaceSize = const Size(800, 1200),
  TextScaler textScaler = TextScaler.noScaling,
  bool scrollable = false,
}) async {
  final content = HowTenturaWorksContent(
    title: title,
    intro: intro,
    onOpenTab: onOpenTab,
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: MediaQueryData(
          size: surfaceSize,
          textScaler: textScaler,
        ),
        child: Scaffold(
          body: scrollable
              ? SingleChildScrollView(
                  child: SizedBox(
                    width: surfaceSize.width,
                    child: content,
                  ),
                )
              : content,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('HowTenturaWorksContent', () {
    late L10n l10n;

    setUp(() {
      l10n = lookupL10n(const Locale('en'));
    });

    testWidgets('renders four nav rows with plan descriptions', (tester) async {
      await _pumpContent(
        tester,
        title: _title,
        intro: _intro,
        onOpenTab: (_) {},
      );

      final rows = <({String label, String description})>[
        (label: l10n.myWork, description: l10n.orientationWhereWork),
        (label: l10n.inbox, description: l10n.orientationWhereInbox),
        (
          label: l10n.constellationNavLabel,
          description: l10n.orientationWhereField,
        ),
        (label: l10n.network, description: l10n.orientationWhereNetwork),
      ];

      for (final row in rows) {
        expect(find.text(row.description), findsOneWidget);
        final semanticsLabel = l10n.orientationWhereSemantics(
          row.label,
          row.description,
        );
        final semantics = tester.getSemantics(
          find.bySemanticsLabel(semanticsLabel),
        );
        expect(semantics.label, semanticsLabel);
      }
    });

    testWidgets('tapping a row invokes onOpenTab with the right HomeTab', (
      tester,
    ) async {
      final opened = <HomeTab>[];

      await _pumpContent(
        tester,
        title: _title,
        intro: _intro,
        onOpenTab: opened.add,
      );

      final taps = <({String semanticsLabel, HomeTab tab})>[
        (
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.myWork,
            l10n.orientationWhereWork,
          ),
          tab: HomeTab.work,
        ),
        (
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.inbox,
            l10n.orientationWhereInbox,
          ),
          tab: HomeTab.inbox,
        ),
        (
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.constellationNavLabel,
            l10n.orientationWhereField,
          ),
          tab: HomeTab.constellation,
        ),
        (
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.network,
            l10n.orientationWhereNetwork,
          ),
          tab: HomeTab.network,
        ),
      ];

      for (final tap in taps) {
        await tester.tap(find.bySemanticsLabel(tap.semanticsLabel));
        await tester.pumpAndSettle();
        expect(opened.last, tap.tab);
      }

      expect(opened, [
        HomeTab.work,
        HomeTab.inbox,
        HomeTab.constellation,
        HomeTab.network,
      ]);
    });

    testWidgets('every nav row hit box is at least 48 logical pixels tall', (
      tester,
    ) async {
      await _pumpContent(
        tester,
        title: _title,
        intro: _intro,
        onOpenTab: (_) {},
      );

      final inkWells = tester.widgetList<InkWell>(find.byType(InkWell));
      expect(inkWells.length, 4);

      for (final inkWell in find.byType(InkWell).evaluate()) {
        final size = tester.getSize(find.byWidget(inkWell.widget));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('null onOpenTab renders rows without InkWell tap targets', (
      tester,
    ) async {
      await _pumpContent(
        tester,
        title: _title,
        intro: _intro,
        onOpenTab: null,
      );

      expect(find.byType(InkWell), findsNothing);

      final semanticsLabel = l10n.orientationWhereSemantics(
        l10n.myWork,
        l10n.orientationWhereWork,
      );
      await tester.tap(find.bySemanticsLabel(semanticsLabel));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at text scale 2.0 in a 375x667 surface without overflow', (
      tester,
    ) async {
      await _pumpContent(
        tester,
        title: _title,
        intro: _intro,
        onOpenTab: (_) {},
        surfaceSize: const Size(375, 667),
        textScaler: const TextScaler.linear(2),
        scrollable: true,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.orientationHowStep1), findsOneWidget);
      expect(find.text(l10n.orientationWhereNetwork), findsOneWidget);
    });
  });
}
