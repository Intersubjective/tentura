@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../hook/build/web_build_version.dart';

// Observed before this release task began, not a prescribed next version.
// Keep this floor fixed so later releases pass and main never compares to itself.
const _previousRelease = [7, 60, 23];

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
        'Release metadata must advance beyond the shipped 7.60.23 baseline; '
        'got $version',
  );
}

void main() {
  group('client release version', () {
    test('package version resolver advances beyond the previous release', () {
      _expectReleaseAdvanced(resolveWebBuildVersion(buildId: ''));
    });

    test('source page requests the new release with a fresh bootstrap URL', () {
      final index = File('web/index.html').readAsStringSync();
      final scripts = RegExp(
        r'''<script\b[^>]*\bsrc=["']([^"']*flutter_bootstrap\.js[^"']*)["']''',
      ).allMatches(index).toList();
      expect(scripts, hasLength(1));
      final bootstrapUrl = Uri.parse(scripts.single.group(1)!);
      final version = bootstrapUrl.queryParameters['v'];
      expect(
        version,
        isNotNull,
        reason: 'Returning browsers need a versioned URL',
      );
      expect(version, resolveWebBuildVersion(buildId: ''));
      _expectReleaseAdvanced(version!);
    });
  });
}
