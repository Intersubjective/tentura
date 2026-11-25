import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const _header = 'Invitation Code';
final _link = Uri.parse('https://tentura.example/invite/I123456789abc');

void main() {
  testWidgets('sharing a personal invitation adds its message while ordinary '
      'link sharing keeps its existing payload', (tester) async {
    final sent = <Map<Object?, Object?>>[];
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(_shareChannel, (call) async {
        expect(call.method, 'share');
        sent.add(call.arguments as Map<Object?, Object?>);
        return 'dev.fluttercommunity.plus/share/success';
      });
    addTearDown(() => messenger.setMockMethodCallHandler(_shareChannel, null));

    const personalLine = 'Anna, would you like to join our group?';
    final payload = '$personalLine\n$_link';
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => _open(context),
                  child: const Text('Ordinary invitation'),
                ),
                TextButton(
                  onPressed: () => _open(context, text: payload),
                  child: const Text('Personal invitation'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await _tap(tester, 'Ordinary invitation');
    await _tap(tester, 'Share link');
    final ordinary = sent.single;
    expect(ordinary, containsPair('uri', _link.toString()));
    expect(ordinary, containsPair('subject', _header));
    expect(ordinary, containsPair('title', 'Share link'));
    expect(ordinary.containsKey('text'), isFalse);
    await _tap(tester, 'Close');

    await _tap(tester, 'Personal invitation');
    await _tap(tester, 'Share link');
    expect(sent, hasLength(2));
    expect(sent.last['text'], payload);
  });
}

void _open(BuildContext context, {String? text}) {
  // The current dialog can already share a link. Exercise that path on the
  // baseline so the test reports the missing message in a real share payload.
  const Function show = ShareCodeDialog.show;
  if (text != null &&
      show
          is Future<bool> Function(
            BuildContext, {
            required String header,
            required Uri link,
            String? text,
          })) {
    unawaited(show(context, header: _header, link: _link, text: text));
  } else {
    unawaited(ShareCodeDialog.show(context, header: _header, link: _link));
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final control = find.text(label);
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}
