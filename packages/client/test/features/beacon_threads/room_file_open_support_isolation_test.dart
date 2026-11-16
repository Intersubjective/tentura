// The room_file_open_support helpers must leave global state as they found it.

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
// Transitive dependency: the platform seam under share_plus.
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/room_file_open_support.dart';

void main() {
  late SharePlatform before;
  late Level levelBefore;

  setUpAll(() {
    before = SharePlatform.instance;
    levelBefore = Logger.root.level;
  });

  group('helper users', () {
    late RecordingShare share;
    setUpAll(() => share = installRecordingShare());

    test('installs the recording fake while active', () {
      expect(SharePlatform.instance, same(share));
    });

    test('LogCapture raises the level while active', () async {
      final logs = LogCapture();
      expect(Logger.root.level, Level.ALL);
      await logs.dispose();
    });
  });

  test('SharePlatform.instance is restored after the helper group', () {
    expect(SharePlatform.instance, same(before));
  });

  test('Logger.root.level is restored after LogCapture.dispose', () {
    expect(Logger.root.level, levelBefore);
  });
}
