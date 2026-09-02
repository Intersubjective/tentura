import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/utils/copy_text_to_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copyTextToClipboard returns true when platform accepts', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') return null;
          return null;
        });
    expect(await copyTextToClipboard('hello'), isTrue);
  });

  test('copyTextToClipboard returns false on PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(
              code: 'copy_fail',
              message: 'Clipboard.setData failed.',
            );
          }
          return null;
        });
    expect(await copyTextToClipboard('hello'), isFalse);
  });
}
