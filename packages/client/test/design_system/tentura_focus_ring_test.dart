import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

// #499: keyboard focus was shown only as a faint grey fill. Focused controls
// must get a 2 dp outline in primary blue with >= 3:1 contrast.

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

class _Controls {
  final filled = FocusNode(debugLabel: 'filled');
  final outlined = FocusNode(debugLabel: 'outlined');
  final text = FocusNode(debugLabel: 'text');
  final icon = FocusNode(debugLabel: 'icon');
  final tile = FocusNode(debugLabel: 'tile');
  final chip = FocusNode(debugLabel: 'chip');
  final card = FocusNode(debugLabel: 'card');
  final field = FocusNode(debugLabel: 'field');

  List<(String, FocusNode)> get ringed => [
    ('FilledButton', filled),
    ('OutlinedButton', outlined),
    ('TextButton', text),
    ('IconButton', icon),
    ('ListTile', tile),
    ('ActionChip', chip),
    ('Card InkWell', card),
  ];

  void dispose() {
    for (final n in [filled, outlined, text, icon, tile, chip, card, field]) {
      n.dispose();
    }
  }
}

Future<ThemeData> _pump(
  WidgetTester tester,
  _Controls c, {
  required ThemeData theme,
}) async {
  late ThemeData resolved;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => TenturaFocusRing(child: child!),
      home: Builder(
        builder: (context) {
          resolved = Theme.of(context);
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton(
                    focusNode: c.filled,
                    onPressed: () {},
                    child: const Text('Filled'),
                  ),
                  OutlinedButton(
                    focusNode: c.outlined,
                    onPressed: () {},
                    child: const Text('Outlined'),
                  ),
                  TextButton(
                    focusNode: c.text,
                    onPressed: () {},
                    child: const Text('Text'),
                  ),
                  IconButton(
                    focusNode: c.icon,
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                  ),
                  SizedBox(
                    width: 300,
                    child: ListTile(
                      focusNode: c.tile,
                      onTap: () {},
                      title: const Text('Tile'),
                    ),
                  ),
                  ActionChip(
                    focusNode: c.chip,
                    onPressed: () {},
                    label: const Text('Chip'),
                  ),
                  SizedBox(
                    width: 300,
                    child: Card(
                      child: InkWell(
                        focusNode: c.card,
                        onTap: () {},
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Card'),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(focusNode: c.field),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  return resolved;
}

void main() {
  late _Controls c;

  setUp(() {
    c = _Controls();
  });

  tearDown(() {
    c.dispose();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  final ring = find.byKey(TenturaFocusRing.ringKey);

  for (final (mode, makeTheme) in [
    ('light', TenturaTheme.light),
    ('dark', TenturaTheme.dark),
  ]) {
    testWidgets(
      'keyboard-focused controls get a 2 dp primary outline ($mode)',
      (tester) async {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        final theme = await _pump(tester, c, theme: makeTheme());
        await tester.pump();
        expect(ring, findsNothing, reason: 'nothing focused yet');

        for (final (name, node) in c.ringed) {
          node.requestFocus();
          await tester.pump();
          await tester.pump();

          expect(ring, findsOneWidget, reason: '$name has no focus ring');
          final box = tester.widget<DecoratedBox>(ring);
          final border = (box.decoration as BoxDecoration).border! as Border;
          for (final side in [
            border.top,
            border.right,
            border.bottom,
            border.left,
          ]) {
            expect(side.width, 2, reason: name);
            expect(side.color, theme.colorScheme.primary, reason: name);
          }

          // Ring sits outside the control: 2 dp gap + 2 dp stroke.
          final ringRect = tester.getRect(ring);
          expect(
            ringRect,
            rectMoreOrLessEquals(node.rect.inflate(4)),
            reason: name,
          );
        }
      },
    );

    test('focus ring colour is >= 3:1 against surfaces and the focus fill '
        '($mode)', () {
      final theme = makeTheme();
      final scheme = theme.colorScheme;
      final ringColor = scheme.primary;
      final fill = Color.alphaBlend(theme.focusColor, scheme.surface);
      for (final bg in [
        scheme.surface,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerHighest,
        fill,
      ]) {
        expect(_contrast(ringColor, bg), greaterThanOrEqualTo(3));
      }
    });
  }

  testWidgets('no ring when focus follows touch, ring follows focus moves', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await _pump(tester, c, theme: TenturaTheme.light());
    c.filled.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsNothing);

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    await tester.pump();
    expect(ring, findsOneWidget);
    expect(
      tester.getRect(ring),
      rectMoreOrLessEquals(c.filled.rect.inflate(4)),
    );

    c.icon.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(ring), rectMoreOrLessEquals(c.icon.rect.inflate(4)));

    c.icon.unfocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsNothing);
  });

  testWidgets('text fields keep their own focused border, no extra ring', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await _pump(tester, c, theme: TenturaTheme.light());
    c.field.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsNothing);
  });

  testWidgets('a screen-sized focus scope gets no ring', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final node = FocusNode(debugLabel: 'screen');
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        builder: (context, child) => TenturaFocusRing(child: child!),
        home: Focus(
          focusNode: node,
          child: const Scaffold(body: Text('screen')),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsNothing);
  });

  testWidgets('a control that draws its own ring opts out with exclude', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final own = FocusNode(debugLabel: 'own');
    addTearDown(own.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        builder: (context, child) => TenturaFocusRing(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TenturaFocusRing.exclude(
                child: TextButton(
                  focusNode: own,
                  onPressed: () {},
                  child: const Text('Own ring'),
                ),
              ),
              FilledButton(
                focusNode: c.filled,
                onPressed: () {},
                child: const Text('Filled'),
              ),
            ],
          ),
        ),
      ),
    );
    own.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(own.hasPrimaryFocus, isTrue);
    expect(ring, findsNothing);

    // Guard: the sibling outside the opt-out is still ringed.
    c.filled.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsOneWidget);
  });
}
