@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

const _releaseVersion = '7.71.0';
const _coordinatedFloor = '7.70.0';

void main() {
  test(
    'the client declares one release version and uses public terminology',
    () {
      final internalTerm = RegExp('phantom|фантом', caseSensitive: false);
      for (final locale in ['en', 'ru']) {
        final arb = File('../client/l10n/app_$locale.arb').readAsStringSync();
        final messages = (jsonDecode(arb) as Map<String, dynamic>).entries;
        final offendingKeys = [
          for (final MapEntry(:key, :value) in messages)
            if (!key.startsWith('@') &&
                value is String &&
                internalTerm.hasMatch(value))
              key,
        ];
        expect(offendingKeys, isEmpty, reason: 'app_$locale.arb message keys');
      }

      final pubspec = File('../client/pubspec.yaml').readAsLinesSync();
      expect(pubspec.where((line) => line.startsWith('version:')), [
        'version: $_releaseVersion',
      ]);
    },
  );

  test('the server keeps the coordinated minimum for a client patch', () {
    expect(Platform.environment.containsKey('MIN_CLIENT_VERSION'), isFalse);
    expect(
      (compiled: kDefaultMinClientVersion, effective: Env().minClientVersion),
      (compiled: _coordinatedFloor, effective: _coordinatedFloor),
    );
  });
}
