import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';

void main() {
  Widget _harness({
    required TargetPlatform platform,
    required Widget child,
  }) {
    return MaterialApp(
      theme: TenturaTheme.light().copyWith(platform: platform),
      home: Scaffold(body: child),
    );
  }

  testWidgets('Android theme passes child through without SelectionArea', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.android,
        child: const TenturaSelectionArea(
          child: Text('hello'),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('macOS theme wraps child in SelectionArea', (tester) async {
    await tester.pumpWidget(
      _harness(
        platform: TargetPlatform.macOS,
        child: const TenturaSelectionArea(
          child: Text('hello'),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });
}
