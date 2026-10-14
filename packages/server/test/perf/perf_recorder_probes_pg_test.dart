// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:async';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../support/disposable_pg_target.dart';
import '../support/pg_wait.dart';
import 'perf_instruments.dart';
import 'perf_recorder.dart';

const _lockRowSql =
    'SELECT id FROM public.perf_scratch WHERE id = 1 FOR UPDATE';

/// Each recorder probe must observe the real thing: the connector counter and
/// the transaction, queue and lock timings below are produced by actually
/// doing the work against Postgres (and MeritRank) and are asserted to move,
/// so a recorder that emits constant zeros cannot pass.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_RECORDER_PROBES_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_probes',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for perf recorder probes test';

  group('perf recorder probes against a disposable database', () {
    late DisposablePgWriterSession session;
    late PerfDbMeter meter;
    late TenturaDb db;
    late PerfRecorder recorder;

    Map<String, Object?> section(String key) =>
        recorder.report.toJson()[key]! as Map<String, Object?>;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      await session.writer.execute(
        'CREATE TABLE public.perf_scratch (id int PRIMARY KEY, pad text)',
      );
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != false) return;
      await session.writer.execute('TRUNCATE public.perf_scratch');
      await session.writer.execute(
        "INSERT INTO public.perf_scratch VALUES (1, 'a')",
      );
      meter = PerfDbMeter();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          meter.instrument(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
          ),
          enableMigrations: false,
        ).interceptWith(meter),
      );
      recorder = PerfRecorder(
        fixture: 'recorder_probe',
        db: db,
        meter: meter,
        probeConnection: session.writer,
      );
    });

    tearDown(() async {
      if (skipReason != false) return;
      await db.close();
    });

    group('connector RPCs', () {
      test('counts the MeritRank RPC a statement made on the database '
          'connection', () async {
        await recorder.attempt(
          (_) => db.customSelect('SELECT count(*) FROM mr_edgelist()').get(),
        );

        // `mr_rpc_attempts()` is per backend, so the delta only moves when it
        // is read on the connection that issued the RPC, not on the probe.
        expect(section('connectorRpcs')['total'], 1);
      }, skip: skipReason);

      test('an attempt that never reaches MeritRank counts zero', () async {
        await recorder.attempt((_) => db.customSelect('SELECT 1').get());

        expect(section('connectorRpcs')['total'], 0);
      }, skip: skipReason);

      test('sums the RPCs of several statements within one attempt', () async {
        await recorder.attempt((_) async {
          await db.customSelect('SELECT count(*) FROM mr_edgelist()').get();
          await db.customSelect('SELECT count(*) FROM mr_edgelist()').get();
        });

        expect(section('connectorRpcs')['total'], 2);
      }, skip: skipReason);
    });

    group('transaction age', () {
      test('reports how long the attempt kept a transaction open', () async {
        await recorder.attempt(
          (_) => db.transaction(
            () => db.customSelect('SELECT pg_sleep(0.25)').get(),
          ),
        );

        final age = section('txAgeMs');
        expect(age['p95']! as num, greaterThanOrEqualTo(240));
        expect(age['p95']! as num, lessThan(5000));
      }, skip: skipReason);

      test('an attempt without a transaction has no transaction age', () async {
        await recorder.attempt((_) => db.customSelect('SELECT 1').get());

        expect(section('txAgeMs')['p95'], 0);
      }, skip: skipReason);
    });

    group('connection queue time', () {
      test('measures the wait behind a transaction holding the '
          'connection', () async {
        final holding = Completer<void>();
        final release = Completer<void>();
        final holder = db.transaction(() async {
          await db.customSelect('SELECT 1').get();
          holding.complete();
          await release.future;
        });
        await holding.future.timeout(kStableStateWait);

        final attempt = recorder.attempt(
          (_) => db.customSelect('SELECT 1').get(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        release.complete();
        await holder;
        await attempt;

        expect(
          section('connectionQueueMs')['p95']! as num,
          greaterThanOrEqualTo(250),
        );
      }, skip: skipReason);

      test('an uncontended attempt waits (almost) not at all', () async {
        await recorder.attempt((_) => db.customSelect('SELECT 1').get());

        expect(section('connectionQueueMs')['p95']! as num, lessThan(100));
      }, skip: skipReason);
    });

    group('query count', () {
      test('counts every statement the attempt ran through the database', () async {
        await recorder.attempt((_) async {
          await db.customSelect('SELECT 1').get();
          await db.customSelect('SELECT 2').get();
          await db.customStatement('SELECT 3');
        });

        expect(section('queryCount')['total'], 3);
      }, skip: skipReason);

      test('an attempt that never touches the database counts zero', () async {
        await recorder.attempt((_) async {});

        expect(section('queryCount')['total'], 0);
      }, skip: skipReason);

      test('keeps per-attempt counts apart for the percentiles', () async {
        await recorder.attempt((_) => db.customSelect('SELECT 1').get());
        await recorder.attempt((_) async {
          for (var i = 0; i < 4; i++) {
            await db.customSelect('SELECT 1').get();
          }
        });

        final queries = section('queryCount');
        expect(queries['total'], 5);
        expect(queries['p50'], 1);
        expect(queries['p95'], 4);
      }, skip: skipReason);

      test('ignores statements run outside any attempt', () async {
        await db.customSelect('SELECT 1').get();
        await db.customSelect('SELECT 2').get();

        await recorder.attempt((_) => db.customSelect('SELECT 3').get());

        expect(section('queryCount')['total'], 1);
      }, skip: skipReason);

      test('a failed attempt still counts the statements it ran', () async {
        await expectLater(
          recorder.attempt<void>((_) async {
            await db.customSelect('SELECT 1').get();
            await db.customSelect('SELECT 2').get();
            throw StateError('injected');
          }),
          throwsStateError,
        );

        expect(section('queryCount')['total'], 2);
      }, skip: skipReason);
    });

    group('lock waiters in the probed database', () {
      const lockKey = 'tentura_perf_recorder_lock';

      test('reports a session queued on a lock while the attempt ran', () async {
        final holder = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        try {
          final holding = Completer<void>();
          final release = Completer<void>();
          final held = holder.runTx((tx) async {
            await tx.execute(
              Sql.named('SELECT pg_advisory_xact_lock(hashtext(@k))'),
              parameters: {'k': lockKey},
            );
            holding.complete();
            await release.future;
          });
          await holding.future.timeout(kStableStateWait);

          final attempt = recorder.attempt(
            (_) => db.transaction(
              () => db
                  .customSelect(
                    r'SELECT pg_advisory_xact_lock(hashtext($1))',
                    variables: [Variable.withString(lockKey)],
                  )
                  .get(),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 600));
          release.complete();
          await held;
          await attempt;

          expect(section('lockWaiters')['max'], greaterThanOrEqualTo(1));
        } finally {
          await holder.close();
        }
      }, skip: skipReason);

      test('an attempt that waits on no lock reports none', () async {
        await recorder.attempt((_) => db.customSelect('SELECT 1').get());

        expect(section('lockWaiters')['max'], 0);
      }, skip: skipReason);
    });

    group('retry count', () {
      test(
        'counts a serialization failure that was retried to success',
        () async {
          var calls = 0;

          await recorder.attempt(
            (_) => db.withMutatingRepeatableRead('perf-user', () async {
              calls++;
              await db
                  .customSelect('SELECT pad FROM public.perf_scratch')
                  .get();
              if (calls == 1) {
                // A concurrent commit on the same row after this transaction's
                // snapshot makes the write below fail with 40001.
                await session.writer.execute(
                  "UPDATE public.perf_scratch SET pad = 'raced' WHERE id = 1",
                );
              }
              await db.customStatement(
                "UPDATE public.perf_scratch SET pad = 'mine' WHERE id = 1",
              );
            }),
          );

          expect(calls, 2);
          expect(section('retryCount')['total'], 1);
          expect(
            recorder.report.toJson()['attempts'],
            containsPair('failed', 0),
          );
        },
        skip: skipReason,
      );

      test('an attempt that needed no retry counts zero', () async {
        await recorder.attempt(
          (_) => db.withMutatingRepeatableRead(
            'perf-user',
            () => db.customStatement(
              "UPDATE public.perf_scratch SET pad = 'mine' WHERE id = 1",
            ),
          ),
        );

        expect(section('retryCount')['total'], 0);
      }, skip: skipReason);
    });

    group('cursor wait and hold', () {
      test('measures the wait on a row lock held by another session and the '
          'time the attempt then holds it', () async {
        final holding = Completer<void>();
        final release = Completer<void>();
        final holder = session.writer.runTx((tx) async {
          await tx.execute(_lockRowSql);
          holding.complete();
          await release.future;
        });
        await holding.future.timeout(kStableStateWait);

        final attempt = recorder.attempt(
          (scope) => db.transaction(
            () => scope.cursorLock(
              lockSql: _lockRowSql,
              hold: () => db.customSelect('SELECT pg_sleep(0.1)').get(),
            ),
          ),
        );
        Connection? probe;
        try {
          probe = await Connection.open(
            target.databaseEnv.pgEndpoint,
            settings: target.databaseEnv.pgEndpointSettings,
          );
          final lockProbe = PerfLockProbe(probe);
          final clock = Stopwatch()..start();
          // Start the timed hold only once the statement is actually blocked.
          while (await lockProbe.waitingLockCount() == 0) {
            if (clock.elapsed >= kStableStateWait) {
              throw TimeoutException('Cursor lock waiter did not start');
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        } finally {
          release.complete();
          await probe?.close();
          await holder;
          await attempt;
        }

        final wait = section('cursorWaitMs')['p95']! as num;
        final hold = section('cursorHoldMs')['p95']! as num;
        expect(wait, greaterThanOrEqualTo(250));
        expect(hold, greaterThanOrEqualTo(90));
        expect(hold, lessThan(wait));
      }, skip: skipReason);

      test('an uncontended lock is acquired without a wait', () async {
        await recorder.attempt(
          (scope) => db.transaction(
            () => scope.cursorLock(
              lockSql: _lockRowSql,
              hold: () => db.customSelect('SELECT 1').get(),
            ),
          ),
        );

        expect(section('cursorWaitMs')['p95']! as num, lessThan(100));
      }, skip: skipReason);
    });

    group('WAL bytes', () {
      test('attributes the WAL a write attempt generated and none to a read '
          'attempt', () async {
        await recorder.attempt(
          (_) => db.customStatement(
            "INSERT INTO public.perf_scratch SELECT g, repeat('x', 200) "
            'FROM generate_series(2, 1000) g',
          ),
        );
        final afterWrite = section('walBytes')['total']! as int;
        await recorder.attempt(
          (_) =>
              db.customSelect('SELECT count(*) FROM public.perf_scratch').get(),
        );
        final afterRead = section('walBytes')['total']! as int;

        expect(afterWrite, greaterThan(100 * 1000));
        expect(afterRead - afterWrite, lessThan(64 * 1024));
      }, skip: skipReason);
    });

    group('latency', () {
      test('runs from admission to the end of response encoding, apart from '
          'execution', () async {
        await recorder.attempt((scope) async {
          // Time spent queued for admission, before any statement runs.
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await scope.execution(
            () => db.customSelect('SELECT pg_sleep(0.03)').get(),
          );
          // Time spent encoding the response after the database is done.
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });

        final latency = section('latencyMs')['p50']! as num;
        final execution = section('executionMs')['p50']! as num;
        expect(latency, greaterThanOrEqualTo(220));
        expect(execution, greaterThanOrEqualTo(25));
        expect(execution, lessThan(latency - 150));
      }, skip: skipReason);

      test('a failed attempt still contributes its latency', () async {
        await expectLater(
          recorder.attempt<void>((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 150));
            throw StateError('injected');
          }),
          throwsStateError,
        );

        expect(section('latencyMs')['p50']! as num, greaterThanOrEqualTo(140));
        expect(section('attempts'), containsPair('failed', 1));
      }, skip: skipReason);
    });
  });
}
