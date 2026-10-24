@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// Postgres integration test — skipped in CI when DB is down.
///
/// See `packages/server/README.md` § Tests for the full list and how to run.
Future<void> main() async {
  final postgresReachable = await canReachPostgresAdmin(_target);
  DisposablePgWriterSession? pgSession;
  if (postgresReachable) {
    pgSession = await setUpDisposablePgWriter(target: _target);
    tearDownAll(() => tearDownDisposablePgWriter(session: pgSession!));
  }
  final skipReason =
      postgresReachable ? false : 'local Postgres not reachable';

  const userId = 'Uquota_test1';

  late TenturaDb db;
  late UploadQuotaRepository repo;

  if (postgresReachable) {
    setUpAll(() async {
      final env = _testEnv();
      db = TenturaDb(env);
      repo = UploadQuotaRepository(db);
      await db.customStatement('''
CREATE TABLE IF NOT EXISTS public.upload_daily_usage (
  user_id text NOT NULL
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  usage_date date NOT NULL,
  bytes bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, usage_date)
)
''');
      await db.customStatement(
        'INSERT INTO public."user" (id, public_key) VALUES (\$1, \$2) '
        'ON CONFLICT (id) DO NOTHING',
        [userId, 'quota-test-pubkey-1'],
      );
    });

    tearDown(() async {
      await db.customStatement(
        'DELETE FROM public.upload_daily_usage WHERE user_id = \$1',
        [userId],
      );
    });

    tearDownAll(() async {
      await db.customStatement(
        'DELETE FROM public."user" WHERE id = \$1',
        [userId],
      );
      await db.close();
    });
  }

  test(
    'tryReserveDailyBytes accumulates usage while within the cap',
    () async {
      const cap = 1000;
      expect(
        await repo.tryReserveDailyBytes(
          userId: userId,
          bytes: 400,
          dailyCapBytes: cap,
        ),
        isTrue,
      );
      expect(await repo.usedBytesToday(userId), 400);

      expect(
        await repo.tryReserveDailyBytes(
          userId: userId,
          bytes: 600,
          dailyCapBytes: cap,
        ),
        isTrue,
      );
      expect(await repo.usedBytesToday(userId), 1000);
    },
    skip: skipReason,
  );

  test(
    'tryReserveDailyBytes rejects and rolls back when over the cap',
    () async {
      const cap = 1000;
      await repo.tryReserveDailyBytes(
        userId: userId,
        bytes: 900,
        dailyCapBytes: cap,
      );

      // Would push total to 1100 (> cap): rejected and not retained.
      expect(
        await repo.tryReserveDailyBytes(
          userId: userId,
          bytes: 200,
          dailyCapBytes: cap,
        ),
        isFalse,
      );
      expect(await repo.usedBytesToday(userId), 900);

      // A smaller upload that still fits is accepted.
      expect(
        await repo.tryReserveDailyBytes(
          userId: userId,
          bytes: 100,
          dailyCapBytes: cap,
        ),
        isTrue,
      );
      expect(await repo.usedBytesToday(userId), 1000);
    },
    skip: skipReason,
  );
}

final _target = DisposablePgTarget.fromNamedEnvironment(
  envVarName: 'TENTURA_UPLOAD_QUOTA_REPOSITORY_TEST_DB',
  defaultNamePrefix: 'tentura_test_upload_quota_repository',
);

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: _target.databaseName,
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  printEnv: false,
  isDebugModeOn: false,
);
