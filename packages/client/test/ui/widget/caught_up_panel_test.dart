import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/caught_up_panel.dart';

/// U17d / D18 — the reward is a *presentation*, so it is tested as one: what
/// it paints, at what size, with what semantics, and how it behaves when the
/// person has asked the platform for no motion.
Future<void> _pump(
  WidgetTester tester,
  Widget panel, {
  double width = 800,
  double textScale = 1,
  bool disableAnimations = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: CustomScrollView(
              slivers: [SliverToBoxAdapter(child: panel)],
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets('the full panel shows the illustration, title and detail', (
    tester,
  ) async {
    await _pump(
      tester,
      const CaughtUpPanel(
        title: 'You are caught up',
        detail: 'Anything still waiting for your decision stays above.',
      ),
    );

    expect(find.byKey(CaughtUpPanel.illustrationKey), findsOneWidget);
    expect(find.text('You are caught up'), findsOneWidget);
    expect(
      find.text('Anything still waiting for your decision stays above.'),
      findsOneWidget,
    );
    expect(find.byKey(CaughtUpPanel.clearedKey), findsNothing);
  });

  testWidgets('the cleared count is shown only when there is one', (
    tester,
  ) async {
    await _pump(
      tester,
      const CaughtUpPanel(title: 'Caught up', clearedLabel: 'Cleared 7'),
    );

    expect(find.byKey(CaughtUpPanel.clearedKey), findsOneWidget);
    expect(find.text('Cleared 7'), findsOneWidget);
  });

  testWidgets('the compact note is one line with no illustration', (
    tester,
  ) async {
    await _pump(
      tester,
      const CaughtUpPanel(title: 'Nothing needs you right now', compact: true),
    );

    expect(find.text('Nothing needs you right now'), findsOneWidget);
    expect(
      find.byKey(CaughtUpPanel.illustrationKey),
      findsNothing,
      reason: 'a permanent line above a live list is a note, not a trophy',
    );
    expect(
      tester.getSize(find.byKey(CaughtUpPanel.panelKey)).height,
      lessThan(56),
      reason: 'the compact note must not push the work down the screen',
    );
  });

  testWidgets('the whole panel is one semantics container with its copy', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const CaughtUpPanel(
        title: 'Caught up',
        detail: 'Decisions stay above.',
        clearedLabel: 'Cleared 3',
      ),
    );

    final node = tester.getSemantics(find.byKey(CaughtUpPanel.panelKey));
    expect(node.label, contains('Caught up'));
    expect(node.label, contains('Decisions stay above.'));
    expect(
      node.label,
      contains('Cleared 3'),
      reason: 'the number the sweep achieved is part of what is announced',
    );
    handle.dispose();
  });

  testWidgets('with animations disabled the illustration is there at once', (
    tester,
  ) async {
    await _pump(
      tester,
      const CaughtUpPanel(title: 'Caught up'),
      disableAnimations: true,
      settle: false,
    );
    await tester.pump();

    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(CaughtUpPanel.illustrationKey),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
      reason: 'reduced motion means no fade, not a slower one',
    );
  });

  testWidgets('with animations allowed the illustration fades in', (
    tester,
  ) async {
    await _pump(
      tester,
      const CaughtUpPanel(title: 'Caught up'),
      settle: false,
    );
    await tester.pump();

    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(CaughtUpPanel.illustrationKey),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      lessThan(1),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('every line survives 320dp at 2x text scale, unclipped', (
    tester,
  ) async {
    // The trap: a long block in a scroll view at narrow width and 2x silently
    // stops building what follows it, with no overflow error — so this
    // asserts the positive, and asserts height rather than presence, because
    // a one-line clip satisfies "found".
    await _pump(
      tester,
      const CaughtUpPanel(
        title: 'You are caught up',
        detail:
            'You have cleared everything that could be cleared. Anything '
            'still waiting for your decision stays above.',
        clearedLabel: 'Cleared 12',
      ),
      width: 320,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(CaughtUpPanel.illustrationKey), findsOneWidget);
    expect(find.byKey(CaughtUpPanel.clearedKey), findsOneWidget);

    final detail = tester.widget<Text>(find.byKey(CaughtUpPanel.detailKey));
    expect(detail.overflow, isNot(TextOverflow.ellipsis));
    expect(detail.maxLines, isNull);
    expect(
      tester.getSize(find.byKey(CaughtUpPanel.detailKey)).height,
      greaterThan(100),
      reason: 'two sentences at 2x on a 320dp screen are many lines, not one',
    );
    expect(
      tester.getSize(find.byKey(CaughtUpPanel.clearedKey)).height,
      greaterThan(0),
      reason: 'the count below the explanation is still built',
    );
  });
}
