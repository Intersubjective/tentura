@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../hook/build/wasm_preload_artifacts.dart';
import '../../hook/build/web_build_version.dart';

// Observed before this release task began, not a prescribed next version.
// Keep this floor fixed so later releases pass and main never compares to itself.
const _previousRelease = [7, 60, 29];

void _expectReleaseAdvanced(String version) {
  expect(version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
  final components = version.split('.').map(int.parse).toList();
  var comparison = 0;
  for (var i = 0; i < _previousRelease.length; i++) {
    comparison = components[i].compareTo(_previousRelease[i]);
    if (comparison != 0) break;
  }
  expect(
    comparison,
    greaterThan(0),
    reason:
        'Release metadata must advance beyond the shipped 7.60.29 baseline; '
        'got $version',
  );
}

void main() {
  group('client release version', () {
    test('package version resolver advances beyond the previous release', () {
      _expectReleaseAdvanced(resolveWebBuildVersion(buildId: ''));
    });

    test(
      'built release requests the package version while source retains a placeholder',
      () {
        final source = File('web/index.html');
        final sourceBytes = source.readAsBytesSync();
        final output = Directory.systemTemp.createTempSync('client_release_');
        addTearDown(() => output.deleteSync(recursive: true));
        source.copySync('${output.path}/index.html');
        File(
          '${output.path}/manifest.json',
        ).writeAsStringSync('{"name":"Tentura"}');
        for (final asset in [
          'main.dart.wasm',
          'main.dart.js',
          'flutter_bootstrap.js',
        ]) {
          File(
            '${output.path}/$asset',
          ).writeAsStringSync('compiled artifact fixture');
        }
        final packageVersion = resolveWebBuildVersion(buildId: '');

        generateWasmPreloadArtifacts(
          buildWebDir: output.path,
          version: packageVersion,
        );

        final deployed = _bootstrapVersion(File('${output.path}/index.html'));
        expect(deployed, packageVersion);
        expect(deployed, isNot('0.0.0-dev'));
        _expectReleaseAdvanced(deployed!);
        expect(source.readAsBytesSync(), sourceBytes);
        expect(_bootstrapVersion(source), '0.0.0-dev');
      },
    );
  });
}

String? _bootstrapVersion(File index) {
  final scripts = RegExp(
    r'''<script\b[^>]*\bsrc=["']([^"']*flutter_bootstrap\.js[^"']*)["']''',
  ).allMatches(index.readAsStringSync()).toList();
  expect(scripts, hasLength(1));
  return Uri.parse(scripts.single.group(1)!).queryParameters['v'];
}
