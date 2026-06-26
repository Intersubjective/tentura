import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  testWidgets('showSnackBar with action shows close icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSnackBar(
                  context,
                  text: 'Invite saved — find it in the Invitations tab',
                  action: SnackBarAction(
                    label: 'View invitations',
                    onPressed: () {},
                  ),
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('View invitations'), findsOneWidget);
  });

  testWidgets('showSnackBar without action shows close icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSnackBar(
                  context,
                  text: 'Draft saved',
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
