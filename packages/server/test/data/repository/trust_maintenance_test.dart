@Tags(['pg', 'mr'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/trust_maintenance_sweep_repository.dart';
import 'package:tentura_server/domain/use_case/trust_maintenance_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_MAINTENANCE_TEST_DB',
    defaultNamePrefix: 'tentura_test_tmt',
  );
  final reachable = await canReachPostgresAdmin(target);
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
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);

      if (!await _hasPairProjection(writer)) {
        throw StateError(
          'trust_project_pair missing after migrateDbSchema',
        );
      }

      db = TenturaDb(target.databaseEnv);
      maintenance = TrustMaintenanceCase(
        TrustMaintenanceSweepRepository(db),
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
        "DELETE FROM public.trust_evidence "
        "WHERE subject_user_id IN ('$aliceId', '$bobId') "
        "OR object_user_id IN ('$aliceId', '$bobId')",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge "
        "WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId')",
      );
      await db.customStatement(
        "DELETE FROM public.trust_publish_queue "
        "WHERE subject_user_id IN ('$aliceId', '$bobId') "
        "OR object_user_id IN ('$aliceId', '$bobId')",
      );
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });

    test('first runDue succeeds on empty pair set', () async {
      await expectLater(maintenance.runDue(), completes);
    }, skip: skipReason);

    test('immediate second runDue respects sweep interval', () async {
      final now = DateTime.utc(2026, 3, 1, 12);
      await maintenance.runDue(now: now);
      await expectLater(maintenance.runDue(now: now), completes);
    }, skip: skipReason);
  });
}

Future<bool> _hasPairProjection(Connection connection) async {
  final rows = await connection.execute('''
SELECT count(*)::int > 0 AS ok FROM pg_proc
WHERE proname = 'trust_project_pair'
''');
  return rows.single.single as bool;
}
