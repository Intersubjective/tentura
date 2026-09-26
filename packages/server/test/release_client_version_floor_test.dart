import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

/// The client version shipped on `main` as of tentura-617.37 (before this
/// release bead lands). Plan §14.6's last bullet ("Correct return type
/// changes Boolean → Int, so the server floor moves in the same release")
/// requires this release to bump `packages/client/pubspec.yaml` strictly
/// above it and move `kDefaultMinClientVersion` to match exactly — not
/// merely satisfy it, the way the older U19 cutover floor did.
const _mainClientVersion = '7.23.0';

List<int> _parse(String version) => [
  for (final part in version.split('.')) int.parse(part),
];

int _compare(String a, String b) {
  final left = _parse(a);
  final right = _parse(b);
  for (var i = 0; i < left.length; i++) {
    final c = left[i].compareTo(right[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// Path to a file in the sibling client package. Server tests run with
/// `packages/server` as the working directory.
File _clientFile(String relative) => File('../client/$relative');

String _shippedClientVersion() {
  final line = _clientFile('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':')[1].trim();
}

String _bootstrapCacheBusterVersion() {
  final html = _clientFile('web/index.html').readAsStringSync();
  final match = RegExp(
    r'flutter_bootstrap\.js\?v=([0-9]+\.[0-9]+\.[0-9]+)',
  ).firstMatch(html);
  if (match == null) {
    fail('web/index.html has no flutter_bootstrap.js?v= cache-buster');
  }
  return match.group(1)!;
}

void main() {
  group('tentura-617.37 — release version bump', () {
    test('pubspec version is strictly higher than the version on main', () {
      expect(
        _compare(_shippedClientVersion(), _mainClientVersion),
        greaterThan(0),
        reason:
            'packages/client/pubspec.yaml is $_mainClientVersion on main; '
            'this release must bump it to a newer version.',
      );
    });

    test('the index.html cache-buster is bumped to the same new version', () {
      final shipped = _shippedClientVersion();
      expect(
        _compare(shipped, _mainClientVersion),
        greaterThan(0),
        reason: 'pubspec.yaml must be bumped first for this check to be '
            'meaningful.',
      );
      expect(
        _bootstrapCacheBusterVersion(),
        shipped,
        reason:
            'web/index.html flutter_bootstrap.js?v= must carry the same '
            'bumped version as pubspec.yaml.',
      );
    });

    test('kDefaultMinClientVersion is raised to equal the new client version',
        () {
      expect(
        _compare(kDefaultMinClientVersion, _mainClientVersion),
        greaterThan(0),
        reason:
            'kDefaultMinClientVersion is still $_mainClientVersion-era; '
            'this release must raise it past the version shipped on main.',
      );
      expect(
        kDefaultMinClientVersion,
        _shippedClientVersion(),
        reason:
            'kDefaultMinClientVersion ($kDefaultMinClientVersion) must '
            'equal the newly bumped packages/client/pubspec.yaml version '
            '(${_shippedClientVersion()}), not merely satisfy it.',
      );
    });
  });
}
