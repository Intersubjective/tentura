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
        '$env Env keeps the transaction pinned pool off when the host '
        'enables it',
        () async {
          final snapshot = await _probe({
            'DRIFT_TRANSACTION_PINNED_POOL_ENABLED': 'true',
            'POSTGRES_MAXCONN': '4',
          });
          expect(
            snapshot[env],
            isFalse,
            reason:
                'perf budgets must not depend on a host-level pool flag; '
                'tests that need the flag opt in explicitly',
          );
        },
      );
    }

    test(
      'all Envs keep the pinned pool off when the host leaves it unset',
      () async {
        final snapshot = await _probe({'POSTGRES_MAXCONN': '4'});
        expect(snapshot.values, everyElement(isFalse));
      },
    );
  });
}
