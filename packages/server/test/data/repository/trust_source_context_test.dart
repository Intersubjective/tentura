@Tags(['pg'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
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
  ) async {
    await db
        .customSelect(
          r'SELECT trust_apply_source_evidence($1, $2, $3, $4, $5)',
          variables: [
            Variable<String>(context),
            Variable<String>(subject),
            Variable<String>(object),
            Variable<String>(bin),
            Variable<double>(count),
          ],
        )
        .getSingle();
  }

  Future<double> rebuild(String subject, String object) async {
    final row = await db
        .customSelect(
          r'SELECT trust_rebuild_effective_edge($1, $2) AS w',
          variables: [
            Variable<String>(subject),
            Variable<String>(object),
          ],
        )
        .getSingle();
    return row.read<double>('w');
  }

  Future<Map<String, double>> sourceBins(
    String context,
    String subject,
    String object,
  ) async {
    final row = await db
        .customSelect(
          r'''
SELECT s_very_bad, s_bad, s_no_effect, s_good, s_very_good
FROM public.user_trust_source_edge
WHERE trust_context = $1 AND subject = $2 AND object = $3
''',
          variables: [
            Variable<String>(context),
            Variable<String>(subject),
            Variable<String>(object),
          ],
        )
        .getSingleOrNull();
    if (row == null) return {};
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

  Future<void> cleanPair() async {
    final idList = allIds.map((id) => "'$id'").join(', ');
    await db.customStatement(
      'DELETE FROM public.trust_evidence_event '
      'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_trust_source_edge '
      'WHERE subject IN ($idList) OR object IN ($idList)',
    );
    await db.customStatement(
      'DELETE FROM public.user_trust_edge '
      'WHERE subject IN ($idList) OR object IN ($idList)',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      for (final id in allIds) {
        await user(id);
      }
    });

    tearDown(cleanPair);

    tearDownAll(() async {
      await cleanPair();
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
    await expectLater(
      applySource('bogus', aliceId, bobId, 'good', 1),
      throwsA(isA<Object>()),
    );
  }, skip: skipReason);

  test('legacy context apply raises', () async {
    await expectLater(
      applySource('legacy', aliceId, bobId, 'good', 1),
      throwsA(isA<Object>()),
    );
  }, skip: skipReason);

  test('invalid count raises', () async {
    await expectLater(
      applySource('personal', aliceId, bobId, 'good', -1),
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
    final after = await db.customSelect(
      "SELECT s_good FROM user_trust_edge WHERE subject = '$aliceId' AND object = '$bobId'",
    ).getSingle();
    expect(after.read<double>('s_good'), greaterThan(0));
  }, skip: skipReason);

  test('forward multiplier scales effective bins', () async {
    await applySource('forward', aliceId, bobId, 'good', 1);
    await rebuild(aliceId, bobId);
    final bins = await db.customSelect(
      "SELECT s_good FROM user_trust_edge WHERE subject = '$aliceId' AND object = '$bobId'",
    ).getSingle();
    expect(bins.read<double>('s_good'), closeTo(0.2, 1e-6));
  }, skip: skipReason);

  test('repeated rebuild is deterministic', () async {
    await applySource('personal', aliceId, bobId, 'very_good', 2);
    final w1 = await rebuild(aliceId, bobId);
    final w2 = await rebuild(aliceId, bobId);
    expect(w1, closeTo(w2, 1e-7));
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
