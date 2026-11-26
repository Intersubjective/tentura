@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

const _release = '7.72.0';

void main() {
  test('the shipped client declares one release version', () {
    final internalTerm = RegExp('phantom|фантом', caseSensitive: false);
    for (final locale in ['en', 'ru']) {
      final arb = File('../client/l10n/app_$locale.arb').readAsStringSync();
      final messages = (jsonDecode(arb) as Map<String, dynamic>).entries.where(
        (entry) => !entry.key.startsWith('@') && entry.value is String,
      );
      expect(
        messages.where((entry) => internalTerm.hasMatch(entry.value as String)),
        isEmpty,
        reason: 'User-facing $locale messages use product terminology.',
      );
    }

    final pubspec = File('../client/pubspec.yaml').readAsLinesSync();
    expect(pubspec.where((line) => line.startsWith('version:')), [
      'version: $_release',
    ]);
  });

  test('without an override the server requires the coordinated client', () {
    expect(Platform.environment.containsKey('MIN_CLIENT_VERSION'), isFalse);
    expect(
      (compiled: kDefaultMinClientVersion, effective: Env().minClientVersion),
      (compiled: _release, effective: _release),
    );
  });

  test('the sample environment documents the coordinated client floor', () {
    final sample = File('../../.env.example').readAsLinesSync();
    expect(
      {
        'comment': sample.where(
          (line) => line.contains('kDefaultMinClientVersion, currently '),
        ),
        'override': sample.where(
          (line) => line.startsWith('# MIN_CLIENT_VERSION='),
        ),
      },
      {
        'comment': [
          contains('kDefaultMinClientVersion, currently $_release)'),
        ],
        'override': ['# MIN_CLIENT_VERSION=$_release'],
      },
    );
  });
}
