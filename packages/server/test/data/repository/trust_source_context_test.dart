@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

/// Postgres integration for typed trust source contexts and rebuild (m0122).
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasTrustFunctions(probe)) {
        skipReason = 'trust_apply_source_evidence missing (m0122 not applied)';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;

  const aliceId = 'UtscAlice001';
  const bobId = 'UtscBob00001';
  const allIds = [aliceId, bobId];

  Future<void> user(String id) => db.customStatement(
    '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('tsc', allIds.indexOf(id) + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );

  Future<void> applySource(
    String context,
    String subject,
    String object,
    String bin,
    double count,
  ) => db.customStatement(
    "SELECT trust_apply_source_evidence('$context', '$subject', '$object', '$bin', $count)",
  );

  Future<double> rebuild(String subject, String object) async {
    final row = await db.customSelect(
      "SELECT trust_rebuild_effective_edge('$subject', '$object') AS w",
    ).getSingle();
    return row.read<double>('w');
  }

  Future<Map<String, double>> effectiveBins(String subject, String object) async {
    final row = await db.customSelect(
      '''
SELECT s_very_bad, s_bad, s_no_effect, s_good, s_very_good
FROM public.user_trust_edge
WHERE subject = '$subject' AND object = '$object'
''',
    ).getSingleOrNull();
    if (row == null) {
      return {};
    }
    return {
      'very_bad': row.read<double>('s_very_bad'),
      'bad': row.read<double>('s_bad'),
      'no_effect': row.read<double>('s_no_effect'),
      'good': row.read<double>('s_good'),
      'very_good': row.read<double>('s_very_good'),
    };
  }

  Future<int> sourceRowCount(String subject, String object) async {
    final row = await db.customSelect(
      '''
SELECT COUNT(*)::int AS c FROM public.user_trust_source_edge
WHERE subject = '$subject' AND object = '$object'
''',
    ).getSingle();
    return row.read<int>('c');
  }

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      for (final id in allIds) {
        await user(id);
      }
    });

    tearDown(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement('''
DELETE FROM public.trust_evidence_event
WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList);
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

  test('personal and forward contexts are isolated in source rows', () async {
    await applySource('personal', aliceId, bobId, 'good', 1);
    await applySource('forward', aliceId, bobId, 'very_good', 1);
    expect(await sourceRowCount(aliceId, bobId), 2);
  }, skip: skipReason);

  test('unknown context apply raises', () async {
    expect(
      () => applySource('bogus', aliceId, bobId, 'good', 1),
      throwsA(isA<Object>()),
    );
  }, skip: skipReason);

  test('legacy context apply raises', () async {
    expect(
      () => applySource('legacy', aliceId, bobId, 'good', 1),
      throwsA(isA<Object>()),
    );
  }, skip: skipReason);

  test('invalid count raises', () async {
    expect(
      () => applySource('personal', aliceId, bobId, 'good', -1),
      throwsA(isA<Object>()),
    );
  }, skip: skipReason);

  test('source writes leave effective edge untouched until rebuild', () async {
    await applySource('personal', aliceId, bobId, 'good', 1);
    final before = await db.customSelect(
      "SELECT COUNT(*)::int AS c FROM user_trust_edge WHERE subject = '$aliceId'",
    ).getSingle();
    expect(before.read<int>('c'), 0);

    await rebuild(aliceId, bobId);
    final after = await effectiveBins(aliceId, bobId);
    expect(after['good'], closeTo(1, 1e-9));
  }, skip: skipReason);

  test('forward multiplier scales effective bins', () async {
    await applySource('forward', aliceId, bobId, 'good', 1);
    await rebuild(aliceId, bobId);
    final bins = await effectiveBins(aliceId, bobId);
    // forward evidence_multiplier is 0.20 in m0122 seed data.
    expect(bins['good'], closeTo(0.2, 1e-9));
  }, skip: skipReason);

  test('repeated rebuild is deterministic', () async {
    await applySource('personal', aliceId, bobId, 'very_good', 2);
    final w1 = await rebuild(aliceId, bobId);
    final w2 = await rebuild(aliceId, bobId);
    expect(w1, closeTo(w2, 1e-12));
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
WHERE proname = 'trust_apply_source_evidence'
''',
  ).getSingle();
  return row.read<bool>('ok');
}
