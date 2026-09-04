import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/widget/accordion_expansion.dart';

void main() {
  Widget wrap(Widget child, {required Size size}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: TenturaTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('AccordionExpansionGroup compact', () {
    const compact = Size(375, 812);

    testWidgets('opening second tile collapses first', (tester) async {
      await tester.binding.setSurfaceSize(compact);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          const AccordionExpansionGroup(
            accordionMode: true,
            initialExpandedId: 'a',
            child: Column(
              children: [
                AccordionExpansionTile(
                  id: 'a',
                  title: Text('Section A'),
                  children: [Text('Body A')],
                ),
                AccordionExpansionTile(
                  id: 'b',
                  title: Text('Section B'),
                  children: [Text('Body B')],
                ),
              ],
            ),
          ),
          size: compact,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Body A'), findsOneWidget);
      expect(find.text('Body B'), findsNothing);

      await tester.tap(find.text('Section B'));
      await tester.pumpAndSettle();

      expect(find.text('Body A'), findsNothing);
      expect(find.text('Body B'), findsOneWidget);
    });

    testWidgets('requestedExpandedId update switches open section', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(compact);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return const AccordionExpansionGroup(
                accordionMode: true,
                initialExpandedId: 'a',
                requestedExpandedId: 'b',
                child: Column(
                  children: [
                    AccordionExpansionTile(
                      id: 'a',
                      title: Text('Section A'),
                      children: [Text('Body A')],
                    ),
                    AccordionExpansionTile(
                      id: 'b',
                      title: Text('Section B'),
                      children: [Text('Body B')],
                    ),
                  ],
                ),
              );
            },
          ),
          size: compact,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Body B'), findsOneWidget);
      expect(find.text('Body A'), findsNothing);
    });
  });

  group('AccordionExpansionGroup regular', () {
    const regular = Size(800, 600);

    testWidgets('both tiles can stay expanded', (tester) async {
      await tester.binding.setSurfaceSize(regular);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          const AccordionExpansionGroup(
            accordionMode: false,
            child: Column(
              children: [
                AccordionExpansionTile(
                  id: 'a',
                  initiallyExpanded: true,
                  title: Text('Section A'),
                  children: [Text('Body A')],
                ),
                AccordionExpansionTile(
                  id: 'b',
                  initiallyExpanded: true,
                  title: Text('Section B'),
                  children: [Text('Body B')],
                ),
              ],
            ),
          ),
          size: regular,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Body A'), findsOneWidget);
      expect(find.text('Body B'), findsOneWidget);
    });
  });

  group('AccordionExpansionGroup PageStorage isolation', () {
    const regular = Size(800, 600);

    Widget buildAtSharedSlot({Key? groupKey}) => ListView(
      key: const PageStorageKey<String>('shared-slot'),
      children: [
        SizedBox(
          height: 2000,
          child: AccordionExpansionGroup(
            key: groupKey,
            accordionMode: false,
            child: const Column(
              children: [
                AccordionExpansionTile(
                  id: 'a',
                  title: Text('Section A'),
                  children: [Text('Body A')],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    testWidgets(
      'tile does not crash reading a scrollable-owned PageStorage slot',
      (tester) async {
        // A ListView's own scroll position and a nested AccordionExpansionTile
        // with no distinguishing key of its own both resolve to the same
        // PageStorage identifier when the ListView carries the only
        // PageStorageKey in the ancestry (as updates_screen.dart's
        // CustomScrollView does). Scrolling writes a non-bool value into that
        // shared slot; remounting the tile afterwards used to crash reading
        // it back as `bool?`.
        await tester.pumpWidget(wrap(buildAtSharedSlot(), size: regular));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          wrap(buildAtSharedSlot(groupKey: UniqueKey()), size: regular),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('AccordionExpansionTile onExpansionChanged', () {
    const regular = Size(800, 600);

    testWidgets('callback fires when title is tapped', (tester) async {
      await tester.binding.setSurfaceSize(regular);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final opens = <bool>[];
      await tester.pumpWidget(
        wrap(
          AccordionExpansionGroup(
            accordionMode: false,
            child: Column(
              children: [
                AccordionExpansionTile(
                  id: 'a',
                  title: const Text('Section A'),
                  onExpansionChanged: opens.add,
                  children: const [Text('Body A')],
                ),
              ],
            ),
          ),
          size: regular,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Body A'), findsNothing);

      await tester.tap(find.text('Section A'));
      await tester.pumpAndSettle();

      expect(opens, [true]);
      expect(find.text('Body A'), findsOneWidget);

      await tester.tap(find.text('Section A'));
      await tester.pumpAndSettle();

      expect(opens, [true, false]);
    });
  });

  group('AccordionExpansionTile headerAction', () {
    const regular = Size(800, 600);

    testWidgets('tapping headerAction does not collapse expanded body', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(regular);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          AccordionExpansionGroup(
            accordionMode: false,
            child: Column(
              children: [
                AccordionExpansionTile(
                  id: 'a',
                  initiallyExpanded: true,
                  title: const Text('Section A'),
                  headerAction: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Action'),
                  ),
                  children: const [Text('Body A')],
                ),
              ],
            ),
          ),
          size: regular,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Body A'), findsOneWidget);

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(find.text('Body A'), findsOneWidget);
    });
  });
}
