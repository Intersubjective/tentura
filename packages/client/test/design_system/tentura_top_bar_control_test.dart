import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

Future<void> _pump(WidgetTester tester, {required bool collapsed}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Center(
              child: TenturaTopBarControl(
                label: 'Active',
                icon: Icons.filter_list,
                trailingIcon: Icons.arrow_drop_down,
                tooltip: 'Filter',
                collapsed: collapsed,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('labelled: the label with its trailing glyph', (tester) async {
    await _pump(tester, collapsed: false);

    expect(find.text('Active'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.byIcon(Icons.filter_list), findsNothing);
    final width = TenturaTopBarControl.expandedWidth(
      tester.element(find.text('Active')),
      'Active',
    );
    expect(
      tester.getSize(find.byType(TextButton)).width,
      lessThanOrEqualTo(width),
    );
  });

  testWidgets('collapsed: an icon button; the label moves to the tooltip', (
    tester,
  ) async {
    await _pump(tester, collapsed: true);

    expect(find.text('Active'), findsNothing);
    expect(find.byIcon(Icons.filter_list), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).tooltip,
      'Filter: Active',
    );
  });
}
