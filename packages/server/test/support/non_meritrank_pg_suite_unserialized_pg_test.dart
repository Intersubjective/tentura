@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'disposable_pg_target.dart';
import 'meritrank_lock_probe.dart';

/// Only suites tagged `mr` are serialized on the MeritRank lock. A plain `pg`
/// suite never touches MeritRank, so it must stay parallel: it must not try to
/// take the lock itself. The test holds the lock on its own session, so a
/// concurrent `mr` suite cannot influence the outcome, and any harness attempt
/// to acquire it from a plain suite would block until the timeout.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_NON_MR_SERIALIZATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_non_mr_serialization',
  );
  final skipReason = await pgSkipReason(target);

  group('MeritRank suite serialization in a plain pg suite', () {
    test(
      'recreating and dropping the disposable database does not wait for the '
      'MeritRank lock',
      () async {
        final holder = await holdMeritRankSuiteLock(target);
        try {
          await target.recreate().timeout(const Duration(seconds: 60));
          await target.drop().timeout(const Duration(seconds: 60));
        } finally {
          await holder.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 20)),
      skip: skipReason,
    );

    test(
      'the writer session lifecycle does not wait for the MeritRank lock',
      () async {
        final holder = await holdMeritRankSuiteLock(target);
        try {
          final session = await setUpDisposablePgWriter(
            target: target,
          ).timeout(const Duration(seconds: 60));
          await tearDownDisposablePgWriter(
            session: session,
          ).timeout(const Duration(seconds: 60));
        } finally {
          await holder.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 20)),
      skip: skipReason,
    );
  });
}
