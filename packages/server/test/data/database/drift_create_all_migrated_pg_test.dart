@Tags(['pg'])
library;

import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../../support/disposable_pg_target.dart';

/// tentura-nyr: Drift-generated `CREATE TABLE` for [Images] must parse on
/// Postgres when `public."user"` already exists from SQL migrations.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DRIFT_CREATE_ALL_MIGRATED_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_drift_create_all',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('Drift Images createTable DDL on SQL-migrated Postgres', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;

    const probeTable = 'image_drift_fk_probe';

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
          ).interceptWith(_stripSqliteWithoutRowId),
        );
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    test(
      'Migrator.createTable for Images author_id FK is accepted by Postgres',
      () async {
        final probe = db.images.createAlias(probeTable);
        await db.createMigrator().createTable(probe);
        await db.customStatement('DROP TABLE IF EXISTS $probeTable');
      },
      skip: skipReason,
    );
  });
}

/// Drift still appends SQLite's `WITHOUT ROWID` for [Images]; Postgres rejects
/// it. Strip only that suffix so the test exercises the real generated DDL.
final _stripSqliteWithoutRowId = _StripSqliteWithoutRowIdInterceptor();

final class _StripSqliteWithoutRowIdInterceptor extends QueryInterceptor {
  static final _withoutRowIdSuffix = RegExp(r'\s+WITHOUT ROWID;');

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final sql = statement.replaceFirst(_withoutRowIdSuffix, ';');
    return super.runCustom(executor, sql, args);
  }
}
