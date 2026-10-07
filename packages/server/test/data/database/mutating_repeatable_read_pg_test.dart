@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

/// `TenturaDb.withMutatingRepeatableRead`: a REPEATABLE READ READ WRITE
/// transaction with the same mutating-actor context as `withMutatingUser`,
/// retried as a whole (bounded, jittered, deadline-limited) on 40001.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MUTATING_REPEATABLE_READ_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_mut_rr',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  const actor = 'Umutrractor01';

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;

  Future<void> installProbe({required String failCondition}) async {
    await writer.execute('DROP TABLE IF EXISTS public.mut_rr_probe CASCADE');
    await writer.execute('DROP SEQUENCE IF EXISTS public.mut_rr_probe_seq');
    await writer.execute('CREATE SEQUENCE public.mut_rr_probe_seq');
    await writer.execute('''
CREATE TABLE public.mut_rr_probe (id serial PRIMARY KEY, actor text)
''');
    await writer.execute('''
CREATE OR REPLACE FUNCTION public.mut_rr_probe_fn() RETURNS trigger
LANGUAGE plpgsql AS \$\$
DECLARE _n bigint;
BEGIN
  _n := nextval('public.mut_rr_probe_seq');
  IF $failCondition THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'synthetic 40001';
  END IF;
  NEW.actor := current_setting('tentura.mutating_user_id', true);
  RETURN NEW;
END;
\$\$
''');
    await writer.execute('''
CREATE TRIGGER mut_rr_probe_trg BEFORE INSERT ON public.mut_rr_probe
FOR EACH ROW EXECUTE FUNCTION public.mut_rr_probe_fn()
''');
  }

  Future<void> insertProbeRow() =>
      db.customStatement('INSERT INTO public.mut_rr_probe DEFAULT VALUES');

  Future<int> probeRowCount() async {
    final rows = await writer.execute('SELECT count(*) FROM public.mut_rr_probe');
    return rows.single.single! as int;
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    db = openDisposablePgDatabase(target);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  group('withMutatingRepeatableRead', () {
    test('runs the action at repeatable read, read write', () async {
      final seen = await db.withMutatingRepeatableRead(actor, () async {
        final iso = await db
            .customSelect("SELECT current_setting('transaction_isolation') AS v")
            .getSingle();
        final ro = await db
            .customSelect("SELECT current_setting('transaction_read_only') AS v")
            .getSingle();
        return (iso.read<String>('v'), ro.read<String>('v'));
      });
      expect(seen.$1, 'repeatable read');
      expect(seen.$2, 'off');
    });

    test('exposes the actor to the action and to triggers', () async {
      await installProbe(failCondition: 'false');
      final inAction = await db.withMutatingRepeatableRead(actor, () async {
        expect(db.isInAmbientMutatingTransaction, isTrue);
        await insertProbeRow();
        final row = await db
            .customSelect(
              "SELECT current_setting('tentura.mutating_user_id') AS v",
            )
            .getSingle();
        return row.read<String>('v');
      });
      expect(inAction, actor);
      final rows = await writer.execute('SELECT actor FROM public.mut_rr_probe');
      expect(rows.single.single, actor);
    });

    test('rejects a nested call for a different actor', () async {
      await expectLater(
        db.withMutatingRepeatableRead(
          actor,
          () => db.withMutatingUser('Uother', () async {}),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('retries the whole transaction after a forced 40001', () async {
      await installProbe(failCondition: '_n = 1');
      var attempts = 0;
      final sleeps = <Duration>[];
      final result = await db.withMutatingRepeatableRead(
        actor,
        () async {
          attempts++;
          await insertProbeRow();
          return 'done';
        },
        sleep: (d) async => sleeps.add(d),
      );
      expect(result, 'done');
      expect(attempts, 2);
      expect(sleeps, hasLength(1));
      expect(sleeps.single, greaterThanOrEqualTo(Duration.zero));
      expect(await probeRowCount(), 1);
    });

    test('gives up after three attempts and rethrows the 40001', () async {
      await installProbe(failCondition: 'true');
      var attempts = 0;
      final sleeps = <Duration>[];
      await expectLater(
        db.withMutatingRepeatableRead(
          actor,
          () async {
            attempts++;
            await insertProbeRow();
          },
          sleep: (d) async => sleeps.add(d),
        ),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'code', '40001'),
        ),
      );
      expect(attempts, 3);
      expect(sleeps, hasLength(2));
      expect(await probeRowCount(), 0);
    });

    test('does not retry a non-serialization error', () async {
      var attempts = 0;
      await expectLater(
        db.withMutatingRepeatableRead(actor, () async {
          attempts++;
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1);
    });

    test('aborts with a typed error once the end-to-end deadline passes',
        () async {
      await installProbe(failCondition: 'true');
      var attempts = 0;
      await expectLater(
        db.withMutatingRepeatableRead(
          actor,
          () async {
            attempts++;
            await insertProbeRow();
          },
          deadline: const Duration(milliseconds: 100),
          sleep: (_) => Future<void>.delayed(const Duration(milliseconds: 250)),
        ),
        throwsA(isA<PostgresRetryDeadlineExceededException>()),
      );
      expect(attempts, lessThan(3));
    });

    test('backoff sleeps after rollback with the connection released',
        () async {
      await installProbe(failCondition: '_n = 1');
      final observations = <({bool ambient, int idleInTx})>[];
      await db.withMutatingRepeatableRead(
        actor,
        () => insertProbeRow(),
        sleep: (_) async {
          final rows = await writer.execute(
            Sql.named('''
SELECT count(*) FROM pg_stat_activity
WHERE datname = @db AND state LIKE 'idle in transaction%'
  AND pid <> pg_backend_pid()
'''),
            parameters: {'db': target.databaseName},
          );
          observations.add((
            ambient: db.isInAmbientMutatingTransaction,
            idleInTx: rows.single.single! as int,
          ));
        },
      );
      expect(observations, hasLength(1));
      expect(observations.single.ambient, isFalse);
      expect(observations.single.idleInTx, 0);
    });
  });
}
