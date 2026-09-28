import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  bool withList = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: TenturaListDetailLayout(
            list: withList ? const Text('list') : null,
            detail: const Text('detail'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: 440 dp list pane before the detail', (tester) async {
    await _pump(tester, const Size(1440, 900));

    final pane = find.byKey(TenturaListDetailLayout.listPaneKey);
    expect(tester.getSize(pane).width, TenturaSpacing.listPaneWidth);
    expect(
      tester.getTopLeft(find.text('detail')).dx,
      greaterThanOrEqualTo(TenturaSpacing.listPaneWidth),
    );
  });

  testWidgets('narrow: detail only', (tester) async {
    await _pump(tester, const Size(390, 844));

    expect(find.text('list'), findsNothing);
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('no source list: detail only', (tester) async {
    await _pump(tester, const Size(1440, 900), withList: false);

    expect(find.byKey(TenturaListDetailLayout.listPaneKey), findsNothing);
  });
}
