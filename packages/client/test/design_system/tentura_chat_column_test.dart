import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

const _chatKey = Key('chat');

Future<void> _pump(WidgetTester tester, {AlignmentGeometry? alignment}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const chat = TenturaChatColumn(child: SizedBox.expand(key: _chatKey));
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: alignment == null
              ? chat
              : TenturaChatColumnScope(alignment: alignment, child: chat),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a wide chat column is centered by default', (tester) async {
    await _pump(tester);
    final rect = tester.getRect(find.byKey(_chatKey));
    expect(rect.width, lessThan(1600));
    expect(rect.center.dx, closeTo(800, 1));
  });

  testWidgets('beside a list it starts at the pane edge', (tester) async {
    await _pump(tester, alignment: AlignmentDirectional.topStart);
    final rect = tester.getRect(find.byKey(_chatKey));
    expect(rect.width, lessThan(1600));
    expect(rect.left, 0);
  });
}
