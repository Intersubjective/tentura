// tentura-3zd: child subprocess for interrupt safety probes (long sleep).
//
// Writes a readiness marker as soon as this isolate starts running (before
// `test()` registers anything), so a SIGKILL probe can wait for proof that
// the subprocess chain actually reached this far instead of guessing a fixed
// delay -- a fixed delay can fire before `dart test`'s VM boot + package
// resolution finish, killing the harness before the code under test ever ran.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final markerPath = Platform.environment['TENTURA_3ZD_SLEEP_PROBE_READY_MARKER'];
  if (markerPath != null && markerPath.isNotEmpty) {
    File(markerPath).writeAsStringSync('ready');
  }

  test('tentura-3zd sleep probe holds subprocess open', () async {
    await Future<void>.delayed(const Duration(hours: 1));
  });
}
