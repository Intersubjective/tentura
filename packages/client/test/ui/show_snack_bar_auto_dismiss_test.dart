// #470: non-blocking bars must auto-dismiss after ~4-6 s. A SnackBar with an
// action defaults to `persist: true` in this Flutter (snack_bar.dart: `persist
// ?? action != null`), so every bar with an action - and every error bar,
// which always gets the Copy action - stayed until the close icon was tapped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  testWidgets('success bar with an action auto-dismisses within 6 s', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      onShow: (context) => showSnackBar(
        context,
        text: 'Invite saved — find it in the Invitations tab',
        action: SnackBarAction(label: 'View invitations', onPressed: () {}),
      ),
    );
    await _showAndSettleEntrance(tester);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('non-blocking error bar auto-dismisses within 6 s', (
    tester,
  ) async {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(GetIt.I.reset);
    await _pumpHost(
      tester,
      onShow: (context) => showSnackBar(
        context,
        text: 'Something went wrong. Please try again.',
        isError: true,
      ),
    );
    await _showAndSettleEntrance(tester);
    // The error bar keeps its Copy action; dismissal must not depend on
    // dropping it.
    expect(find.byType(SnackBarAction), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('bar is still visible before its timeout elapses', (
    tester,
  ) async {
    // Guard against a fix that hides bars too early: ~4 s is the floor, so the
    // bar must still be on screen 3.9 s after it was fully shown.
    await _pumpHost(
      tester,
      onShow: (context) => showSnackBar(
        context,
        text: 'Invite saved — find it in the Invitations tab',
        action: SnackBarAction(label: 'View invitations', onPressed: () {}),
      ),
    );
    await _showAndSettleEntrance(tester);

    await tester.pump(const Duration(milliseconds: 3900));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).persist,
      isFalse,
    );
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
