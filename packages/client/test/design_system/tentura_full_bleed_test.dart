import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

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
  });
}
