import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  group('TenturaFullBleed', () {
    testWidgets('expands child to viewport width inside capped scope', (
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
              child: TenturaFullBleed(
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

    testWidgets('expands at regular/expanded breakpoint widths', (
      tester,
    ) async {
      for (final width in [839.0, 840.0, 600.0]) {
        double? capturedMaxWidth;

        await tester.binding.setSurfaceSize(Size(width, 1280));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 1280)),
              child: TenturaResponsiveScope(
                child: TenturaFullBleed(
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

        expect(capturedMaxWidth, width, reason: 'width=$width');
      }
    });

    testWidgets('NavigationRail stretches to scaffold body height', (
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
              child: TenturaFullBleed(
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
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffoldBox = tester.renderObject<RenderBox>(
        find.byType(Scaffold),
      );
      final railBox = tester.renderObject<RenderBox>(
        find.byType(NavigationRail),
      );

      expect(railBox.size.height, closeTo(scaffoldBox.size.height, 0.1));
    });
  });
}
