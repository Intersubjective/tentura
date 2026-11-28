@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

import 'support/shipped_client_version.dart';

void main() {
  test(
    'the client uses public terminology and meets the server minimum version',
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

      expectShippedClientMeetsServerMinimum();
    },
  );

  test(
    'the server uses its compiled minimum in the absence of an override',
    () {
      expect(Platform.environment.containsKey('MIN_CLIENT_VERSION'), isFalse);
      expect(Env().minClientVersion, kDefaultMinClientVersion);
    },
  );
}
