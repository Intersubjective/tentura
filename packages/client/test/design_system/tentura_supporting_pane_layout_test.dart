import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: TenturaSupportingPaneScope(
            builder: (context) => TenturaSupportingPaneLayout(
              primarySlivers: const [
                SliverToBoxAdapter(child: Text('primary')),
              ],
              supportingSlivers: const [
                SliverToBoxAdapter(child: Text('supporting')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: supporting pane beside primary, fixed width', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 900));

    expect(find.byKey(TenturaSupportingPaneLayout.supportingKey), findsOne);
    expect(
      tester
          .getSize(find.byKey(TenturaSupportingPaneLayout.supportingKey))
          .width,
      TenturaSpacing.supportingPaneWidth,
    );
    expect(
      tester.getTopLeft(find.text('supporting')).dx,
      greaterThan(tester.getTopRight(find.text('primary')).dx),
    );
  });

  testWidgets('narrow: one column, primary first', (tester) async {
    await _pump(tester, const Size(390, 844));

    expect(find.byKey(TenturaSupportingPaneLayout.supportingKey), findsNothing);
    expect(
      tester.getTopLeft(find.text('supporting')).dy,
      greaterThan(tester.getTopLeft(find.text('primary')).dy),
    );
  });
}
