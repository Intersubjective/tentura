import 'dart:io';

import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

/// The main database leases one pool connection per scope; the opt-in
/// transaction-pinned pool flag no longer exists, so no test may configure,
/// probe or assert on it.
void main() {
  group('Retired transaction-pinned pool flag in tests', () {
    final retired = RegExp(
      'DRIFT_TRANSACTION_PINNED_POOL_ENABLED|driftTransactionPinnedPoolEnabled|'
      'transactionPinnedPoolEnv|probeTransactionPinnedPoolRuntimeEnv',
    );
    // These only assert the flag is gone (or name it in a message).
    const assertsAbsence = {
      'retired_transaction_pinned_pool_flag_test.dart',
      'scoped_main_db_access_test.dart',
      'main_db_scope_contention_contract_test.dart',
      'main_db_scope_admission_pg_test.dart',
    };

    test('no test or test helper references the removed flag', () {
      final offenders = <String>[
        for (final entity in Directory('test').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              !assertsAbsence.any(entity.path.endsWith) &&
              retired.hasMatch(entity.readAsStringSync()))
            entity.path,
      ]..sort();

      expect(
        offenders,
        isEmpty,
        reason:
            'Delete or rewrite tests that still exercise the retired flag; '
            'span, pool-acquire and cancellation contracts are covered on '
            'the scoped pool.',
      );
    });

    test('pool capacity is the configured connection count', () {
      for (final capacity in [2, 3, 20]) {
        final env = Env(maxConnectionCount: capacity);

        expect(env.pgMaxConnectionCount, capacity);
        expect(env.pgPoolSettings.maxConnectionCount, capacity);
      }
    });
  });
}
