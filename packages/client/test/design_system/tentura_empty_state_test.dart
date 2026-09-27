import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(child: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows icon, title and the full explanation', (tester) async {
    const body =
        'Requests you decline land here. You can bring any of them back.';
    await _pump(
      tester,
      const TenturaEmptyState(
        icon: Icons.archive_outlined,
        title: 'No declined requests',
        body: body,
      ),
    );

    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    expect(find.text('No declined requests'), findsOneWidget);
    final bodyText = tester.widget<Text>(find.byKey(TenturaEmptyState.bodyKey));
    expect(bodyText.data, body);
    expect(bodyText.maxLines, isNull, reason: 'the explanation never clips');
    expect(find.byKey(TenturaEmptyState.actionKey), findsNothing);
  });

  testWidgets('action renders only with both label and callback', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      TenturaEmptyState(
        icon: Icons.people_outline,
        title: 'No people yet',
        actionLabel: 'Create invitation',
        onAction: () => taps++,
      ),
    );

    await tester.tap(find.byKey(TenturaEmptyState.actionKey));
    expect(taps, 1);
    expect(
      tester.getSize(find.byKey(TenturaEmptyState.actionKey)).height,
      greaterThanOrEqualTo(40),
    );
  });

  testWidgets('keeps a readable measure on wide screens', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      const TenturaEmptyState(
        icon: Icons.visibility_outlined,
        title: 'Nothing to follow yet.',
        body: 'Tap Follow on a Request to keep up with its updates here.',
      ),
    );

    expect(
      tester.getSize(find.byKey(TenturaEmptyState.bodyKey)).width,
      lessThanOrEqualTo(TenturaSpacing.emptyStateMaxWidth),
    );
  });
}
