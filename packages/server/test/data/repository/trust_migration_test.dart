@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Verifies m0122 legacy source copy preserved pre-migration effective rows.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasSourceTable(probe)) {
        skipReason = 'user_trust_source_edge missing (m0122 not applied)';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;

  const aliceId = 'UtmgAlice001';
  const bobId = 'UtmgBob00001';

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      await db.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('$aliceId', '$aliceId', '${pgTestPublicKey('tmg', 1)}', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('$bobId', '$bobId', '${pgTestPublicKey('tmg', 2)}', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );
    });

    tearDown(() async {
      await db.customStatement('''
DELETE FROM public.user_trust_source_edge
WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId');
DELETE FROM public.user_trust_edge
WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId');
''');
    });

    tearDownAll(() async {
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ('$aliceId', '$bobId')''',
      );
      await db.close();
    });
  }

  test('legacy source row mirrors effective projection after seeding', () async {
    await db.customStatement(
      '''
INSERT INTO public.user_trust_edge (
  subject, object, s_very_bad, s_bad, s_no_effect, s_good, s_very_good,
  anchor_at, prev_sent_weight, created_at, updated_at
) VALUES (
  '$aliceId', '$bobId', 0, 0, 0, 3, 1,
  '2026-01-01T00:00:00Z', 0.5, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (subject, object) DO UPDATE SET
  s_good = EXCLUDED.s_good,
  s_very_good = EXCLUDED.s_very_good
''',
    );

    await db.customStatement(
      '''
INSERT INTO public.user_trust_source_edge
  (trust_context, subject, object, s_very_bad, s_bad, s_no_effect, s_good,
   s_very_good, anchor_at, created_at, updated_at)
SELECT 'legacy', subject, object, s_very_bad, s_bad, s_no_effect, s_good,
       s_very_good, anchor_at, created_at, updated_at
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
SELECT s_good, s_very_good FROM user_trust_edge
WHERE subject = '$aliceId' AND object = '$bobId'
''',
    ).getSingle();

    expect(legacy.read<double>('s_good'), effective.read<double>('s_good'));
    expect(
      legacy.read<double>('s_very_good'),
      effective.read<double>('s_very_good'),
    );

    final weightAfterRebuild = await db.customSelect(
      "SELECT trust_rebuild_effective_edge('$aliceId', '$bobId') AS w",
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

Future<bool> _hasSourceTable(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int > 0 AS ok FROM information_schema.tables
WHERE table_schema = 'public' AND table_name = 'user_trust_source_edge'
''',
  ).getSingle();
  return row.read<bool>('ok');
}
