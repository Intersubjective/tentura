import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/qr_code.dart';

const _link = 'https://tentura.example/invite/Iabc123';

/// Answers `Clipboard.setData` like a browser that allows ([accept]) or
/// refuses the write.
void _mockClipboard(WidgetTester tester, {required bool accept}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData' && !accept) {
        throw PlatformException(code: 'copy_fail');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: const Scaffold(
        body: ShareCodeDialog(header: 'Invitation Code', link: _link),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('share dialog exposes invitation URL as selectable text', (
    tester,
  ) async {
    const link = 'https://tentura.example/invite/Iabc123';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: ShareCodeDialog(
            header: 'Invitation Code',
            link: link,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(link), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('Copy to clipboard'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
  });

  testWidgets('optional caption renders under the QR and is not the link', (
    tester,
  ) async {
    const link = 'https://tentura.example/invite/Iabc123';
    const caption =
        'This link works if they are new to Tentura or already have an account.';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: ShareCodeDialog(
            header: 'Invitation Code',
            link: link,
            caption: caption,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(caption), findsOneWidget);
    expect(find.text(link), findsOneWidget);
  });

  testWidgets('share link tap does not throw when render box is ready', (
    tester,
  ) async {
    const link = 'https://tentura.example/invite/Iabc123';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: const Scaffold(
          body: ShareCodeDialog(
            header: 'Invitation Code',
            link: link,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share link'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  // #349: copying gave no feedback when the browser refused the clipboard.
  testWidgets('copy says so when the link was copied', (tester) async {
    _mockClipboard(tester, accept: true);
    await _pumpDialog(tester);

    await tester.ensureVisible(find.text('Copy to clipboard'));
    await tester.tap(find.text('Copy to clipboard'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The link has been copied to the clipboard',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('copy says so when the browser refused the clipboard', (
    tester,
  ) async {
    _mockClipboard(tester, accept: false);
    await _pumpDialog(tester);

    await tester.ensureVisible(find.text('Copy to clipboard'));
    await tester.tap(find.text('Copy to clipboard'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Couldn't copy the link. Select it above to copy it.",
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  // #452: on desktop the QR is rarely the primary path, so the link and
  // Copy come first and the QR waits behind a "Show QR" control.
  testWidgets('desktop dialog leads with link and copy, QR behind a toggle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpDialog(tester);

    expect(find.byType(QrCode), findsNothing);

    final linkTop = tester.getTopLeft(find.text(_link)).dy;
    final copyTop = tester.getTopLeft(find.text('Copy to clipboard')).dy;
    final shareTop = tester.getTopLeft(find.text('Share link')).dy;
    expect(linkTop, lessThan(copyTop));
    expect(copyTop, lessThanOrEqualTo(shareTop));

    final showQr = find.textContaining('QR');
    expect(showQr, findsOneWidget);
    await tester.ensureVisible(showQr);
    await tester.tap(showQr);
    await tester.pumpAndSettle();

    expect(find.byType(QrCode), findsOneWidget);
    expect(tester.getTopLeft(find.byType(QrCode)).dy, greaterThan(linkTop));
  });

  // #452 guard: the request wording belongs to request invites only; the
  // same dialog also shares a profile link.
  testWidgets('plain share dialog does not talk about a request', (
    tester,
  ) async {
    await _pumpDialog(tester);

    expect(find.textContaining('request'), findsNothing);
    expect(
      find.text('Invite someone to help with this request'),
      findsNothing,
    );
  });
  // #605: on desktop the link is selectable text; selecting it by hand (to
  // copy it without the Copy button) counts as used, like Copy and Share.
  testWidgets('desktop: selecting the link by hand counts as used', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final used = ValueNotifier<bool>(false);
    addTearDown(used.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: ShareCodeDialog(
            header: 'Invitation Code',
            link: _link,
            used: used,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Guard: just showing the link-first dialog is not a use.
    expect(used.value, isFalse);

    final box = tester.getRect(find.text(_link));
    final gesture = await tester.startGesture(
      box.centerLeft + const Offset(1, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(box.centerRight - const Offset(1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(used.value, isTrue);
  });
}
