@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../hook/build/web_build_version.dart';

Directory _clientPackageRoot() {
  final cwd = Directory.current;
  if (File(
    '${cwd.path}/tool/verify_web_version_consistency.dart',
  ).existsSync()) {
    return cwd;
  }
  final nested = Directory('${cwd.path}/packages/client');
  if (File(
    '${nested.path}/tool/verify_web_version_consistency.dart',
  ).existsSync()) {
    return nested;
  }
  throw StateError(
    'Expected packages/client as working directory (found ${cwd.path})',
  );
}

Future<ProcessResult> _runDefaultVerify(
  Directory clientRoot,
  Directory sourceRoot,
) {
  return Process.run(
    'dart',
    [
      '--packages=${clientRoot.parent.parent.path}/.dart_tool/package_config.json',
      '${clientRoot.path}/tool/verify_web_version_consistency.dart',
    ],
    workingDirectory: sourceRoot.path,
    environment: {
      ...Platform.environment,
      'WEB_BUILD_ID': '',
    },
  );
}

Future<ProcessResult> _runBuildDirVerify(
  Directory clientRoot,
  String buildWebPath,
) {
  return Process.run(
    'dart',
    ['run', 'tool/verify_web_version_consistency.dart', buildWebPath],
    workingDirectory: clientRoot.path,
    environment: {
      ...Platform.environment,
      'WEB_BUILD_ID': '',
    },
  );
}

void _writeStaleBuildWeb({
  required Directory buildWebDir,
  required String staleVersion,
}) {
  buildWebDir.createSync(recursive: true);
  File('${buildWebDir.path}/index.html').writeAsStringSync(
    '<script src="flutter_bootstrap.js?v=$staleVersion"></script>',
  );
  File('${buildWebDir.path}/manifest.json').writeAsStringSync(
    jsonEncode({'version': staleVersion}),
  );
  File('${buildWebDir.path}/flutter_bootstrap.js').writeAsStringSync('');
  File('${buildWebDir.path}/wasm-preload-manifest.json').writeAsStringSync(
    jsonEncode({
      'version': staleVersion,
      'sharedPreload': ['/flutter_bootstrap.js?v=$staleVersion'],
      'wasmPreload': <String>[],
      'jsPreload': <String>[],
    }),
  );
  File('${buildWebDir.path}/tentura-app-cache-sw.js').writeAsStringSync(
    "const CACHE_VERSION = '$staleVersion';",
  );
}

void _writeConsistentBuildWeb({
  required Directory buildWebDir,
  required String version,
}) {
  buildWebDir.createSync(recursive: true);
  File('${buildWebDir.path}/index.html').writeAsStringSync(
    '<script src="flutter_bootstrap.js?v=$version"></script>',
  );
  File('${buildWebDir.path}/manifest.json').writeAsStringSync(
    jsonEncode({'version': version}),
  );
  File('${buildWebDir.path}/flutter_bootstrap.js').writeAsStringSync('');
  for (final asset in ['main.dart.js', 'main.dart.wasm']) {
    File('${buildWebDir.path}/app-assets/$version/$asset')
      ..createSync(recursive: true)
      ..writeAsStringSync('compiled artifact fixture');
  }
  File('${buildWebDir.path}/wasm-preload-manifest.json').writeAsStringSync(
    jsonEncode({
      'version': version,
      'sharedPreload': ['/flutter_bootstrap.js?v=$version'],
      'wasmPreload': <String>['/app-assets/$version/main.dart.wasm'],
      'jsPreload': <String>['/app-assets/$version/main.dart.js'],
    }),
  );
  File('${buildWebDir.path}/tentura-app-cache-sw.js').writeAsStringSync(
    "const CACHE_VERSION = '$version';",
  );
}

void main() {
  group('non-control preload URLs belong to the expected immutable build', () {
    const assetsByGroup = {
      'sharedPreload': [
        'assets/packages/sqlite3.wasm',
        'assets/packages/drift_worker.js',
      ],
      'wasmPreload': ['main.dart.wasm', 'canvaskit/canvaskit.wasm'],
      'jsPreload': ['main.dart.js'],
    };
    for (final group in assetsByGroup.entries) {
      for (final asset in group.value) {
        test(
          '${group.key} rejects /$asset despite an existing root copy',
          () async {
            final clientRoot = _clientPackageRoot();
            final version = resolveWebBuildVersion(
              buildId: '',
              pubspecPath: '${clientRoot.path}/pubspec.yaml',
            );
            final dir = Directory.systemTemp.createTempSync(
              'versioned_preload_',
            );
            addTearDown(() => dir.deleteSync(recursive: true));
            final prefix = '/app-assets/$version/';
            File('${dir.path}/index.html').writeAsStringSync(
              '<script src="flutter_bootstrap.js?v=$version"></script>',
            );
            File(
              '${dir.path}/flutter_bootstrap.js',
            ).writeAsStringSync('bootstrap');
            File('${dir.path}/manifest.json').writeAsStringSync(
              jsonEncode({'version': version}),
            );
            File('${dir.path}/tentura-app-cache-sw.js').writeAsStringSync(
              "const CACHE_VERSION = '$version';",
            );
            final manifest = <String, Object>{
              'version': version,
              for (final entry in assetsByGroup.entries)
                entry.key: [
                  if (entry.key == 'sharedPreload')
                    '/flutter_bootstrap.js?v=$version',
                  for (final name in entry.value) '$prefix$name',
                ],
            };
            for (final names in assetsByGroup.values) {
              for (final name in names) {
                File('${dir.path}$prefix$name')
                  ..createSync(recursive: true)
                  ..writeAsStringSync('current asset');
              }
            }
            final preload = File('${dir.path}/wasm-preload-manifest.json');
            preload.writeAsStringSync(jsonEncode(manifest));
            final valid = await _runBuildDirVerify(clientRoot, dir.path);
            expect(
              valid.exitCode,
              0,
              reason: '${valid.stdout}\n${valid.stderr}',
            );

            // This is an existing stale file, not a missing-file fixture.
            File('${dir.path}/$asset')
              ..createSync(recursive: true)
              ..writeAsStringSync('stale asset');
            (manifest[group.key]! as List<String>).add('/$asset');
            preload.writeAsStringSync(jsonEncode(manifest));
            final invalid = await _runBuildDirVerify(clientRoot, dir.path);
            expect(
              invalid.exitCode,
              1,
              reason:
                  '/$asset must be rejected outside $prefix, even if it exists.\n'
                  '${invalid.stdout}\n${invalid.stderr}',
            );
            expect(invalid.stderr, contains('/$asset'));
          },
        );
      }
    }
  });

  test(
    'source verification accepts a fixed placeholder when compiled output is stale',
    () async {
      final clientRoot = _clientPackageRoot();
      final pubspecPath = '${clientRoot.path}/pubspec.yaml';
      final expected = resolveWebBuildVersion(
        buildId: '',
        pubspecPath: pubspecPath,
      );
      const staleBuildVersion = '0.0.1-stale-build-artifacts-only';

      final sourceRoot = _writeSourceCheckout(clientRoot, '0.0.0-dev');
      final buildWeb = Directory('${sourceRoot.path}/build/web');

      _writeStaleBuildWeb(
        buildWebDir: buildWeb,
        staleVersion: staleBuildVersion,
      );

      final result = await _runDefaultVerify(clientRoot, sourceRoot);
      expect(
        result.exitCode,
        0,
        reason:
            'standalone check must accept the source placeholder, independently of '
            'build/web\nstdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
      expect(result.stdout, contains(expected));
      expect(
        File('${sourceRoot.path}/web/index.html').readAsStringSync(),
        contains('flutter_bootstrap.js?v=0.0.0-dev'),
      );
    },
  );

  test(
    'source verification rejects release-pinned bootstraps even when compiled output is valid',
    () async {
      final clientRoot = _clientPackageRoot();
      final pubspecPath = '${clientRoot.path}/pubspec.yaml';
      final expected = resolveWebBuildVersion(
        buildId: '',
        pubspecPath: pubspecPath,
      );
      final sourceRoot = _writeSourceCheckout(clientRoot, expected);
      final buildWeb = Directory('${sourceRoot.path}/build/web');

      _writeConsistentBuildWeb(buildWebDir: buildWeb, version: expected);
      final validBuild = await _runBuildDirVerify(clientRoot, buildWeb.path);
      expect(
        validBuild.exitCode,
        0,
        reason: '${validBuild.stdout}\n${validBuild.stderr}',
      );

      for (final sourceVersion in [expected, '0.0.2-tracked-index-drift']) {
        File('${sourceRoot.path}/web/index.html').writeAsStringSync(
          '<script src="flutter_bootstrap.js?v=$sourceVersion"></script>',
        );
        final result = await _runDefaultVerify(clientRoot, sourceRoot);
        expect(
          result.exitCode,
          1,
          reason:
              'A release version in source HTML restores the dual-version workflow, '
              'whether it matches pubspec or has drifted.\n${result.stdout}\n${result.stderr}',
        );
        expect(
          '${result.stdout}${result.stderr}',
          contains('web/index.html'),
          reason:
              'failure must cite the tracked source entry point, not only '
              'build/web artifacts',
        );
      }
    },
  );

  test(
    'build output verify fails when the given build directory is stale',
    () async {
      final clientRoot = _clientPackageRoot();
      final pubspecPath = '${clientRoot.path}/pubspec.yaml';
      final expected = resolveWebBuildVersion(
        buildId: '',
        pubspecPath: pubspecPath,
      );
      const staleBuildVersion = '0.0.3-stale-explicit-build-dir';

      final buildWeb = Directory.systemTemp.createTempSync(
        'tentura_verify_web_stale_',
      );
      addTearDown(() => buildWeb.deleteSync(recursive: true));

      _writeStaleBuildWeb(
        buildWebDir: buildWeb,
        staleVersion: staleBuildVersion,
      );
      expect(staleBuildVersion, isNot(equals(expected)));

      final result = await _runBuildDirVerify(clientRoot, buildWeb.path);
      expect(
        result.exitCode,
        isNot(0),
        reason:
            'explicit build directory check must fail on stale artifacts\n'
            'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    },
  );
}

Directory _writeSourceCheckout(Directory clientRoot, String bootstrapVersion) {
  final root = Directory.systemTemp.createTempSync('web_version_source_');
  addTearDown(() => root.deleteSync(recursive: true));
  File('${clientRoot.path}/pubspec.yaml').copySync('${root.path}/pubspec.yaml');
  File('${root.path}/web/index.html')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '<script src="flutter_bootstrap.js?v=$bootstrapVersion"></script>',
    );
  return root;
}
