@Tags(['pg', 'mr'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import '../support/http_request_cancellation_fixture.dart';
import '../support/meritrank_blackhole.dart';
import '../support/pg_wait.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HTTP_CANCELLATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_http_cancellation',
  );
  final unavailable =
      await pgSkipReason(target) ??
      await HttpRequestCancellationFixture.caddySkipReason();
  if (unavailable != null) {
    // Acceptance commands set TENTURA_PG_TESTS_REQUIRED=1: missing PostgreSQL,
    // Caddy, or the MR blackhole must fail that gate instead of skipping it.
    if (isPgTestsRequired()) {
      throw StateError(
        'Required HTTP cancellation dependencies unavailable: $unavailable',
      );
    }
    test('HTTP cancellation through Caddy', () {}, skip: unavailable);
    return;
  }

  late HttpRequestCancellationFixture fixture;
  setUpAll(() async {
    fixture = HttpRequestCancellationFixture(target);
    await fixture.start();
  });
  tearDownAll(() => fixture.close());

  group('HTTP cancellation through Caddy', () {
    test('a disconnect before admission starts no database work', () async {
      final pause = fixture.pauseBeforeAdmission();
      final call = await fixture.create('cancellation-before-admission');
      try {
        await pause.entered.future.timeout(kStableStateWait);
        expect(fixture.pool.admission.running, 0);
        expect(fixture.pool.admission.queued, 0);
        await call.abortInFlight();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } finally {
        if (!pause.release.isCompleted) pause.release.complete();
      }
      await pause.finished.future.timeout(kCompletionWait);

      expect(
        await fixture.rowCount('cancellation-before-admission'),
        0,
        reason: 'Resuming authentication must not admit an abandoned request.',
      );
      await fixture.assertUsable('cancellation-after-pre-admission');
    });

    test(
      'a disconnect removes queued work before its admission timer',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final holder = fixture.pool.admission.run(() async {
          entered.complete();
          await release.future;
        });
        var removedByCancellation = false;
        try {
          await entered.future.timeout(kStableStateWait);
          final call = await fixture.create('cancellation-queued');
          expect(
            await fixture.waitUntil(() => fixture.pool.admission.queued == 1),
            isTrue,
            reason: 'The request must reach the real admission queue first.',
          );
          await call.abortInFlight();
          // The existing interactive admission timer is 250 ms. This bound is
          // deliberately shorter: ordinary queue expiry is not cancellation.
          removedByCancellation = await fixture.waitUntil(
            () => fixture.pool.admission.queued == 0,
            budget: const Duration(milliseconds: 150),
          );
        } finally {
          release.complete();
          await holder.timeout(kCompletionWait);
          expect(
            await fixture.waitUntil(() => fixture.pool.admission.running == 0),
            isTrue,
          );
        }

        expect(removedByCancellation, isTrue);
        expect(await fixture.rowCount('cancellation-queued'), 0);
        await fixture.assertUsable('cancellation-after-queue');
      },
    );

    test('a disconnect stops active SQL and drains its rollback', () async {
      final call = await fixture.create('cancellation-sql-active');
      final backend = await fixture.waitForBackend(
        (backend) => backend.waitEvent == 'PgSleep',
      );
      await call.abortInFlight();
      final stopped = await fixture.backendStopped(backend);
      if (!stopped) await fixture.releaseHungBackend(backend);

      expect(await fixture.rowCount('cancellation-sql-active'), 0);
      await fixture.assertUsable('cancellation-after-active-sql');
      expect(
        stopped,
        isTrue,
        reason:
            'Closing the downstream connection must stop PostgreSQL, '
            'not just abandon the Shelf response future.',
      );
    });

    test('a cancelled scope refuses SQL issued after disconnect', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final statementFinished = Completer<void>();
      var attemptedStatement = false;
      final probe = fixture.probeNextCreate((database) {
        return database.withConnectionScope(
          () async {
            await database.customSelect('SELECT pg_backend_pid()').getSingle();
            entered.complete();
            await release.future;
            try {
              attemptedStatement = true;
              // No transaction: rollback cannot hide that this SQL was sent.
              await database.customStatement('''
                INSERT INTO public.request_cancellation_probe (label)
                VALUES ('statement-after-disconnect')
              ''');
            } finally {
              statementFinished.complete();
            }
          },
          actorUserId: cancellationActor,
        );
      });
      final call = await fixture.create('cancellation-after-disconnect-probe');
      try {
        await entered.future.timeout(kStableStateWait);
        await call.abortInFlight();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      } finally {
        release.complete();
        await probe.finished.future.timeout(kCompletionWait);
        await statementFinished.future.timeout(kCompletionWait);
      }
      expect(attemptedStatement, isTrue);
      expect(
        await fixture.probeRowCount('statement-after-disconnect'),
        0,
        reason: 'Cancellation must reject new SQL before the driver sends it.',
      );
      expect(probe.error, isNotNull);
      expect(await fixture.rowCount('cancellation-after-disconnect-probe'), 0);
      await fixture.assertUsable('cancellation-after-cancelled-scope');
    });

    test('a busy one-slot pool cancels only its leased backend', () async {
      final witness = await Connection.open(
        fixture.target.databaseEnv.pgEndpoint,
        settings: fixture.target.databaseEnv.pgEndpointSettings,
      );
      final witnessPid =
          (await witness.execute('SELECT pg_backend_pid()')).single.single!
              as int;
      final witnessSql = witness
          .execute('SELECT pg_sleep(30)')
          .then<Object?>(
            (_) => null,
            onError: (Object error) => error,
          );
      CancellationBackend? backend;
      var stopped = false;
      var witnessStillRunning = false;
      try {
        await fixture.waitForBackend(
          (candidate) =>
              candidate.pid == witnessPid && candidate.waitEvent == 'PgSleep',
        );
        final call = await fixture.create('cancellation-sql-owned-backend');
        backend = await fixture.waitForBackend(
          (candidate) =>
              candidate.pid != witnessPid && candidate.waitEvent == 'PgSleep',
        );
        expect(fixture.pool.admission.running, 1);
        await call.abortInFlight();
        stopped = await fixture.backendStopped(backend);
        final activeWitness = await fixture.writer.execute(
          Sql.named('''
            SELECT 1 FROM pg_stat_activity
            WHERE datname = current_database() AND pid = @pid
              AND state = 'active' AND wait_event = 'PgSleep'
          '''),
          parameters: {'pid': witnessPid},
        );
        witnessStillRunning = activeWitness.length == 1;
      } finally {
        if (backend != null && !stopped) {
          await fixture.releaseHungBackend(backend);
        }
        await fixture.writer.execute(
          Sql.named('''
            SELECT pg_cancel_backend(@pid) WHERE EXISTS (
              SELECT 1 FROM pg_stat_activity
              WHERE datname = current_database() AND pid = @pid
                AND state = 'active' AND query = 'SELECT pg_sleep(30)'
            )
          '''),
          parameters: {'pid': witnessPid},
        );
        await witnessSql.timeout(kCompletionWait);
        await witness.close();
      }
      expect(witnessStillRunning, isTrue);
      expect(await fixture.rowCount('cancellation-sql-owned-backend'), 0);
      await fixture.assertUsable('cancellation-after-control-path');
      expect(
        stopped,
        isTrue,
        reason:
            'Cancellation must reach the owned backend while the only '
            'application connection is busy. A SQL control query cannot '
            'queue behind that backend or target a different session.',
      );
    });

    test('a disconnect interrupts a PostgreSQL lock wait', () async {
      await fixture.lock(cancellationLockKey);
      CancellationBackend? backend;
      var stopped = false;
      try {
        final call = await fixture.create('cancellation-lock-wait');
        backend = await fixture.waitForBackend(
          (backend) => backend.waitEvent == 'advisory',
        );
        await call.abortInFlight();
        stopped = await fixture.backendStopped(backend);
        if (!stopped) await fixture.releaseHungBackend(backend);
      } finally {
        await fixture.unlock(cancellationLockKey);
      }

      expect(await fixture.rowCount('cancellation-lock-wait'), 0);
      await fixture.assertUsable('cancellation-after-lock-wait');
      expect(
        stopped,
        isTrue,
        reason:
            'The cancelled statement must leave the lock queue before '
            'the blocker is released or lock_timeout expires.',
      );
    });

    test('a disconnect interrupts SQL waiting for MeritRank RPC', () async {
      final (blackhole, unavailable) = await MeritRankBlackhole.probe();
      if (blackhole == null) {
        markTestSkipped(unavailable!);
        return;
      }
      // A cache hit would never enter the connector. Warm the connector,
      // invalidate only this viewer, then hold the real MR receive wait.
      await fixture.writer.execute('SELECT count(*) FROM mr_edgelist()');
      await fixture.writer.execute(
        Sql.named('''
          DELETE FROM public.person_visible_set_cache WHERE viewer_id = @viewer
        '''),
        parameters: {'viewer': cancellationActor},
      );
      CancellationBackend? backend;
      var stopped = false;
      await blackhole.engage();
      try {
        final call = await fixture.fullSnapshot();
        backend = await fixture.waitForBackend(
          (backend) => backend.query.contains('person_visible_peer_ids_tx'),
        );
        await call.abortInFlight();
        stopped = await fixture.backendStopped(backend);
      } finally {
        await blackhole.release();
        if (backend != null && !stopped) {
          await fixture.releaseHungBackend(backend);
        }
      }

      await fixture.assertUsable('cancellation-after-mr-rpc');
      expect(
        stopped,
        isTrue,
        reason:
            'Cancellation must interrupt the deployed pgmer2 connector '
            'while MeritRank is still blackholed.',
      );
    });

    test(
      'a disconnect at COMMIT rolls back and operation replay writes once',
      () async {
        const title = 'cancellation-commit-mutation';
        const operationKey = 'cancellation-commit-operation';
        await fixture.lock(cancellationCommitKey);
        var stopped = false;
        try {
          final call = await fixture.create(title, clientOpId: operationKey);
          final backend = await fixture.waitForBackend(
            (backend) =>
                backend.waitEvent == 'advisory' &&
                backend.query.trim().toUpperCase().startsWith('COMMIT'),
          );
          await call.abortInFlight();
          stopped = await fixture.backendStopped(backend);
          if (!stopped) await fixture.releaseHungBackend(backend);
          expect(
            await fixture.rowCount(title),
            0,
            reason: 'The deferred trigger is held before the commit boundary.',
          );
        } finally {
          await fixture.unlock(cancellationCommitKey);
        }

        final retry = await fixture.create(title, clientOpId: operationKey);
        await retry.done.timeout(kCompletionWait);
        retry.expectSuccess();
        final replay = await fixture.create(title, clientOpId: operationKey);
        await replay.done.timeout(kCompletionWait);
        replay.expectSuccess();
        expect(replay.payload!['data'], retry.payload!['data']);
        expect(await fixture.rowCount(title), 1);
        expect(fixture.pool.admission.running, 0);
        expect(stopped, isTrue);
      },
    );

    test(
      'a mandatory server deadline stops SQL while the caller stays connected',
      () async {
        final call = await fixture.create('cancellation-sql-server-deadline');
        final backend = await fixture.waitForBackend(
          (backend) => backend.waitEvent == 'PgSleep',
        );
        // Interactive work has a five-second server budget in the design.
        // One second allows protocol/rollback drain; the connection-wide
        // statement timeout remains 30 seconds and cannot satisfy this gate.
        final stopped = await fixture.backendStopped(
          backend,
          budget: const Duration(seconds: 6),
        );
        if (!stopped) await fixture.releaseHungBackend(backend);
        await call.done.timeout(kCompletionWait);

        expect(call.transportError, isNull);
        expect(call.payload!['errors'], isNotEmpty);
        expect(await fixture.rowCount('cancellation-sql-server-deadline'), 0);
        await fixture.assertUsable('cancellation-after-server-deadline');
        expect(
          stopped,
          isTrue,
          reason:
              'The server must enforce a deadline even without a timely '
              'browser disconnect signal.',
        );
      },
    );

    test(
      'a disconnect after scope release leaves its next owner running',
      () async {
        final releasedScope = Completer<void>();
        final releaseResolver = Completer<void>();
        late int originalPid;
        final probe = fixture.probeNextCreate((database) async {
          await database.withConnectionScope(
            () async {
              final row = await database
                  .customSelect('SELECT pg_backend_pid() AS pid')
                  .getSingle();
              originalPid = row.read<int>('pid');
            },
            actorUserId: cancellationActor,
          );
          releasedScope.complete();
          // Keep the original HTTP request and its cancellation context alive
          // after the DB lease has ended, unlike aborting a finished response.
          await releaseResolver.future;
        });
        final abandoned = await fixture.create('cancellation-released-scope');
        await releasedScope.future.timeout(kStableStateWait);
        expect(abandoned.payload, isNull);
        await fixture.lock(cancellationLockKey);
        CancellationHttpCall? successor;
        var successorStillRunning = false;
        try {
          successor = await fixture.create(
            'cancellation-lock-next-scope-owner',
          );
          final reused = await fixture.waitForBackend(
            (backend) => backend.waitEvent == 'advisory',
          );
          expect(
            reused.pid,
            originalPid,
            reason: 'Force actual backend reuse.',
          );
          await abandoned.abortInFlight();
          await Future<void>.delayed(const Duration(milliseconds: 350));
          final active = await fixture.writer.execute(
            Sql.named('''
            SELECT 1 FROM pg_stat_activity
            WHERE datname = current_database() AND pid = @pid
              AND state = 'active' AND wait_event = 'advisory'
          '''),
            parameters: {'pid': reused.pid},
          );
          successorStillRunning = active.length == 1;
        } finally {
          await fixture.unlock(cancellationLockKey);
          releaseResolver.complete();
          await probe.finished.future.timeout(kCompletionWait);
        }
        await successor.done.timeout(kCompletionWait);
        successor.expectSuccess();
        expect(successorStillRunning, isTrue);
        expect(await fixture.rowCount('cancellation-lock-next-scope-owner'), 1);
        await fixture.assertUsable('cancellation-after-released-scope');
      },
    );

    test('a late disconnect cannot cancel SQL on a reused backend', () async {
      await fixture.lock(cancellationCommitKey);
      late CancellationHttpCall completed;
      late CancellationBackend original;
      try {
        completed = await fixture.create('cancellation-commit-completed');
        original = await fixture.waitForBackend(
          (backend) =>
              backend.waitEvent == 'advisory' &&
              backend.query.trim().toUpperCase().startsWith('COMMIT'),
        );
      } finally {
        await fixture.unlock(cancellationCommitKey);
      }
      await completed.done.timeout(kCompletionWait);
      completed.expectSuccess();

      await fixture.lock(cancellationLockKey);
      late CancellationHttpCall survivor;
      late CancellationBackend reused;
      Result? stillWaiting;
      try {
        survivor = await fixture.create('cancellation-lock-surviving-request');
        reused = await fixture.waitForBackend(
          (backend) => backend.waitEvent == 'advisory',
        );
        expect(
          reused.pid,
          original.pid,
          reason: 'A one-slot pool and long connection age force real reuse.',
        );
        // The first caller's HTTP connection remains open after its response.
        // Now close it while a different request owns that same SQL backend.
        completed.abort();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        stillWaiting = await fixture.writer.execute(
          Sql.named('''
            SELECT 1 FROM pg_stat_activity
            WHERE datname = current_database() AND pid = @pid
              AND state = 'active' AND wait_event = 'advisory'
          '''),
          parameters: {'pid': reused.pid},
        );
      } finally {
        await fixture.unlock(cancellationLockKey);
      }
      await survivor.done.timeout(kCompletionWait);
      survivor.expectSuccess();
      expect(stillWaiting, hasLength(1));
      expect(await fixture.rowCount('cancellation-commit-completed'), 1);
      expect(await fixture.rowCount('cancellation-lock-surviving-request'), 1);
      expect(fixture.pool.admission.running, 0);
    });
  });

  group('PostgreSQL retries share the HTTP request lifetime', () {
    test(
      'authentication and earlier attempts spend the original deadline',
      () async {
        final pause = fixture.pauseBeforeAdmission();
        final elapsed = Stopwatch()..start();
        final starts = <Duration>[];
        final probe = fixture.probeNextCreate((database) {
          return database.withMutatingRepeatableRead<void>(
            cancellationActor,
            () async {
              starts.add(elapsed.elapsed);
              if (starts.length == 1) {
                await database.customSelect('SELECT pg_sleep(1)').get();
                throw const PostgresSnapshotUnavailableException(
                  'first-attempt snapshot conflict',
                );
              }
              await database.customSelect('SELECT pg_sleep(30)').get();
              await database.customStatement('''
              INSERT INTO public.request_cancellation_probe (label)
              VALUES ('retry-after-request-deadline')
            ''');
            },
          );
        });
        final call = await fixture.create(
          'cancellation-original-retry-deadline',
        );
        try {
          await pause.entered.future.timeout(kStableStateWait);
          // Auth is part of the same interactive request's five-second budget.
          await Future<void>.delayed(const Duration(milliseconds: 2500));
        } finally {
          pause.release.complete();
        }
        await probe.finished.future.timeout(kCompletionWait);
        await call.done.timeout(kCompletionWait);
        final finishedAt = elapsed.elapsed;
        expect(
          starts,
          hasLength(2),
          reason: 'Exercise a real retry, not only expiry.',
        );
        expect(probe.error, isNotNull);
        expect(call.transportError, isNull);
        expect(call.payload!['errors'], isNotEmpty);
        expect(await fixture.probeRowCount('retry-after-request-deadline'), 0);
        expect(
          await fixture.rowCount('cancellation-original-retry-deadline'),
          0,
        );
        await fixture.assertUsable('cancellation-after-retry-deadline');
        expect(
          finishedAt,
          lessThan(const Duration(seconds: 6)),
          reason:
              'The retry must use what remains of the original five-second '
              'HTTP budget, including authentication and the first attempt; '
              'one second allows cancellation and rollback to drain.',
        );
      },
    );

    test(
      'disconnect prevents another attempt after a retryable failure',
      () async {
        final firstAttempt = Completer<void>();
        final releaseFailure = Completer<void>();
        var attempts = 0;
        final probe = fixture.probeNextCreate((database) {
          return database.withMutatingRepeatableRead<void>(
            cancellationActor,
            () async {
              attempts++;
              if (attempts == 1) {
                await database
                    .customSelect('SELECT pg_backend_pid()')
                    .getSingle();
                firstAttempt.complete();
                await releaseFailure.future;
                throw const PostgresSnapshotUnavailableException(
                  'snapshot conflict arriving after disconnect',
                );
              }
              await database.customStatement('''
              INSERT INTO public.request_cancellation_probe (label)
              VALUES ('retry-after-disconnect')
            ''');
            },
          );
        });
        final call = await fixture.create('cancellation-disconnected-retry');
        try {
          await firstAttempt.future.timeout(kStableStateWait);
          await call.abortInFlight();
          await Future<void>.delayed(const Duration(milliseconds: 350));
        } finally {
          releaseFailure.complete();
          await probe.finished.future.timeout(kCompletionWait);
        }
        expect(
          attempts,
          1,
          reason:
              'A retryable SQL failure must not revive an abandoned request.',
        );
        expect(probe.error, isNotNull);
        expect(await fixture.probeRowCount('retry-after-disconnect'), 0);
        expect(await fixture.rowCount('cancellation-disconnected-retry'), 0);
        await fixture.assertUsable('cancellation-after-disconnected-retry');
      },
    );

    test(
      'sequential SQL statements spend one cumulative request budget',
      () async {
        var completedStatements = 0;
        final elapsed = Stopwatch()..start();
        final probe = fixture.probeNextCreate((database) {
          return database.withMutatingUser<void>(cancellationActor, () async {
            for (var i = 0; i < 4; i++) {
              // Every statement is shorter than the five-second budget, while
              // the complete chain exceeds it. A per-statement cap alone fails.
              await database.customSelect('SELECT pg_sleep(1.75)').get();
              completedStatements++;
            }
            await database.customStatement('''
            INSERT INTO public.request_cancellation_probe (label)
            VALUES ('cumulative-sql-deadline')
          ''');
          });
        });
        final call = await fixture.create('cancellation-cumulative-deadline');
        await probe.finished.future.timeout(kCompletionWait);
        await call.done.timeout(kCompletionWait);
        final finishedAt = elapsed.elapsed;
        expect(completedStatements, lessThan(4));
        expect(probe.error, isNotNull);
        expect(call.transportError, isNull);
        expect(call.payload!['errors'], isNotEmpty);
        expect(await fixture.probeRowCount('cumulative-sql-deadline'), 0);
        expect(await fixture.rowCount('cancellation-cumulative-deadline'), 0);
        await fixture.assertUsable('cancellation-after-cumulative-deadline');
        expect(finishedAt, lessThan(const Duration(seconds: 6)));
      },
    );
  });
}
