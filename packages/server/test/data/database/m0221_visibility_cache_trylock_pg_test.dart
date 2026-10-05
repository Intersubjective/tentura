@Tags(['pg'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// m0221: `person_are_mutually_visible_cached` must not take a blocking
/// per-pair advisory lock. Concurrent Hasura inbox reads that walk authors
/// in different orders used to 40P01 (TENTURA-CLIENT-32).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0221_VISIBILITY_LOCK_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0221_vis_lock',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  test('the try-lock migration is registered', () {
    expect(migrationsForTesting.map((m) => m.version), contains('0221'));
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('cached visibility takes no per-pair advisory lock', () async {
      // m0221 switched to a try-lock; m0222 dropped the lock with the
      // cross-transaction cache table.
      final rows = await writer.execute('''
SELECT pg_get_functiondef(
  'public.person_are_mutually_visible_cached(text,text,text)'::regprocedure)
''');
      final def = rows.single.single! as String;
      expect(def, isNot(contains('pg_advisory_xact_lock')));
    });

    test('crossed concurrent pair walks do not deadlock', () async {
      const a = 'Um0221lockA0001';
      const b = 'Um0221lockB0001';
      const c = 'Um0221lockC0001';
      for (final id in [a, b, c]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
      }
      await writer.execute(
        'DELETE FROM public.person_mutual_visibility_cache',
      );

      final connA = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      final connB = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      try {
        await connA.execute('BEGIN');
        await connB.execute('BEGIN');

        await connA.execute(
          Sql.named(
            "SELECT public.person_are_mutually_visible_cached(@x, @y, '')",
          ),
          parameters: {'x': a, 'y': b},
        );
        await connB.execute(
          Sql.named(
            "SELECT public.person_are_mutually_visible_cached(@x, @y, '')",
          ),
          parameters: {'x': a, 'y': c},
        );

        await Future.wait([
          connA.execute(
            Sql.named(
              "SELECT public.person_are_mutually_visible_cached(@x, @y, '')",
            ),
            parameters: {'x': a, 'y': c},
          ),
          connB.execute(
            Sql.named(
              "SELECT public.person_are_mutually_visible_cached(@x, @y, '')",
            ),
            parameters: {'x': a, 'y': b},
          ),
        ]).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'crossed visibility-cache lock order hung (likely deadlock)',
          ),
        );

        await connA.execute('COMMIT');
        await connB.execute('COMMIT');
      } finally {
        await connA.close();
        await connB.close();
      }
    });

    test('try-lock miss still returns true trust and skips cache write', () async {
      const a = 'Um0221tryA00001';
      const b = 'Um0221tryB00001';
      for (final id in [a, b]) {
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');
      }
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES
  ('$a', '$b', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$b', '$a', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
      await writer.execute(
        'DELETE FROM public.person_mutual_visibility_cache',
      );

      final locker = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      final reader = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      try {
        await locker.execute('BEGIN');
        // Same key the cached helper uses: LEAST:GREATEST:ctx
        await locker.execute(
          Sql.named(
            "SELECT pg_advisory_xact_lock(hashtext(@k))",
          ),
          parameters: {
            'k': a.compareTo(b) <= 0 ? '$a:$b:' : '$b:$a:',
          },
        );

        final rows = await reader.execute(
          Sql.named(
            "SELECT public.person_are_mutually_visible_cached(@x, @y, '')",
          ),
          parameters: {'x': a, 'y': b},
        );
        expect(rows.single.single, isTrue);

        final cache = await writer.execute('''
SELECT count(*)::int FROM public.person_mutual_visibility_cache
WHERE person_lo = LEAST('$a', '$b') AND person_hi = GREATEST('$a', '$b')
''');
        expect(
          cache.single.single,
          0,
          reason: 'contended try-lock path must not write the cache',
        );

        await locker.execute('COMMIT');
      } finally {
        await locker.close();
        await reader.close();
      }
    });
  });
}
