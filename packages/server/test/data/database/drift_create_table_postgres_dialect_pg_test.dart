@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

/// tentura-uggd: Drift's `Migrator.createAll` / `createTable` must not emit
/// SQLite's `WITHOUT ROWID` suffix on Postgres (SQLSTATE 42601). The DDL is
/// captured, not executed, so the assertion does not depend on which tables
/// already exist in the SQL-migrated schema.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DRIFT_CREATE_TABLE_DIALECT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_drift_ddl',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('Drift createTable DDL on the Postgres dialect', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    final captured = _CaptureDdlInterceptor();

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(captured),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'createTable for Users emits no WITHOUT ROWID suffix',
      () async {
        captured.statements.clear();
        await db.createMigrator().createTable(db.users);

        final createUser = captured.statements.where(
          (s) => s.startsWith('CREATE TABLE'),
        );
        expect(createUser, isNotEmpty);
        for (final sql in createUser) {
          expect(sql.toUpperCase(), isNot(contains('WITHOUT ROWID')));
        }
      },
      skip: skipReason,
    );

    test(
      'createTable emits no WITHOUT ROWID suffix for any Tentura table',
      () async {
        captured.statements.clear();
        final migrator = db.createMigrator();
        for (final table in db.allTables) {
          await migrator.createTable(table);
        }

        final offenders = captured.statements
            .where((s) => s.toUpperCase().contains('WITHOUT ROWID'))
            .map((s) => s.split('(').first.trim())
            .toList();
        expect(
          offenders,
          isEmpty,
          reason: 'Postgres rejects SQLite WITHOUT ROWID DDL',
        );
      },
      skip: skipReason,
    );
  });
}

/// Records DDL statements and swallows them, so nothing is executed.
final class _CaptureDdlInterceptor extends QueryInterceptor {
  final statements = <String>[];

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    statements.add(statement);
  }
}
