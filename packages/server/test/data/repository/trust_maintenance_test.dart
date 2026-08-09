@Tags(['pg'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/domain/use_case/trust_maintenance_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;
  late TrustMaintenanceCase maintenance;

  const aliceId = 'UtmtAlice001';
  const bobId = 'UtmtBob00001';

  group('TrustMaintenanceCase', () {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      // MeritRank functions are provisioned outside Dart migrations.
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      if (!await _hasBatchRebuild(writer)) {
        throw StateError(
          'trust_rebuild_effective_batch missing after migrateDbSchema',
        );
      }

      db = TenturaDb(target.databaseEnv);
      maintenance = TrustMaintenanceCase(
        db,
        MeritrankRepository(db),
        env: Env(
          environment: Environment.test,
          trustSweepInterval: const Duration(hours: 1),
          trustSweepRetry: const Duration(minutes: 5),
        ),
        logger: Logger('TrustMaintenanceTest'),
      );
      for (final entry in [
        (aliceId, 1),
        (bobId, 2),
      ]) {
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('${entry.$1}', '${entry.$1}', '${pgTestPublicKey('mtn', entry.$2)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.user_trust_source_edge "
        "WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId')",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge "
        "WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId')",
      );
      await db.customStatement(
        "DELETE FROM public.meritrank_edge_tombstone "
        "WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId')",
      );
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });

    test('first runDue succeeds on empty tombstone set', () async {
      await expectLater(maintenance.runDue(), completes);
    }, skip: skipReason);

    test('immediate second runDue respects sweep interval', () async {
      final now = DateTime.utc(2026, 3, 1, 12);
      await maintenance.runDue(now: now);
      await expectLater(maintenance.runDue(now: now), completes);
    }, skip: skipReason);

    test('rebuild restores stale effective edge from source', () async {
      await db
          .customSelect(
            r'SELECT trust_apply_source_evidence($1, $2, $3, $4, $5)',
            variables: [
              const Variable<String>('personal'),
              Variable<String>(aliceId),
              Variable<String>(bobId),
              const Variable<String>('good'),
              const Variable<double>(1),
            ],
          )
          .getSingle();
      await db
          .customSelect(
            r'SELECT trust_rebuild_effective_edge($1, $2)',
            variables: [
              Variable<String>(aliceId),
              Variable<String>(bobId),
            ],
          )
          .getSingle();
      await db.customStatement(
        '''
UPDATE user_trust_edge SET s_good = 0, updated_at = now()
WHERE subject = '$aliceId' AND object = '$bobId'
''',
      );
      await db
          .customSelect(
            r'SELECT trust_rebuild_effective_edge($1, $2, $3)',
            variables: [
              Variable<String>(aliceId),
              Variable<String>(bobId),
              const Variable<double>(-1),
            ],
          )
          .getSingle();
      final row = await db.customSelect(
        "SELECT s_good FROM user_trust_edge WHERE subject = '$aliceId' AND object = '$bobId'",
      ).getSingle();
      expect(row.read<double>('s_good'), greaterThan(0));
    }, skip: skipReason);
  });
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_TRUST_MAINTENANCE_TEST_DB'] ??
        'tentura_test_tmt_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_TRUST_MAINTENANCE_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      final remaining = await connection.execute(
        r'SELECT count(*)::int FROM pg_database WHERE datname = $1',
        parameters: [databaseName],
      );
      if (remaining.single.single != 0) {
        throw StateError('Disposable database was not dropped: $databaseName');
      }
    } finally {
      await connection.close();
    }
  }
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

Future<bool> _hasBatchRebuild(Connection connection) async {
  final rows = await connection.execute('''
SELECT count(*)::int > 0 AS ok FROM pg_proc
WHERE proname = 'trust_rebuild_effective_batch'
''');
  return rows.single.single as bool;
}
