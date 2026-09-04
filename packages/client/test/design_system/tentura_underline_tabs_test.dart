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

  testWidgets(
    'TenturaUnderlineTabs primary badge uses custom background color',
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
              badgeBackgroundColors: [
                null,
                TenturaTokens.light.danger,
                null,
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final badge = tester.widget<TenturaCountBadge>(
        find.byType(TenturaCountBadge),
      );
      expect(badge.backgroundColor, TenturaTokens.light.danger);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs plainText counts skip TenturaCountBadge',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: TenturaUnderlineTabs(
              tabs: const ['A', 'B'],
              selectedIndex: 0,
              onChanged: (_) {},
              badges: const [4, null],
              countStyle: TenturaTabCountStyle.plainText,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TenturaCountBadge), findsNothing);
      expect(find.text('4'), findsOneWidget);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs with icons shows labels when wide enough',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: TenturaUnderlineTabs(
                tabs: const ['Threads', 'People', 'Log'],
                icons: const [
                  Icons.forum_outlined,
                  Icons.people_outline,
                  Icons.history_outlined,
                ],
                selectedIndex: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Threads'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Log'), findsOneWidget);
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
      expect(find.byIcon(Icons.history_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs with icons hides labels when slots are tight',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: TenturaUnderlineTabs(
                tabs: const ['Threads', 'People', 'Journal'],
                icons: const [
                  Icons.forum_outlined,
                  Icons.people_outline,
                  Icons.history_outlined,
                ],
                selectedIndex: 0,
                onChanged: (_) {},
                badges: const [null, 2, null],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Threads'), findsNothing);
      expect(find.text('People'), findsNothing);
      expect(find.text('Journal'), findsNothing);
      expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
      expect(find.byIcon(Icons.history_outlined), findsOneWidget);
      expect(find.byType(TenturaCountBadge), findsOneWidget);

      final threadsSemantics = tester.getSemantics(
        find.byIcon(Icons.forum_outlined),
      );
      expect(
        threadsSemantics.label,
        contains('Threads'),
      );
    },
  );

  testWidgets(
    'TenturaUnderlineTabs badges do not force label hide when icon+text fits',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: TenturaUnderlineTabs(
                tabs: const ['Threads', 'People', 'Log'],
                icons: const [
                  Icons.forum_outlined,
                  Icons.people_outline,
                  Icons.history_outlined,
                ],
                selectedIndex: 1,
                onChanged: (_) {},
                badges: const [null, 2, null],
                secondaryBadges: const [null, 3, null],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Threads'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Log'), findsOneWidget);
      expect(find.byType(TenturaCountBadge), findsNWidgets(2));
    },
  );

  testWidgets(
    'TenturaUnderlineTabs without icons keeps text when narrow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: TenturaUnderlineTabs(
                tabs: const ['Threads', 'People', 'Journal'],
                selectedIndex: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Threads'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Journal'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    },
  );
}
