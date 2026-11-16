@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

/// Server tests run with `packages/server` as the working directory.
File _clientFile(String relative) => File('../client/$relative');
File _repoFile(String relative) => File('../../$relative');

/// Semver part of the pubspec `version:` line (build suffix `+N` dropped).
String _pubspecVersion() {
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
    multiLine: true,
  ).firstMatch(_clientFile('pubspec.yaml').readAsStringSync());
  if (match == null) {
    fail('packages/client/pubspec.yaml has no semver `version:` line');
  }
  return match.group(1)!;
}

void main() {
  group('Client version floor agrees across trackers', () {
    test(
      'server minimum client version does not exceed the client version',
      () {
        List<int> parts(String v) => v.split('.').map(int.parse).toList();
        final floor = parts(kDefaultMinClientVersion);
        final current = parts(_pubspecVersion());
        var cmp = 0;
        for (var i = 0; i < 3 && cmp == 0; i++) {
          cmp = floor[i].compareTo(current[i]);
        }
        expect(cmp, lessThanOrEqualTo(0));
      },
    );

    test('.env.example states the same floor and override as the server', () {
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

    test(
      'web index.html keeps the unstamped bootstrap version placeholder',
      () {
        expect(
          _clientFile('web/index.html').readAsStringSync(),
          contains('flutter_bootstrap.js?v=0.0.0-dev'),
        );
      },
    );
  });
}
