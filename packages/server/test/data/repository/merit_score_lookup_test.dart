@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/merit_score_lookup.dart';
import 'package:tentura_server/env.dart';

/// Exercises the real `trust_apply_evidence` → `mr_put_edge` → `mr_mutual_scores`
/// path (migration m0088; see `docs/features/trust_edges.md`), since nothing
/// else in the suite ever seeds a live MeritRank score end-to-end. The older
/// `vote_user` trigger this used to run through was dropped by m0088 — evidence
/// now flows through `user_trust_edge` instead.
Future<void> main() async {
  final postgresReachable = await _canConnectPostgres();
  var skipReason = postgresReachable ? false : 'local Postgres not reachable';

  if (postgresReachable) {
    final probe = TenturaDb(_testEnv());
    try {
      if (!await _hasMeritRank(probe)) {
        skipReason = 'mr_mutual_scores / trust_apply_evidence function missing';
      }
    } finally {
      await probe.close();
    }
  }

  late TenturaDb db;
  late MeritScoreLookup lookup;

  const aliceId = 'Umsalice00001';
  const bobId = 'Umsbob000001';
  const loneId = 'Umslone00001';
  const strangerId = 'Umsstranger01';
  const allIds = [aliceId, bobId, loneId, strangerId];

  // Matches TRUST_EDGE_HALF_LIFE_DAYS / TRUST_EDGE_EPSILON server defaults.
  const halfLifeSeconds = 15724800.0;
  const epsilon = 0.1;

  Future<void> applyEvidence(String subject, String object, String bin) =>
      db.customStatement(
        '''
SELECT trust_apply_evidence('$subject', '$object', '$bin', 1, $halfLifeSeconds, $epsilon)
''',
      );

  if (skipReason == false) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      lookup = MeritScoreLookup(db);

      // Derived from the user id (not a fixed letter-run) so it can't collide
      // with the placeholder public keys other pg-tagged test files insert
      // concurrently against the same live Postgres instance.
      Future<void> user(String id) => db.customStatement(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );

      await user(aliceId);
      await user(bobId);
      await user(loneId);
      await user(strangerId);
    });

    tearDownAll(() async {
      final idList = allIds.map((id) => "'$id'").join(', ');
      await db.customStatement('''
DELETE FROM public.user_trust_edge WHERE subject IN ($idList)
  OR object IN ($idList)
''');
      await db.customStatement(
        '''DELETE FROM public."user" WHERE id IN ($idList)''',
      );
      await db.close();
    });
  }

  test(
    'reciprocalScoresForViewer returns a real score for a reciprocal '
    'positive trust edge',
    () async {
      await applyEvidence(aliceId, bobId, 'very_good');
      await applyEvidence(bobId, aliceId, 'very_good');

      final scores = await lookup.reciprocalScoresForViewer(
        viewerId: aliceId,
        context: '',
      );

      expect(scores.containsKey(bobId), isTrue);
      expect(scores[bobId]!.dstScore, greaterThan(0));
      expect(scores[bobId]!.srcScore, greaterThan(0));
      expect(scores.containsKey(strangerId), isFalse);
    },
    skip: skipReason,
  );

  test(
    'reciprocalScoresForViewer omits a one-directional (non-mutual) trust edge',
    () async {
      await applyEvidence(aliceId, loneId, 'very_good');

      final scores = await lookup.reciprocalScoresForViewer(
        viewerId: aliceId,
        context: '',
      );

      expect(scores.containsKey(loneId), isFalse);
    },
    skip: skipReason,
  );
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

Future<bool> _hasMeritRank(TenturaDb db) async {
  final row = await db.customSelect(
    '''
SELECT
  (SELECT count(*) FROM pg_proc WHERE proname = 'mr_mutual_scores') > 0
  AND (SELECT count(*) FROM pg_proc WHERE proname = 'trust_apply_evidence') > 0
  AS ok
''',
  ).getSingle();
  return row.read<bool>('ok');
}
