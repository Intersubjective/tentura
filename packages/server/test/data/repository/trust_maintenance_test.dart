@Tags(['pg'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/domain/use_case/trust_maintenance_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasBatchRebuild(probe)) {
        skipReason = 'trust_rebuild_effective_batch missing (m0122 not applied)';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late TrustMaintenanceCase maintenance;

  const aliceId = 'UtmtAlice001';
  const bobId = 'UtmtBob00001';

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
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
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$aliceId', '$bobId')''',
      );
      await db.close();
    });
  }

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
}

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? 'localhost',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: Platform.environment['POSTGRES_DBNAME'] ?? 'postgres',
  pgUsername: Platform.environment['POSTGRES_USERNAME'] ?? 'postgres',
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

Future<bool> _canConnectPostgres() async {
  try {
    final db = TenturaDb(_testEnv());
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _hasBatchRebuild(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int > 0 AS ok FROM pg_proc
WHERE proname = 'trust_rebuild_effective_batch'
''',
  ).getSingle();
  return row.read<bool>('ok');
}
