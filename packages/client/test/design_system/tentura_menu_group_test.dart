import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rows meet the touch target and share one text keyline', (
    tester,
  ) async {
    await _pump(
      tester,
      TenturaMenuGroup(
        title: 'Account',
        children: [
          TenturaMenuTile(
            key: const Key('a'),
            icon: Icons.key_outlined,
            title: 'Sign-in methods',
            onTap: () {},
          ),
          TenturaMenuTile(
            key: const Key('b'),
            icon: Icons.notifications_outlined,
            title: 'Notification settings',
            subtitle: 'Push, in app and email',
            onTap: () {},
          ),
        ],
      ),
    );

    for (final key in ['a', 'b']) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
    }
    expect(
      tester.getTopLeft(find.text('Sign-in methods')).dx,
      tester.getTopLeft(find.text('Notification settings')).dx,
    );
    expect(
      tester.getTopLeft(find.text('Push, in app and email')).dx,
      tester.getTopLeft(find.text('Notification settings')).dx,
    );
    // Navigation rows say they open a page; one divider between two rows.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
  });

  testWidgets('destructive rows are error-coloured and show no chevron', (
    tester,
  ) async {
    await _pump(
      tester,
      TenturaMenuGroup(
        children: [
          TenturaMenuTile(
            icon: Icons.person_off_outlined,
            title: 'Request profile deletion',
            destructive: true,
            onTap: () {},
          ),
        ],
      ),
    );

    final context = tester.element(find.byType(TenturaMenuTile));
    final title = tester.widget<Text>(find.text('Request profile deletion'));
    expect(title.style?.color, context.tt.danger);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });
}
