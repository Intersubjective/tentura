// #684: the second tap of a double tap on a sheet's last button must not
// land on the page under it while the sheet animates away (it opened
// Questions or the Forward picker right after «Offer help»).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

Future<void> _pumpPage(
  WidgetTester tester, {
  required Size size,
  required VoidCallback onPageTap,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => Stack(
                children: [
                  // The page: every point is a control.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onPageTap,
                    ),
                  ),
                  Align(
                    alignment: Alignment.topLeft,
                    child: TextButton(
                      onPressed: () => showTenturaAdaptiveSheet<void>(
                        context: context,
                        builder: (ctx) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Send'),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final (name, size) in [
    ('bottom sheet (compact)', const Size(390, 844)),
    ('dialog (wide)', const Size(1280, 800)),
  ]) {
    testWidgets('$name: a double tap on its button stays in the sheet', (
      tester,
    ) async {
      var pageTaps = 0;
      await _pumpPage(tester, size: size, onPageTap: () => pageTaps++);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      pageTaps = 0;

      final send = tester.getCenter(find.text('Send'));
      await tester.tapAt(send);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(send);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(send);
      await tester.pumpAndSettle();

      expect(find.text('Send'), findsNothing);
      expect(pageTaps, 0, reason: 'taps right after the close are swallowed');

      // Shortly after, the page takes taps again.
      await tester.tapAt(send);
      await tester.pumpAndSettle();
      expect(pageTaps, 1);
    });
  }
}
