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
    test('server minimum client version equals the client pubspec version',
        () {
      expect(kDefaultMinClientVersion, _pubspecVersion());
    });

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

    test('client pubspec version is 7.62.0', () {
      expect(_pubspecVersion(), '7.62.0');
    });

    test('.env.example floor lines match the client pubspec version', () {
      final env = _repoFile('.env.example').readAsStringSync();
      expect(
        env,
        contains('kDefaultMinClientVersion, currently ${_pubspecVersion()}'),
      );
      expect(env, contains('# MIN_CLIENT_VERSION=${_pubspecVersion()}'));
    });

    test('web index.html keeps the unstamped bootstrap version placeholder',
        () {
      expect(
        _clientFile('web/index.html').readAsStringSync(),
        contains('flutter_bootstrap.js?v=0.0.0-dev'),
      );
    });
  });
}
