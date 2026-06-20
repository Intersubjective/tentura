// CI guard: fail the build if the deployed web entry points disagree on the
// cache-busting build version. Run AFTER generate_wasm_preload_artifacts.dart.
//
// Checks that all of these reference the same `resolveWebBuildVersion()`:
//   - build/web/index.html        flutter_bootstrap.js?v=<version>
//   - build/web/manifest.json     "version"
//   - build/web/wasm-preload-manifest.json  "version"
//   - build/web/tentura-app-cache-sw.js     CACHE_VERSION
//
// Inconsistency here is exactly what served stale assets on a normal refresh
// (a cache version that never changed between deploys), so it must block deploy.
// ignore_for_file: avoid_print //

import 'dart:convert';
import 'dart:io';

import '../hook/build/web_build_version.dart';

void main() {
  const buildWebDir = 'build/web';
  final expected = resolveWebBuildVersion();
  print('Expected web build version: $expected');

  final problems = <String>[];
  void check(String label, String? actual) {
    if (actual == null) {
      problems.add('$label: could not read version');
    } else if (actual != expected) {
      problems.add('$label: "$actual" != expected "$expected"');
    } else {
      print('OK  $label = $actual');
    }
  }

  check('index.html bootstrap query', _indexBootstrapVersion(buildWebDir));
  check('manifest.json', _jsonVersion('$buildWebDir/manifest.json'));
  check(
    'wasm-preload-manifest.json',
    _jsonVersion('$buildWebDir/wasm-preload-manifest.json'),
  );
  check('tentura-app-cache-sw.js CACHE_VERSION', _swCacheVersion(buildWebDir));

  if (problems.isNotEmpty) {
    stderr.writeln('web version consistency check FAILED:');
    for (final p in problems) {
      stderr.writeln('  - $p');
    }
    exit(1);
  }
  print('web version consistency check passed.');
}

String? _indexBootstrapVersion(String dir) {
  final file = File('$dir/index.html');
  if (!file.existsSync()) return null;
  final match = RegExp(r'''flutter_bootstrap\.js\?v=([^"']+)''')
      .firstMatch(file.readAsStringSync());
  return match?.group(1);
}

String? _jsonVersion(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync());
  if (json is Map && json['version'] is String) return json['version'] as String;
  return null;
}

String? _swCacheVersion(String dir) {
  final file = File('$dir/tentura-app-cache-sw.js');
  if (!file.existsSync()) return null;
  final match =
      RegExp("CACHE_VERSION = '([^']+)'").firstMatch(file.readAsStringSync());
  return match?.group(1);
}
