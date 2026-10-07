// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import '../support/pg_wait.dart';
import 'perf_instruments.dart';
import 'perf_report.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_INSTRUMENTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_instr',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for perf instruments test';

  group('perf instruments on a disposable database', () {
    late DisposablePgWriterSession session;
    Connection writer() => session.writer;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      await writer().execute(
        'CREATE TABLE public.perf_scratch (id int PRIMARY KEY, pad text)',
      );
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      if (skipReason != false) return;
      await writer().execute('TRUNCATE public.perf_scratch');
    });

    group('WalMeter', () {
      test('measures the WAL bytes a write generated', () async {
        final meter = WalMeter(writer());

        await meter.start();
        await writer().execute(
          "INSERT INTO public.perf_scratch SELECT g, repeat('x', 200) "
          'FROM generate_series(1, 1000) g',
        );
        final measurement = await meter.stop();

        expect(measurement.bytes, greaterThan(100 * 1000));
      }, skip: skipReason);

      test('a read-only window generates (almost) no WAL', () async {
        final meter = WalMeter(writer());

        await meter.start();
        await writer().execute('SELECT count(*) FROM public.perf_scratch');
        final measurement = await meter.stop();

        expect(measurement.bytes, lessThan(64 * 1024));
      }, skip: skipReason);

      test('labels the figure as a cluster total while another session is '
          'active', () async {
        final other = await Connection.open(
          target.adminEnv.pgEndpoint,
          settings: target.adminEnv.pgEndpointSettings,
        );
        final otherPid =
            (await other.execute('SELECT pg_backend_pid()')).first.first!
                as int;
        try {
          final sleeping = other.execute('SELECT pg_sleep(60)');
          // Swallow the cancellation raised when this test ends it.
          unawaited(sleeping.then<void>((_) {}, onError: (Object _) {}));
          await _waitUntil(
            () async {
              final rows = await writer().execute(
                Sql.named(
                  'SELECT 1 FROM pg_stat_activity WHERE pid = @pid '
                  "AND state = 'active'",
                ),
                parameters: {'pid': otherPid},
              );
              return rows.isNotEmpty;
            },
            timeout: kStableStateWait,
          );

          final meter = WalMeter(writer());
          await meter.start();
          final measurement = await meter.stop();

          expect(measurement.attribution, WalAttribution.clusterTotal);
        } finally {
          // `other` is still inside pg_sleep, so it cannot answer a query
          // here: cancel it by the pid read before the sleep started.
          await writer().execute('SELECT pg_cancel_backend($otherPid)');
          await other.close();
        }
      }, skip: skipReason);
    });

    group('PerfLockProbe', () {
      Future<Connection> openOn(Endpoint endpoint, ConnectionSettings s) =>
          Connection.open(endpoint, settings: s);

      test(
        'counts a session waiting on a lock inside the probed database',
        () async {
          const key = 'tentura_perf_probe_inside';
          final holder = await openOn(
            target.databaseEnv.pgEndpoint,
            target.databaseEnv.pgEndpointSettings,
          );
          final waiter = await openOn(
            target.databaseEnv.pgEndpoint,
            target.databaseEnv.pgEndpointSettings,
          );
          try {
            await holder.execute(
              Sql.named('SELECT pg_advisory_lock(hashtext(@k))'),
              parameters: {'k': key},
            );
            final waiting = waiter.execute(
              Sql.named('SELECT pg_advisory_lock(hashtext(@k))'),
              parameters: {'k': key},
            );
            unawaited(waiting.then<void>((_) {}, onError: (Object _) {}));
            final probe = PerfLockProbe(writer());

            await _waitUntil(
              () async => await probe.waitingLockCount() == 1,
              timeout: kStableStateWait,
            );

            expect(await probe.waitingLockCount(), 1);
          } finally {
            await holder.close();
            await waiter.close();
          }
        },
        skip: skipReason,
      );

      test('ignores a session waiting on a lock in another database', () async {
        const key = 'tentura_perf_probe_outside';
        final holder = await openOn(
          target.adminEnv.pgEndpoint,
          target.adminEnv.pgEndpointSettings,
        );
        final waiter = await openOn(
          target.adminEnv.pgEndpoint,
          target.adminEnv.pgEndpointSettings,
        );
        try {
          await holder.execute(
            Sql.named('SELECT pg_advisory_lock(hashtext(@k))'),
            parameters: {'k': key},
          );
          final waiting = waiter.execute(
            Sql.named('SELECT pg_advisory_lock(hashtext(@k))'),
            parameters: {'k': key},
          );
          unawaited(waiting.then<void>((_) {}, onError: (Object _) {}));
          // The waiter is queued once the admin database shows it, which the
          // probe under test is not allowed to see.
          await _waitUntil(
            () async {
              final rows = await holder.execute(
                "SELECT 1 FROM pg_locks WHERE locktype = 'advisory' "
                'AND NOT granted AND database = '
                '(SELECT oid FROM pg_database WHERE datname = '
                'current_database())',
              );
              return rows.isNotEmpty;
            },
            timeout: kStableStateWait,
          );

          expect(await PerfLockProbe(writer()).waitingLockCount(), 0);
        } finally {
          await holder.close();
          await waiter.close();
        }
      }, skip: skipReason);
    });

    group('captureExplain', () {
      test('keeps EXPLAIN (ANALYZE, BUFFERS, WAL) JSON for a read', () async {
        final capture = await captureExplain(
          writer(),
          label: 'scratch_count',
          sql: 'SELECT count(*) FROM public.perf_scratch',
        );

        expect(capture.label, 'scratch_count');
        expect(capture.rolledBack, isFalse);
        final root = (capture.plan! as List<Object?>).single! as Map;
        expect(root['Execution Time'], isA<num>());
        final plan = root['Plan']! as Map;
        expect(plan, contains('Shared Hit Blocks'));
        expect(plan, contains('WAL Records'));
      }, skip: skipReason);

      test('a mutating statement is explained inside a transaction that is '
          'rolled back', () async {
        final capture = await captureExplain(
          writer(),
          label: 'scratch_insert',
          sql: "INSERT INTO public.perf_scratch VALUES (1, 'x')",
          mutating: true,
        );

        expect(capture.rolledBack, isTrue);
        final root = (capture.plan! as List<Object?>).single! as Map;
        expect((root['Plan']! as Map)['Node Type'], 'ModifyTable');
        final remaining = await writer().execute(
          'SELECT count(*)::int FROM public.perf_scratch',
        );
        expect(remaining.first.first, 0);
      }, skip: skipReason);

      test('the connection stays usable after a rolled-back capture', () async {
        await captureExplain(
          writer(),
          label: 'scratch_insert',
          sql: "INSERT INTO public.perf_scratch VALUES (2, 'x')",
          mutating: true,
        );

        await writer().execute(
          "INSERT INTO public.perf_scratch VALUES (3, 'y')",
        );

        final rows = await writer().execute(
          'SELECT id FROM public.perf_scratch',
        );
        expect(rows.map((r) => r.first), [3]);
      }, skip: skipReason);
    });
  });
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not reached', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
