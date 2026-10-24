@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'disposable_pg_target.dart';
import 'meritrank_lock_probe.dart';

/// The MeritRank suite lock inside a CI bundle (scripts/gen_test_bundles.py).
///
/// A bundle is one suite that imports many test files and declares each
/// file's tests in `group('<path>', ..., tags: <the file's @Tags>)`, so the
/// suite itself carries no `mr` even when a file in it does. This suite has
/// that shape: `pg` on the suite, `mr` only on the first file's group. The
/// harness must still serialize that file on the lock — including from its
/// `setUpAll`, where real files provision their database — and must still
/// leave the plain file in the same suite alone.
Future<void> main() async {
  DisposablePgTarget newTarget() => DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MR_BUNDLE_LOCK_TEST_DB',
    defaultNamePrefix: 'tentura_test_mr_bundle_lock',
  );
  final probeTarget = newTarget();
  final skipReason = await pgSkipReason(probeTarget);

  group('test/bundled_mr_file_pg_test.dart', () {
    final fileTarget = newTarget();
    DisposablePgWriterSession? session;

    setUpAll(() async {
      if (skipReason != null) return;
      session = await setUpDisposablePgWriter(target: fileTarget);
    });

    tearDownAll(() async {
      final open = session;
      if (open != null) await tearDownDisposablePgWriter(session: open);
    });

    test(
      "a database provisioned in the file's setUpAll holds the lock",
      () async {
        expect(await meritRankSuiteLockIsFree(fileTarget), isFalse);
      },
      skip: skipReason,
    );
  }, tags: ['mr']);

  group('test/bundled_second_mr_file_pg_test.dart', () {
    test(
      'recreating a database in a test holds the lock until it is dropped',
      () async {
        final target = newTarget();
        await target.recreate();
        final held = !await meritRankSuiteLockIsFree(target);
        await target.drop();
        expect(held, isTrue);
      },
      skip: skipReason,
    );
  }, tags: ['mr']);

  group('test/bundled_plain_file_pg_test.dart', () {
    test(
      'the mr files released the lock when their databases were dropped',
      () async {
        expect(await meritRankSuiteLockBecomesFree(probeTarget), isTrue);
      },
      tags: ['mr'],
      skip: skipReason,
    );

    test(
      'a plain file in the same bundle does not wait for the lock',
      () async {
        final holder = await holdMeritRankSuiteLock(probeTarget);
        try {
          final session = await setUpDisposablePgWriter(
            target: newTarget(),
          ).timeout(const Duration(seconds: 60));
          await tearDownDisposablePgWriter(
            session: session,
          ).timeout(const Duration(seconds: 60));
        } finally {
          await holder.close();
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
      skip: skipReason,
    );
  });
}
