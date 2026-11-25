@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

const _release = '7.65.0';
const _shippedClient = '7.66.0';

void main() {
  test('the shipped client declares one minor release version', () {
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
      'version: $_shippedClient',
    ]);
  });

  test('without an override the server requires the coordinated client', () {
    expect(
      (compiled: kDefaultMinClientVersion, effective: Env().minClientVersion),
      (compiled: _release, effective: _release),
    );
  });

  test('the sample environment documents the coordinated client floor', () {
    final sample = File('../../.env.example').readAsLinesSync();
    final floorComment = sample.singleWhere(
      (line) => line.contains('kDefaultMinClientVersion, currently '),
    );
    final override = sample.singleWhere(
      (line) => line.startsWith('# MIN_CLIENT_VERSION='),
    );
    expect(
      {'comment': floorComment, 'override': override},
      {
        'comment': contains('kDefaultMinClientVersion, currently $_release)'),
        'override': '# MIN_CLIENT_VERSION=$_release',
      },
    );
  });
}
