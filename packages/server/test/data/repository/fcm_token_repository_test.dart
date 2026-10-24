@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/fcm_token_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

/// Postgres integration test — skipped in CI when DB is down.
///
/// Regression coverage for the reclaim `DELETE` inside `putToken`: it used
/// to bind `?` placeholders, which drift_postgres never rewrites to
/// `$1/$2/...`, so Postgres raised a syntax error on every call and the
/// whole transaction (including the upsert) rolled back. `FcmCase
/// .registerToken` swallowed that exception and returned `false`, so no FCM
/// token ever actually persisted.
Future<void> main() async {
  final postgresReachable = await canReachPostgresAdmin(_target);
  DisposablePgWriterSession? pgSession;
  if (postgresReachable) {
    pgSession = await setUpDisposablePgWriter(target: _target);
    tearDownAll(() => tearDownDisposablePgWriter(session: pgSession!));
  }
  final skipReason =
      postgresReachable ? false : 'local Postgres not reachable';

  const userId = 'Ufcmtoken_tst1';
  final appIdA = const Uuid().v4();
  final appIdB = const Uuid().v4();

  late TenturaDb db;
  late FcmTokenRepository repo;

  if (postgresReachable) {
    setUpAll(() async {
      final env = _testEnv();
      db = TenturaDb(env);
      repo = FcmTokenRepository(db);
      await db.customStatement(
        'INSERT INTO public."user" (id, public_key) VALUES (\$1, \$2) '
        'ON CONFLICT (id) DO NOTHING',
        [userId, 'fcm-token-test-pubkey-1'],
      );
    });

    tearDown(() async {
      await db.customStatement(
        'DELETE FROM public.fcm_token WHERE user_id = \$1',
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
    'putToken inserts a row retrievable by getTokensByUserId',
    () async {
      await repo.putToken(
        userId: userId,
        appId: appIdA,
        token: 'token-a',
        platform: 'web',
      );

      final rows = await repo.getTokensByUserId(userId);
      expect(rows.map((e) => e.token), contains('token-a'));
    },
    skip: skipReason,
  );

  test(
    'putToken upserts on conflict (same user+app, refreshed token)',
    () async {
      await repo.putToken(
        userId: userId,
        appId: appIdA,
        token: 'token-a',
        platform: 'web',
      );
      await repo.putToken(
        userId: userId,
        appId: appIdA,
        token: 'token-a-refreshed',
        platform: 'web',
      );

      final rows = await repo.getTokensByUserId(userId);
      expect(rows.length, 1);
      expect(rows.single.token, 'token-a-refreshed');
    },
    skip: skipReason,
  );

  test(
    'putToken reclaims a token that moved to a different app for the '
    'same user',
    () async {
      await repo.putToken(
        userId: userId,
        appId: appIdA,
        token: 'shared-token',
        platform: 'web',
      );

      // Same physical device token re-presented under a different appId
      // (e.g. reinstalled PWA) — the stale appIdA row must be reclaimed,
      // not left behind as a duplicate.
      await repo.putToken(
        userId: userId,
        appId: appIdB,
        token: 'shared-token',
        platform: 'web',
      );

      final rows = await repo.getTokensByUserId(userId);
      expect(rows.length, 1);
      expect(rows.single.appId.uuid, appIdB);
    },
    skip: skipReason,
  );
}

final _target = DisposablePgTarget.fromNamedEnvironment(
  envVarName: 'TENTURA_FCM_TOKEN_REPOSITORY_TEST_DB',
  defaultNamePrefix: 'tentura_test_fcm_token_repository',
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
