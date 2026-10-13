import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'transaction_pinned_pool_env.dart';

Future<Map<String, dynamic>> _probe(Map<String, String> overrides) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['test/support/disposable_pg_target_env_probe.dart'],
    workingDirectory: transactionPinnedPoolServerDirectory().path,
    environment: {
      ...(Map<String, String>.of(Platform.environment)
        ..remove('DRIFT_TRANSACTION_PINNED_POOL_ENABLED')),
      ...overrides,
    },
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode((result.stdout as String).trim().split('\n').last)
      as Map<String, dynamic>;
}

void main() {
  group('disposable PG target isolation from ambient server flags', () {
    for (final env in ['database', 'admin', 'template']) {
      test(
        '$env Env uses the configured pool capacity with a retired host flag',
        () async {
          final snapshot = await _probe({
            'DRIFT_TRANSACTION_PINNED_POOL_ENABLED': 'true',
            'POSTGRES_MAXCONN': '4',
          });
          expect(
            snapshot[env],
            4,
            reason: 'the retired spike flag must not change pool capacity',
          );
        },
      );
    }

    test(
      'all Envs use the configured pool capacity without a spike flag',
      () async {
        final snapshot = await _probe({'POSTGRES_MAXCONN': '4'});
        expect(snapshot.values, everyElement(4));
      },
    );
  });
}
