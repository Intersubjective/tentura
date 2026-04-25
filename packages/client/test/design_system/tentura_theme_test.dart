import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  testWidgets('TenturaTheme exposes TenturaTokens extension', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) {
            final tt = context.tt;
            return Scaffold(
              body: Text(
                'x',
                style: TenturaText.status(tt.info),
              ),
            );
          },
        ),
      ),
    );
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('TenturaStatusText renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: TenturaStatusText('active', tone: TenturaTone.good),
        ),
      ),
    );
    expect(find.text('active'), findsOneWidget);
  });
}
