import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  testWidgets('TenturaVerticalResizeHandle reports horizontal drag delta', (
    tester,
  ) async {
    final deltas = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(
              height: 200,
              child: Row(
                children: [
                  const Expanded(child: SizedBox.expand()),
                  TenturaVerticalResizeHandle(
                    onDragDelta: deltas.add,
                  ),
                  const SizedBox(width: 120, child: ColoredBox(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final handle = find.byType(TenturaVerticalResizeHandle);
    expect(handle, findsOneWidget);

    await tester.drag(handle, const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(deltas, isNotEmpty);
    expect(deltas.reduce((a, b) => a + b), closeTo(-40, 1));
  });
}
