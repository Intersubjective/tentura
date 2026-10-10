import 'package:test/test.dart';

import 'support/transaction_pinned_pool_env.dart';

void main() {
  group('Transaction-pinned Drift pool opt-in', () {
    test('defaults off and keeps the single-connection workaround', () {
      final env = transactionPinnedPoolEnv(maxConnectionCount: 20);

      expect(transactionPinnedPoolEnabled(env), isFalse);
      expect(env.pgMaxConnectionCount, 20);
      expect(env.pgPoolSettings.maxConnectionCount, 1);
    });

    test('explicit false keeps the single-connection workaround', () {
      final env = transactionPinnedPoolEnv(
        enabled: false,
        maxConnectionCount: 20,
      );

      expect(transactionPinnedPoolEnabled(env), isFalse);
      expect(env.pgPoolSettings.maxConnectionCount, 1);
    });

    test('explicit true honors the configured pool capacity', () {
      for (final capacity in [2, 3]) {
        final env = transactionPinnedPoolEnv(
          enabled: true,
          maxConnectionCount: capacity,
        );

        expect(transactionPinnedPoolEnabled(env), isTrue);
        expect(env.pgPoolSettings.maxConnectionCount, capacity);
        expect(
          env.pgPoolSettings.maxConnectionAge,
          const Duration(hours: 12),
        );
      }
    });
    test('an unset runtime flag keeps the prototype disabled', () async {
      expect(
        await probeTransactionPinnedPoolRuntimeEnv(),
        (enabled: false, configuredCapacity: 3, poolCapacity: 1),
      );
    });

    test('runtime false keeps the single-connection workaround', () async {
      expect(
        await probeTransactionPinnedPoolRuntimeEnv(flag: 'false'),
        (enabled: false, configuredCapacity: 3, poolCapacity: 1),
      );
    });

    test('runtime true enables the configured multi-connection pool', () async {
      expect(
        await probeTransactionPinnedPoolRuntimeEnv(flag: 'true'),
        (enabled: true, configuredCapacity: 3, poolCapacity: 3),
      );
    });

    test('explicit opt-out overrides a runtime opt-in', () async {
      expect(
        await probeTransactionPinnedPoolRuntimeEnv(
          flag: 'true',
          constructorOverride: false,
        ),
        (enabled: false, configuredCapacity: 3, poolCapacity: 1),
      );
    });

    test('explicit opt-in overrides a runtime opt-out', () async {
      expect(
        await probeTransactionPinnedPoolRuntimeEnv(
          flag: 'false',
          constructorOverride: true,
        ),
        (enabled: true, configuredCapacity: 3, poolCapacity: 3),
      );
    });
  });
}
