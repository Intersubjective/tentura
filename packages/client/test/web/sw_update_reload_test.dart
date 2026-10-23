import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #627 (#622): an open tab must reload once when a new deploy's service
/// worker takes control, or it lazily loads new deferred chunks into old JS.
/// The behaviour is exercised by test/web/sw_update_reload_test.mjs.
void main() {
  test('index.html reloads once on a service worker controller change', () {
    final index = File('web/index.html').readAsStringSync();
    final script = RegExp(
      r'<script id="sw-update-reload">([\s\S]*?)</script>',
    ).firstMatch(index)?.group(1);
    expect(script, isNotNull, reason: 'missing script#sw-update-reload');
    expect(script, contains("addEventListener('controllerchange'"));
    expect(script, contains('navigator.serviceWorker.controller'));
    expect(script, contains('location.reload()'));
  });

  test('controller change reload behaves (node)', () async {
    final ProcessResult nodeVersion;
    try {
      nodeVersion = await Process.run('node', ['--version']);
    } on ProcessException {
      markTestSkipped('node is not installed');
      return;
    }
    if (nodeVersion.exitCode != 0) {
      markTestSkipped('node is not usable');
      return;
    }
    final script = File('test/web/sw_update_reload_test.mjs');
    if (!script.existsSync()) {
      markTestSkipped('run from packages/client');
      return;
    }
    final result = await Process.run('node', ['--test', script.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
