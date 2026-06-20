import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../hook/build/version_update.dart';
import '../../hook/build/web_build_version.dart';

void main() {
  test('versionUpdate rewrites bootstrap query and manifest version', () {
    final dir = Directory.systemTemp.createTempSync('tentura_version_test');
    try {
      File('${dir.path}/index.html').writeAsStringSync(
        '<script src="flutter_bootstrap.js?v=2.3.0" async=""></script>',
      );
      File('${dir.path}/manifest.json').writeAsStringSync(
        jsonEncode({'name': 'Tentura', 'version': '2.3.0'}),
      );

      versionUpdate(webDir: dir.path, version: '9.9.9-abc123');

      final index = File('${dir.path}/index.html').readAsStringSync();
      final manifest = jsonDecode(
        File('${dir.path}/manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(index, contains('flutter_bootstrap.js?v=9.9.9-abc123'));
      expect(index, isNot(contains('?v=2.3.0')));
      // Preserves unrelated attributes.
      expect(index, contains('async=""'));
      expect(manifest['version'], '9.9.9-abc123');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('versionUpdate tolerates a queryless bootstrap script', () {
    final dir = Directory.systemTemp.createTempSync('tentura_version_test');
    try {
      File('${dir.path}/index.html').writeAsStringSync(
        '<script src="flutter_bootstrap.js" async=""></script>',
      );

      versionUpdate(webDir: dir.path, version: '1.0.0');

      expect(
        File('${dir.path}/index.html').readAsStringSync(),
        contains('flutter_bootstrap.js?v=1.0.0'),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('resolveWebBuildVersion appends a sanitized build id', () {
    final dir = Directory.systemTemp.createTempSync('tentura_version_test');
    try {
      File('${dir.path}/pubspec.yaml').writeAsStringSync(
        'name: tentura\nversion: 2.4.0\n',
      );
      final pubspecPath = '${dir.path}/pubspec.yaml';

      expect(
        resolveWebBuildVersion(buildId: '', pubspecPath: pubspecPath),
        '2.4.0',
      );
      expect(
        resolveWebBuildVersion(
          buildId: 'abcdef1234567890',
          pubspecPath: pubspecPath,
        ),
        '2.4.0-abcdef123456',
      );
      // Non-alphanumeric chars (slashes, refs) are stripped.
      expect(
        resolveWebBuildVersion(
          buildId: 'feat/x-9',
          pubspecPath: pubspecPath,
        ),
        '2.4.0-featx9',
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
