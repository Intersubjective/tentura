import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

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

  // #426: the error bar's Copy action kept the inverse-surface action colour
  // (light pink) on the light error container and read as disabled.
  testWidgets('error snack bar action uses the error container foreground', (
    tester,
  ) async {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(GetIt.I.reset);
    final theme = TenturaTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showSnackBar(
                  context,
                  text: 'Description is required',
                  isError: true,
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

    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    expect(action.textColor, theme.colorScheme.onErrorContainer);
  });
}
