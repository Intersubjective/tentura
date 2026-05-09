import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  testWidgets(
    'TenturaUnderlineTabs attention uses AnimatedBuilder when motion enabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: TenturaUnderlineTabs(
              tabs: const ['A', 'B', 'C'],
              selectedIndex: 1,
              onChanged: (_) {},
              attentionIndex: 1,
              attentionActive: true,
            ),
          ),
        ),
      );
      await tester.pump();
      final tabsFinder = find.byType(TenturaUnderlineTabs);
      expect(tabsFinder, findsOneWidget);
      expect(
        find.descendant(
          of: tabsFinder,
          matching: find.byType(AnimatedBuilder),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'TenturaUnderlineTabs attention skips AnimatedBuilder when disableAnimations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: TenturaUnderlineTabs(
                tabs: const ['A', 'B', 'C'],
                selectedIndex: 1,
                onChanged: (_) {},
                attentionIndex: 1,
                attentionActive: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final tabsFinder = find.byType(TenturaUnderlineTabs);
      expect(tabsFinder, findsOneWidget);
      expect(
        find.descendant(
          of: tabsFinder,
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'TenturaUnderlineTabs shows primary and secondary badge on same tab',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: TenturaUnderlineTabs(
              tabs: const ['A', 'B', 'C'],
              selectedIndex: 1,
              onChanged: (_) {},
              badges: const [null, 2, null],
              secondaryBadges: const [null, 3, null],
            ),
          ),
        ),
      );
      await tester.pump();
      final tabsFinder = find.byType(TenturaUnderlineTabs);
      expect(tabsFinder, findsOneWidget);
      expect(
        find.descendant(of: tabsFinder, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tabsFinder, matching: find.text('3')),
        findsOneWidget,
      );
    },
  );
}
