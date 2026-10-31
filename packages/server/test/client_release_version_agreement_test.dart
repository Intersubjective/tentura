@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

/// A client release that depends on new server fields raises the server's
/// floor past the previous one, and every place that states the floor agrees.
/// `min_client_version_gate_test.dart` proves the floor never exceeds the
/// shipped client; these tests prove the floor actually moved up.

/// The floor before the most recent set of new GraphQL fields and mutations
/// shipped: a floor still at this value admits clients that lack them.
const _floorBeforeNewFields = '7.59.14';

/// The last client version built without those fields.
const _clientBeforeNewFields = '7.59.48';

/// Server tests run with `packages/server` as the working directory.
File _clientFile(String relative) => File('../client/$relative');
File _repoFile(String relative) => File('../../$relative');

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

String _pubspecVersion() {
  final line = _clientFile(
    'pubspec.yaml',
  ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
  return line.split(':')[1].trim();
}

void main() {
  group('Client version floor moves up when new server fields ship', () {
    test('the floor is raised past the previous floor', () {
      expect(
        _compare(kDefaultMinClientVersion, _floorBeforeNewFields),
        greaterThan(0),
        reason:
            'kDefaultMinClientVersion is $kDefaultMinClientVersion; clients '
            'at $_floorBeforeNewFields lack the new fields and must be '
            'excluded.',
      );
    });

    test('the shipped client is newer than the build without the fields', () {
      expect(
        _compare(_pubspecVersion(), _clientBeforeNewFields),
        greaterThan(0),
        reason:
            'packages/client/pubspec.yaml is ${_pubspecVersion()}; it must '
            'be a release above $_clientBeforeNewFields.',
      );
    });

    test('the .env.example floor comment and override match the floor', () {
      final env = _repoFile('.env.example').readAsStringSync();

      final stated = RegExp(
        r'kDefaultMinClientVersion, currently ([0-9]+\.[0-9]+\.[0-9]+)',
      ).firstMatch(env);
      final example = RegExp(
        r'^# MIN_CLIENT_VERSION=([0-9]+\.[0-9]+\.[0-9]+)',
        multiLine: true,
      ).firstMatch(env);

      expect(stated?.group(1), kDefaultMinClientVersion);
      expect(example?.group(1), kDefaultMinClientVersion);
    });
  });
}
