import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/card_triage_action_row.dart';

void main() {
  group('TenturaResponsiveScope', () {
    testWidgets('passes full viewport width to child (no centered cap clip)', (
      tester,
    ) async {
      const viewportWidth = 853.0;
      double? capturedMaxWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 1280),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 1280)),
            child: TenturaResponsiveScope(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  capturedMaxWidth = constraints.maxWidth;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(capturedMaxWidth, viewportWidth);
    });

    testWidgets('tablet shell rail is not horizontally clipped', (
      tester,
    ) async {
      const viewportWidth = 853.0;
      const viewportHeight = 1280.0;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, viewportHeight),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(viewportWidth, viewportHeight),
            ),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavigationRail(
                      extended: true,
                      selectedIndex: 0,
                      onDestinationSelected: (_) {},
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home),
                          label: Text('Caring'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.inbox),
                          label: Text('Inbox'),
                        ),
                      ],
                    ),
                    const Expanded(
                      child: ColoredBox(color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final railBox = tester.renderObject<RenderBox>(
        find.byType(NavigationRail),
      );
      final caringLabel = tester.renderObject<RenderBox>(
        find.text('Caring'),
      );

      expect(railBox.size.height, closeTo(viewportHeight, 1));
      expect(railBox.localToGlobal(Offset.zero).dx, closeTo(0, 1));
      expect(caringLabel.size.width, greaterThan(20));
      expect(
        caringLabel.localToGlobal(Offset.zero).dx,
        lessThan(railBox.size.width * 0.5),
      );
    });
  });

  group('TenturaContentColumn', () {
    testWidgets('caps width when contentMaxWidth is set', (tester) async {
      const viewportWidth = 853.0;
      double? capturedMaxWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 1280),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 1280)),
            child: TenturaResponsiveScope(
              child: TenturaContentColumn(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    capturedMaxWidth = constraints.maxWidth;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(capturedMaxWidth, 720);
    });

    testWidgets('is a no-op on compact viewport', (tester) async {
      const viewportWidth = 375.0;
      double? capturedMaxWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 812),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 812)),
            child: TenturaResponsiveScope(
              child: TenturaContentColumn(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    capturedMaxWidth = constraints.maxWidth;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(capturedMaxWidth, viewportWidth);
    });

    testWidgets('home shell pattern caps content pane without clipping rail', (
      tester,
    ) async {
      const viewportWidth = 900.0;
      const viewportHeight = 1200.0;
      double? capturedMaxWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, viewportHeight),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(viewportWidth, viewportHeight),
            ),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavigationRail(
                      selectedIndex: 0,
                      onDestinationSelected: (_) {},
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home),
                          label: Text('Home'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: TenturaContentColumn(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            capturedMaxWidth = constraints.maxWidth;
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final railBox = tester.renderObject<RenderBox>(
        find.byType(NavigationRail),
      );

      expect(capturedMaxWidth, 720);
      expect(railBox.localToGlobal(Offset.zero).dx, closeTo(0, 1));
      expect(railBox.size.height, closeTo(viewportHeight, 1));
    });
  });

  group('CardTriageActionRow desktop width', () {
    testWidgets('uses intrinsic forward button width on expanded', (
      tester,
    ) async {
      const viewportWidth = 900.0;
      double? buttonWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 800),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 720,
                    child: CardTriageActionRow(onForward: () {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.descendant(
        of: find.byType(CardTriageActionRow),
        matching: find.byType(OutlinedButton),
      );
      buttonWidth = tester.getSize(buttonFinder).width;

      expect(buttonWidth, lessThan(360));
    });

    testWidgets('stretches forward button on compact', (tester) async {
      const viewportWidth = 375.0;
      double? buttonWidth;
      double? rowWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 812),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 812)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: CardTriageActionRow(onForward: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.descendant(
        of: find.byType(CardTriageActionRow),
        matching: find.byType(OutlinedButton),
      );
      rowWidth = tester.getSize(find.byType(CardTriageActionRow)).width;
      buttonWidth = tester.getSize(buttonFinder).width;

      expect(buttonWidth, greaterThan(rowWidth * 0.7));
    });

    testWidgets('uses parent constraints on expanded viewport', (
      tester,
    ) async {
      const viewportWidth = 900.0;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 800),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 31,
                    child: CardTriageActionRow(
                      onOfferHelp: () async {},
                      onForward: () {},
                      secondaryIcon: Icons.delete_outline,
                      secondaryTooltip: 'Remove',
                      onSecondary: () async {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('showTenturaAdaptiveSheet', () {
    testWidgets('uses a bottom sheet on compact viewport', (tester) async {
      const viewportWidth = 375.0;
      double? capturedMaxWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 812),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 812)),
            child: TenturaResponsiveScope(
              child: Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () => showTenturaAdaptiveSheet<void>(
                      context: context,
                      builder: (_) => LayoutBuilder(
                        builder: (context, constraints) {
                          capturedMaxWidth = constraints.maxWidth;
                          return const SizedBox(height: 80);
                        },
                      ),
                    ),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(capturedMaxWidth, viewportWidth);
    });

    testWidgets('uses constrained dialog on expanded viewport', (tester) async {
      const viewportWidth = 900.0;
      double? capturedMaxWidth;

      await tester.binding.setSurfaceSize(
        const Size(viewportWidth, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(viewportWidth, 900)),
            child: TenturaResponsiveScope(
              child: Builder(
                builder: (context) {
                  return TextButton(
                    onPressed: () => showTenturaAdaptiveSheet<void>(
                      context: context,
                      builder: (_) => LayoutBuilder(
                        builder: (context, constraints) {
                          capturedMaxWidth = constraints.maxWidth;
                          return const SizedBox(height: 80);
                        },
                      ),
                    ),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(capturedMaxWidth, 720);
    });
  });
}
