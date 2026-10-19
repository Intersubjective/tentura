// #470: only blocking bars stay on screen. A caller marks a bar blocking
// with `persist: true` (same name as `SnackBar.persist`); it must survive any
// timeout and leave only through its close icon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  testWidgets('blocking error bar stays until its close icon is tapped', (
    tester,
  ) async {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(GetIt.I.reset);
    await _pumpHost(
      tester,
      onShow: (context) => showSnackBar(
        context,
        text: 'Your session expired. Sign in again to continue.',
        isError: true,
        persist: true,
      ),
    );
    await _showAndSettleEntrance(tester);

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}

/// Mounts a screen whose button raises a bar through the app helper.
Future<void> _pumpHost(
  WidgetTester tester, {
  required void Function(BuildContext context) onShow,
}) => tester.pumpWidget(
  MaterialApp(
    theme: TenturaTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onShow(context),
            child: const Text('Show'),
          ),
        ),
      ),
    ),
  ),
);

/// Taps Show and lets the entrance animation finish so the messenger arms
/// its timeout timer (it does so on the build after the bar is fully shown).
Future<void> _showAndSettleEntrance(WidgetTester tester) async {
  await tester.tap(find.text('Show'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  expect(find.byType(SnackBar), findsOneWidget);
}
