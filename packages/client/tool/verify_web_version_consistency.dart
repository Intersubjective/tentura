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

void main(List<String> args) {
  final buildWebDir = args.isEmpty ? 'build/web' : args.single;
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

  final preloadFile = File('$buildWebDir/wasm-preload-manifest.json');
  if (preloadFile.existsSync()) {
    final preload = jsonDecode(preloadFile.readAsStringSync()) as Map;
    for (final group in ['sharedPreload', 'wasmPreload', 'jsPreload']) {
      final paths = preload[group];
      if (paths is! List || paths.isEmpty) {
        problems.add('$group: missing asset paths');
        continue;
      }
      for (final asset in paths) {
        final uri = Uri.parse(asset as String);
        if (uri.hasAuthority ||
            !uri.path.startsWith('/') ||
            uri.pathSegments.contains('..')) {
          problems.add('$group: invalid local asset path "$asset"');
        } else if (!File('$buildWebDir${uri.path}').existsSync()) {
          problems.add('$group: missing asset "$asset"');
        }
        if (uri.path.startsWith('/app-assets/') &&
            !uri.path.startsWith('/app-assets/$expected/')) {
          problems.add('$group: stale versioned asset "$asset"');
        }
      }
    }
  }

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
  final match = RegExp(
    r'''flutter_bootstrap\.js\?v=([^"']+)''',
  ).firstMatch(file.readAsStringSync());
  return match?.group(1);
}

String? _jsonVersion(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync());
  if (json is Map && json['version'] is String)
    return json['version'] as String;
  return null;
}

String? _swCacheVersion(String dir) {
  final file = File('$dir/tentura-app-cache-sw.js');
  if (!file.existsSync()) return null;
  final match = RegExp(
    "CACHE_VERSION = '([^']+)'",
  ).firstMatch(file.readAsStringSync());
  return match?.group(1);
}
