import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

Widget _tabsHarness({
  required Widget child,
  required double width,
  WindowClass? windowClass,
}) {
  final wc = windowClass ?? windowClassForWidth(width);
  final baseTheme = TenturaTheme.light();
  final tokens =
      (baseTheme.extension<TenturaTokens>() ?? TenturaTokens.light)
          .applyWindowClass(wc);
  return MaterialApp(
    theme: baseTheme.copyWith(
      extensions: [
        tokens,
        ...baseTheme.extensions.values.where((e) => e is! TenturaTokens),
      ],
    ),
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: Scaffold(body: child),
    ),
  );
}

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

  testWidgets(
    'TenturaUnderlineTabs without compactIconTabs keeps equal-width Expanded cells',
    (tester) async {
      await tester.pumpWidget(
        _tabsHarness(
          width: 400,
          child: SizedBox(
            width: 400,
            child: TenturaUnderlineTabs(
              tabs: const ['One', 'Two', 'Three'],
              icons: const [
                Icons.star_outline,
                Icons.favorite_outline,
                Icons.history_outlined,
              ],
              selectedIndex: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final inkWells = tester.renderObjectList<RenderBox>(
        find.descendant(
          of: find.byType(TenturaUnderlineTabs),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWells.length, 3);
      final widths = inkWells.map((box) => box.size.width).toList();
      expect(widths[0], closeTo(400 / 3, 0.01));
      expect(widths[1], closeTo(400 / 3, 0.01));
      expect(widths[2], closeTo(400 / 3, 0.01));
    },
  );

  testWidgets(
    'TenturaUnderlineTabs compactIconTabs uses tabCompactWidth and hides label',
    (tester) async {
      await tester.pumpWidget(
        _tabsHarness(
          width: 360,
          child: SizedBox(
            width: 360,
            child: TenturaUnderlineTabs(
              tabs: const ['Now', 'Chat', 'People'],
              icons: const [
                Icons.bolt_outlined,
                Icons.forum_outlined,
                Icons.people_outline,
              ],
              compactIconTabs: const {2},
              selectedIndex: 2,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final tt = TenturaTokens.light.applyWindowClass(WindowClass.compact);
      expect(find.text('People'), findsNothing);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);

      final peopleIcon = find.byIcon(Icons.people_outline);
      final peopleInkWell = tester.renderObject<RenderBox>(
        find.ancestor(of: peopleIcon, matching: find.byType(InkWell)),
      );
      expect(peopleInkWell.size.width, tt.tabCompactWidth);

      final inkWells = tester.renderObjectList<RenderBox>(
        find.descendant(
          of: find.byType(TenturaUnderlineTabs),
          matching: find.byType(InkWell),
        ),
      );
      final flexWidths = inkWells
          .map((box) => box.size.width)
          .where((w) => w != tt.tabCompactWidth)
          .toList();
      expect(flexWidths.length, 2);
      expect(flexWidths[0], closeTo(flexWidths[1], 0.01));
      expect(
        flexWidths[0] + flexWidths[1] + tt.tabCompactWidth,
        closeTo(360, 0.01),
      );
    },
  );

  testWidgets(
    'TenturaUnderlineTabs compactIconTabs exposes tooltip and semantics',
    (tester) async {
      await tester.pumpWidget(
        _tabsHarness(
          width: 360,
          child: TenturaUnderlineTabs(
            tabs: const ['Now', 'Chat', 'People'],
            icons: const [
              Icons.bolt_outlined,
              Icons.forum_outlined,
              Icons.people_outline,
            ],
            compactIconTabs: const {2},
            selectedIndex: 1,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Tooltip), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'People');

      final peopleSemantics = tester.getSemantics(
        find.byIcon(Icons.people_outline),
      );
      expect(peopleSemantics.label, contains('People'));
      expect(peopleSemantics.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(peopleSemantics.hasFlag(SemanticsFlag.isSelected), isFalse);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs compactIconTabs selected exposes selected semantics',
    (tester) async {
      await tester.pumpWidget(
        _tabsHarness(
          width: 360,
          child: TenturaUnderlineTabs(
            tabs: const ['Now', 'Chat', 'People'],
            icons: const [
              Icons.bolt_outlined,
              Icons.forum_outlined,
              Icons.people_outline,
            ],
            compactIconTabs: const {2},
            selectedIndex: 2,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      final peopleSemantics = tester.getSemantics(
        find.byIcon(Icons.people_outline),
      );
      expect(peopleSemantics.hasFlag(SemanticsFlag.isSelected), isTrue);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs _labelsFit reserves compact slot so flex labels show',
    (tester) async {
      // Without the fixed slot, three equal columns would hide all labels.
      await tester.pumpWidget(
        _tabsHarness(
          width: 280,
          child: SizedBox(
            width: 280,
            child: TenturaUnderlineTabs(
              tabs: const ['Now', 'Chat', 'People'],
              icons: const [
                Icons.bolt_outlined,
                Icons.forum_outlined,
                Icons.people_outline,
              ],
              compactIconTabs: const {2},
              selectedIndex: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('People'), findsNothing);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs compactIconTabs badge overlay prefers primary',
    (tester) async {
      await tester.pumpWidget(
        _tabsHarness(
          width: 360,
          child: TenturaUnderlineTabs(
            tabs: const ['Now', 'Chat', 'People'],
            icons: const [
              Icons.bolt_outlined,
              Icons.forum_outlined,
              Icons.people_outline,
            ],
            compactIconTabs: const {2},
            selectedIndex: 0,
            onChanged: (_) {},
            badges: const [null, null, 2],
            secondaryBadges: const [null, null, 3],
            badgeBackgroundColors: [
              null,
              null,
              TenturaTokens.light.danger,
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TenturaCountBadge), findsOneWidget);
      final badge = tester.widget<TenturaCountBadge>(
        find.byType(TenturaCountBadge),
      );
      expect(badge.count, 2);
      expect(badge.backgroundColor, TenturaTokens.light.danger);
      expect(find.text('3'), findsNothing);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs compactIconTabs badge overlay shows secondary alone',
    (tester) async {
      await tester.pumpWidget(
        _tabsHarness(
          width: 360,
          child: TenturaUnderlineTabs(
            tabs: const ['Now', 'Chat', 'People'],
            icons: const [
              Icons.bolt_outlined,
              Icons.forum_outlined,
              Icons.people_outline,
            ],
            compactIconTabs: const {2},
            selectedIndex: 0,
            onChanged: (_) {},
            secondaryBadges: const [null, null, 3],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(TenturaCountBadge), findsOneWidget);
      final badge = tester.widget<TenturaCountBadge>(
        find.byType(TenturaCountBadge),
      );
      expect(badge.count, 3);
      expect(badge.backgroundColor, TenturaTokens.light.warn);
    },
  );

  testWidgets(
    'TenturaUnderlineTabs every cell hit target is at least 48dp tall',
    (tester) async {
      for (final wc in WindowClass.values) {
        final width = switch (wc) {
          WindowClass.compact => 360.0,
          WindowClass.regular => 700.0,
          WindowClass.expanded => 900.0,
        };
        await tester.pumpWidget(
          _tabsHarness(
            width: width,
            windowClass: wc,
            child: SizedBox(
              width: width,
              child: TenturaUnderlineTabs(
                tabs: const ['Now', 'Chat', 'People'],
                icons: const [
                  Icons.bolt_outlined,
                  Icons.forum_outlined,
                  Icons.people_outline,
                ],
                compactIconTabs: const {2},
                selectedIndex: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();

        for (final inkWell in find.byType(InkWell).evaluate()) {
          final size = (inkWell.renderObject! as RenderBox).size;
          expect(
            size.height,
            greaterThanOrEqualTo(kMinInteractiveDimension),
            reason: 'InkWell height at $wc',
          );
        }
      }
    },
  );
}
