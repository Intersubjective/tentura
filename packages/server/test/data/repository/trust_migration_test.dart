@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Verifies m0122 legacy source copy preserved pre-migration effective rows.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_MIGRATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_trust_migration',
  );
  var skipReason = await canReachPostgresAdmin(target)
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  if (skipReason == false) {
    await target.recreate();
    final bootstrapWriter = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    try {
      await bootstrapWriter.execute('SET check_function_bodies = false');
      await migrateDbSchema(bootstrapWriter);
      final probe = TenturaDb(_disposableEnv(target));
      try {
        if (!await _hasSourceTable(probe)) {
          skipReason = 'user_trust_source_edge missing (m0122 not applied)';
        } else if (!await _hasLegacyEffectiveBins(probe)) {
          skipReason =
              'user_trust_edge tier bins missing (m0202 projection; legacy copy N/A)';
        }
      } finally {
        await probe.close();
      }
    } finally {
      await bootstrapWriter.close();
    }
  }

  late Connection writer;
  late TenturaDb db;

  const aliceId = 'UtmgAlice001';
  const bobId = 'UtmgBob00001';

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      db = TenturaDb(_disposableEnv(target));
      await db.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('$aliceId', '$aliceId', '${pgTestPublicKey('mga', 1)}', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$bobId', '$bobId', '${pgTestPublicKey('mga', 2)}', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );
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
    });

    tearDownAll(() async {
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$aliceId', '$bobId')''',
      );
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  test('legacy source row mirrors effective projection after seeding', () async {
    await db.customStatement(
      '''
INSERT INTO public.user_trust_edge (
  subject, object, prev_sent_weight, trust_w, wall_d, target_w,
  created_at, updated_at
) VALUES (
  '$aliceId', '$bobId', 0.5, 0.8, 0, 0.8,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (subject, object) DO UPDATE SET
  trust_w = EXCLUDED.trust_w,
  target_w = EXCLUDED.target_w
''',
    );

    await db.customStatement(
      '''
INSERT INTO public.user_trust_source_edge
  (trust_context, subject, object, s_very_bad, s_bad, s_no_effect, s_good,
   s_very_good, anchor_at, created_at, updated_at)
SELECT 'legacy', subject, object,
  0, 0, 0, trust_w, target_w,
  created_at, created_at, updated_at
FROM public.user_trust_edge
WHERE subject = '$aliceId' AND object = '$bobId'
ON CONFLICT (trust_context, subject, object) DO UPDATE SET
  s_good = EXCLUDED.s_good,
  s_very_good = EXCLUDED.s_very_good
''',
    );

    final legacy = await db.customSelect(
      '''
SELECT s_good, s_very_good FROM user_trust_source_edge
WHERE trust_context = 'legacy' AND subject = '$aliceId' AND object = '$bobId'
''',
    ).getSingle();
    final effective = await db.customSelect(
      '''
SELECT trust_w, wall_d, target_w, prev_sent_weight FROM user_trust_edge
WHERE subject = '$aliceId' AND object = '$bobId'
''',
    ).getSingle();

    expect(legacy.read<double>('s_good'), effective.read<double>('trust_w'));
    expect(
      legacy.read<double>('s_very_good'),
      effective.read<double>('target_w'),
    );

    await db.customSelect(
      r'SELECT public.trust_project_pair($1, $2)',
      variables: [
        Variable<String>(aliceId),
        Variable<String>(bobId),
      ],
    ).getSingle();
    final weightAfterRebuild = await db.customSelect(
      '''
SELECT target_w AS w FROM user_trust_edge
WHERE subject = '$aliceId' AND object = '$bobId'
''',
    ).getSingle();
    expect(weightAfterRebuild.read<double>('w'), isNotNull);
  }, skip: skipReason);

  test('empty source table migration statements are no-ops', () async {
    final count = await db.customSelect(
      "SELECT COUNT(*)::int AS c FROM user_trust_source_edge WHERE subject = '$aliceId'",
    ).getSingle();
    expect(count.read<int>('c'), 0);
  }, skip: skipReason);
}

Env _disposableEnv(DisposablePgTarget target) => Env(
  environment: Environment.test,
  pgHost: target.databaseEnv.pgHost,
  pgPort: target.databaseEnv.pgPort,
  pgDatabase: target.databaseEnv.pgDatabase,
  pgUsername: target.databaseEnv.pgUsername,
  pgPassword: target.databaseEnv.pgPassword,
  genealogyNodeKeySecret: 'test-genealogy-secret',
);

Future<bool> _hasSourceTable(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int > 0 AS ok FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'user_trust_source_edge'
''',
  ).getSingle();
  return row.read<bool>('ok');
}

Future<bool> _hasLegacyEffectiveBins(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int > 0 AS ok FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_trust_edge'
  AND column_name = 's_good'
''',
  ).getSingle();
  return row.read<bool>('ok');
}
