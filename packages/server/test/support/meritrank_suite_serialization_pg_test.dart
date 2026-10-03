@Tags(['pg', 'mr'])
library;

import 'package:test/test.dart';

import 'disposable_pg_target.dart';
import 'meritrank_lock_probe.dart';

/// `mr`-tagged suites share one MeritRank container, so they must not overlap
/// even when `dart test` runs files in parallel (no `-j 1`). The harness has to
/// enforce that itself: a suite tagged `mr` holds a cluster-wide advisory lock
/// ([meritRankSuiteLockKey]) from the moment it provisions its disposable
/// database until it drops it.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MR_SERIALIZATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_mr_serialization',
  );
  final skipReason = await pgSkipReason(target);

  group('MeritRank suite serialization in an mr-tagged suite', () {
    test(
      'recreating the disposable database holds the MeritRank lock until '
      'the database is dropped',
      () async {
        await target.recreate();
        final heldWhileProvisioned = !await meritRankSuiteLockIsFree(target);
        await target.drop();

        expect(heldWhileProvisioned, isTrue);
        expect(await meritRankSuiteLockBecomesFree(target), isTrue);
      },
      skip: skipReason,
    );

    test(
      'the writer session holds the MeritRank lock until it is torn down',
      () async {
        final session = await setUpDisposablePgWriter(target: target);
        final heldWhileSessionOpen = !await meritRankSuiteLockIsFree(target);
        await tearDownDisposablePgWriter(session: session);

        expect(heldWhileSessionOpen, isTrue);
        expect(await meritRankSuiteLockBecomesFree(target), isTrue);
      },
      skip: skipReason,
    );
  });
}
