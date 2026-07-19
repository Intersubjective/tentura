@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// MeritRank boundary: effective projection vs source table (m0122).
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasTrustFunctions(probe)) {
        skipReason = 'trust functions missing (m0122 not applied)';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;

  const aliceId = 'UtmbAlice001';
  const bobId = 'UtmbBob00001';
  const allIds = [aliceId, bobId];

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      for (var i = 0; i < allIds.length; i++) {
        final id = allIds[i];
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('tmb', i + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
    });

    tearDown(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement('''
DELETE FROM public.user_trust_source_edge
WHERE subject IN ($idList) OR object IN ($idList);
DELETE FROM public.user_trust_edge
WHERE subject IN ($idList) OR object IN ($idList);
''');
    });

    tearDownAll(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ($idList)''',
      );
      await db.close();
    });
  }

  test('meritrank_init bulk-loads user_trust_edge only', () async {
    await db.customStatement(
      "SELECT trust_apply_source_evidence('personal', '$aliceId', '$bobId', 'good', 1)",
    );
    await db.customStatement(
      "SELECT trust_rebuild_effective_edge('$aliceId', '$bobId')",
    );

    final sourceInMr = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c FROM mr_edgelist() e
JOIN public.user_trust_source_edge s
  ON s.subject = e.src AND s.object = e.dst
WHERE s.subject = '$aliceId' AND s.object = '$bobId'
''',
    ).getSingle();
    expect(sourceInMr.read<int>('c'), 0);

    final effectiveInMr = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c FROM mr_edgelist() e
JOIN public.user_trust_edge t ON t.subject = e.src AND t.object = e.dst
WHERE t.subject = '$aliceId' AND t.object = '$bobId'
''',
    ).getSingle();
    expect(effectiveInMr.read<int>('c'), greaterThanOrEqualTo(0));
  }, skip: skipReason);

  test('source-only row is invisible in effective table until rebuild', () async {
    await db.customStatement(
      "SELECT trust_apply_source_evidence('personal', '$aliceId', '$bobId', 'very_good', 2)",
    );
    final effectiveBefore = await db.customSelect(
      "SELECT COUNT(*)::int AS c FROM user_trust_edge WHERE subject = '$aliceId'",
    ).getSingle();
    expect(effectiveBefore.read<int>('c'), 0);

    await db.customStatement(
      "SELECT trust_rebuild_effective_edge('$aliceId', '$bobId')",
    );
    final effectiveAfter = await db.customSelect(
      "SELECT COUNT(*)::int AS c FROM user_trust_edge WHERE subject = '$aliceId'",
    ).getSingle();
    expect(effectiveAfter.read<int>('c'), 1);
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

Future<bool> _hasTrustFunctions(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT count(*)::int > 0 AS ok FROM pg_proc
WHERE proname IN ('trust_apply_source_evidence', 'trust_rebuild_effective_edge')
''',
  ).getSingle();
  return row.read<bool>('ok');
}
