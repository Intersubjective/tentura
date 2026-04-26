import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  testWidgets('TenturaTheme exposes TenturaTokens extension', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) {
            final tt = context.tt;
            return Scaffold(
              body: Text(
                'x',
                style: TenturaText.status(tt.info),
              ),
            );
          },
        ),
      ),
    );
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('TenturaStatusText renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: TenturaStatusText('active', tone: TenturaTone.good),
        ),
      ),
    );
    expect(find.text('active'), findsOneWidget);
  });

  testWidgets('NavigationBar selected label uses onSurface (light)', (
    tester,
  ) async {
    late ColorScheme scheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) {
            scheme = Theme.of(context).colorScheme;
            return Scaffold(
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.inbox_outlined),
                    selectedIcon: Icon(Icons.inbox),
                    label: 'A',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.work_outline),
                    selectedIcon: Icon(Icons.work),
                    label: 'B',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    final barFinder = find.byType(NavigationBar);
    expect(barFinder, findsOneWidget);

    final selectedLabel = tester.widget<Text>(
      find.descendant(of: barFinder, matching: find.text('A')),
    );
    final unselectedLabel = tester.widget<Text>(
      find.descendant(of: barFinder, matching: find.text('B')),
    );

    expect(selectedLabel.style?.color, scheme.onSurface);
    expect(unselectedLabel.style?.color, scheme.onSurfaceVariant);

    final selectedIconCtx = tester.element(
      find.descendant(of: barFinder, matching: find.byIcon(Icons.inbox)),
    );
    expect(IconTheme.of(selectedIconCtx).color, scheme.onPrimary);
  });

  testWidgets('NavigationBar selected label uses onSurface (dark)', (
    tester,
  ) async {
    late ColorScheme scheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.dark(),
        home: Builder(
          builder: (context) {
            scheme = Theme.of(context).colorScheme;
            return Scaffold(
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.inbox_outlined),
                    selectedIcon: Icon(Icons.inbox),
                    label: 'A',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.work_outline),
                    selectedIcon: Icon(Icons.work),
                    label: 'B',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    final barFinder = find.byType(NavigationBar);
    expect(barFinder, findsOneWidget);

    final selectedLabel = tester.widget<Text>(
      find.descendant(of: barFinder, matching: find.text('A')),
    );
    final unselectedLabel = tester.widget<Text>(
      find.descendant(of: barFinder, matching: find.text('B')),
    );

    expect(selectedLabel.style?.color, scheme.onSurface);
    expect(unselectedLabel.style?.color, scheme.onSurfaceVariant);

    final selectedIconCtx = tester.element(
      find.descendant(of: barFinder, matching: find.byIcon(Icons.inbox)),
    );
    expect(
      IconTheme.of(selectedIconCtx).color,
      scheme.onSecondaryContainer,
    );
  });
}
