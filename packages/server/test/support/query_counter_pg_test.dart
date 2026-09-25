@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import 'disposable_pg_target.dart';
import 'query_counter.dart';

/// tentura-617.3 (plan §14.7 "RT counting"): [QueryCounter] must observe
/// every Drift-issued statement on an intercepted [TenturaDb], including the
/// BEGIN/COMMIT that `withMutatingUser` wraps its action in, so later beads
/// can budget realtime query counts per use case.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_QUERY_COUNTER_TEST_DB',
    defaultNamePrefix: 'tentura_test_query_counter',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('QueryCounter', () {
    late QueryCounter counter;
    late TenturaDb db;

    if (reachable) {
      setUpAll(() async {
        await target.recreate();
      });

      tearDownAll(() async {
        await target.drop();
      });
    }

    setUp(() {
      if (!reachable) return;
      counter = QueryCounter();
      db = TenturaDb.forTest(
        database: PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [target.databaseEnv.pgEndpoint],
            settings: target.databaseEnv.pgPoolSettings,
          ),
          enableMigrations: false,
        ).interceptWith(counter),
      );
    });

    tearDown(() async {
      if (!reachable) return;
      await db.close();
    });

    test('one customSelect counts as 1', () async {
      await db.customSelect('SELECT 1 AS c').get();

      expect(counter.count, 1);
    }, skip: skipReason);

    test(
      'withMutatingUser wrapping one statement counts BEGIN, set_config, '
      'the statement, and COMMIT as 4',
      () async {
        await db.withMutatingUser('Uquerycounter01', () async {
          await db.customStatement('SELECT 1');
        });

        expect(counter.count, 4);
      },
      skip: skipReason,
    );

    test('reset() returns count to 0', () async {
      await db.customSelect('SELECT 1 AS c').get();
      expect(counter.count, greaterThan(0));

      counter.reset();

      expect(counter.count, 0);
    }, skip: skipReason);
  });
}
