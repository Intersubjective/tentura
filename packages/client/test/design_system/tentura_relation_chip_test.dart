import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

Future<TenturaTokens> _pumpChip(
  WidgetTester tester, {
  required TenturaRelationTone tone,
  String label = 'Helping',
  IconData? icon,
}) async {
  late TenturaTokens tokens;
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (context) {
              tokens = context.tt;
              return Center(
                child: TenturaRelationChip(
                  label: label,
                  tone: tone,
                  icon: icon,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tokens;
}

Color _chipBackground(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(TenturaRelationChip),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('renders the label', (tester) async {
    await _pumpChip(tester, tone: TenturaRelationTone.helping);
    expect(find.text('Helping'), findsOneWidget);
  });

  testWidgets('tones are visually distinct and token-derived', (tester) async {
    final tokens = await _pumpChip(
      tester,
      tone: TenturaRelationTone.helping,
    );
    final helping = _chipBackground(tester);

    await _pumpChip(
      tester,
      tone: TenturaRelationTone.following,
      label: 'Following',
    );
    final following = _chipBackground(tester);

    expect(helping, isNot(following));
    expect(helping.value, TenturaRelationTone.helping.container(tokens).value);
    expect(
      following.value,
      TenturaRelationTone.following.container(tokens).value,
    );
  });

  testWidgets('label honours the metadata type floor (>= 13)', (tester) async {
    await _pumpChip(tester, tone: TenturaRelationTone.following);
    final text = tester.widget<Text>(find.text('Helping'));
    expect(text.style!.fontSize, greaterThanOrEqualTo(13));
  });

  testWidgets('exposes the label to semantics once', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpChip(tester, tone: TenturaRelationTone.helping);
    expect(
      find.bySemanticsLabel('Helping'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('renders an optional leading icon', (tester) async {
    await _pumpChip(
      tester,
      tone: TenturaRelationTone.helping,
      icon: Icons.favorite,
    );
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });
}
