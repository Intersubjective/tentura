import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Rect _viewport(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

void _expectFullyVisible(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  final view = _viewport(tester);
  expect(rect.top, greaterThanOrEqualTo(view.top));
  expect(rect.bottom, lessThanOrEqualTo(view.bottom + 0.5));
}

Future<void> _openDialog(WidgetTester tester) async {
  const viewport = Size(375, 667);
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final l10n = lookupL10n(const Locale('en'));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ShareCodeDialog.show(
              context,
              header: l10n.forwardInviteDialogTitlePost,
              caption: l10n.forwardInviteDialogBodyPost(7),
              link: Uri.parse('https://dev.tentura.io/invite/Iabc123'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('#790 Post invite dialog keeps Copy visible at 375×667', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await _openDialog(tester);

    expect(find.text(l10n.shareDialogShowQr), findsOneWidget);
    _expectFullyVisible(
      tester,
      find.widgetWithText(OutlinedButton, l10n.copyToClipboard),
    );
    expect(tester.takeException(), isNull);
  });
}
