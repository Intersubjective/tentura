@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// tentura-vd5d: the m0148 migration test passes alone but timed out
/// ("Test timed out after 30 seconds") in the long `--tags pg` run.
///
/// Every test in that file calls `migrateLocked`, which queues on the
/// cluster-wide disposable-pg lifecycle advisory lock. In a parallel run other
/// files hold that lock (template build, recreate, drop) for longer than the
/// default 30 s test timeout, so whichever m0148 test is waiting at that moment
/// fails (`setUpAll` has no such limit, so the failure only ever lands on a
/// test body).
///
/// Reproduce it without a race. Postgres grants a contended advisory lock to
/// waiters in arrival order, so:
///
/// 1. hold the lock (A), then start the m0148 file;
/// 2. wait until `pg_locks` shows the file's `setUpAll` blocked on the lock;
/// 3. queue a second request (B) behind it, and wait until `pg_locks` shows it;
/// 4. release A. The file's `setUpAll` runs, releases, and B is granted before
///    the file's first test can ask for the lock; B holds it longer than the
///    default test timeout, so the file's test bodies must wait it out.
const _m0148TestFile =
    'test/data/database/m0148_user_availability_migration_test.dart';

/// Longer than the package-default 30 s test timeout.
const _lockHold = Duration(seconds: 40);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0148_LOCK_CONTENTION_ADMIN_ONLY',
    defaultNamePrefix: 'tentura_test_m0148lock',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  Future<int> lifecycleLockWaiters(Connection admin) async {
    final rows = await admin.execute('''
SELECT count(*)::int
FROM pg_locks l
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.locktype = 'advisory'
  AND NOT l.granted
  AND l.database = (
    SELECT oid FROM pg_database WHERE datname = current_database()
  )
  AND a.datname = current_database()
  AND a.query LIKE '%pg_advisory_lock(hashtext%'
''');
    return rows.single.single! as int;
  }

  Future<void> waitForWaiters(
    Connection admin,
    int atLeast,
    String what,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (await lifecycleLockWaiters(admin) < atLeast) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out waiting for $what to block on the lifecycle lock');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'm0148 migration test waits out a lifecycle lock held past the default '
    'test timeout',
    () async {
      final admin = await Connection.open(
        target.adminEnv.pgEndpoint,
        settings: target.adminEnv.pgEndpointSettings,
      );
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final releaseA = Completer<void>();
      final aHeld = Completer<void>();
      final lockA = withDisposablePgLifecycleLock(
        target.adminEnv,
        () async {
          aHeld.complete();
          await releaseA.future;
        },
      );
      late final Process inner;
      late final Future<void> lockB;
      try {
        await aHeld.future;
        final baseline = await lifecycleLockWaiters(admin);

        inner = await Process.start(
          Platform.resolvedExecutable,
          ['test', _m0148TestFile, '--tags', 'pg', '-r', 'expanded'],
          workingDirectory: Directory.current.path,
        );
        unawaited(
          inner.stdout.transform(utf8.decoder).forEach(stdoutBuffer.write),
        );
        unawaited(
          inner.stderr.transform(utf8.decoder).forEach(stderrBuffer.write),
        );
        await waitForWaiters(admin, baseline + 1, 'the m0148 file (setUpAll)');

        lockB = withDisposablePgLifecycleLock(
          target.adminEnv,
          () => Future<void>.delayed(_lockHold),
        );
        await waitForWaiters(admin, baseline + 2, 'the contention hold');
      } finally {
        releaseA.complete();
        await lockA;
        await admin.close();
      }

      final exitCode = await inner.exitCode;
      await lockB;

      expect(
        exitCode,
        0,
        reason:
            'm0148 test file failed while the disposable-pg lifecycle lock '
            'was busy for ${_lockHold.inSeconds}s (default test timeout is '
            '30s).\nstdout:\n$stdoutBuffer\nstderr:\n$stderrBuffer',
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
