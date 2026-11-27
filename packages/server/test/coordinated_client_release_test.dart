@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

import 'support/shipped_client_version.dart';

void main() {
  test(
    'the shipped client meets the server minimum version',
    () {
      final internalTerm = RegExp('phantom|фантом', caseSensitive: false);
      for (final locale in ['en', 'ru']) {
        final arb = File('../client/l10n/app_$locale.arb').readAsStringSync();
        final messages = (jsonDecode(arb) as Map<String, dynamic>).entries
            .where(
              (entry) => !entry.key.startsWith('@') && entry.value is String,
            );
        expect(
          messages.where(
            (entry) => internalTerm.hasMatch(entry.value as String),
          ),
          isEmpty,
          reason: 'User-facing $locale messages use product terminology.',
        );
      }

      expectShippedClientMeetsServerMinimum();
    },
  );

  test('without an override the server enforces its compiled minimum', () {
    expect(Platform.environment.containsKey('MIN_CLIENT_VERSION'), isFalse);
    expect(Env().minClientVersion, kDefaultMinClientVersion);
  });

  test('the sample environment documents the coordinated client floor', () {
    final sample = File('../../.env.example').readAsLinesSync();
    final floorComments = sample.where(
      (line) =>
          line.startsWith('#') &&
          line.contains('kDefaultMinClientVersion, currently '),
    );
    final floorOverrides = sample.where(
      (line) => line.startsWith('# MIN_CLIENT_VERSION='),
    );
    expect(
      {
        'comment': floorComments,
        'override': floorOverrides,
        'previous release references': sample.where(
          (line) => line.contains('7.73.0'),
        ),
      },
      {
        'comment': [
          contains(
            'kDefaultMinClientVersion, currently $kDefaultMinClientVersion)',
          ),
        ],
        'override': ['# MIN_CLIENT_VERSION=$kDefaultMinClientVersion'],
        'previous release references': isEmpty,
      },
    );
  });
}
