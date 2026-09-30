@Tags(['pg', 'mr'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/merit_score_lookup.dart';

import '../../support/disposable_pg_target.dart';

/// Exercises the real evidence ledger → `trust_project_pair` → `mr_put_edge` →
/// `mr_mutual_scores` path (m0202 trust ledger). The publisher is not running,
/// so the test pushes the projected target the way it would.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MERIT_SCORE_LOOKUP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_msl',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late MeritScoreLookup lookup;

  const aliceId = 'Umsalice00001';
  const bobId = 'Umsbob000001';
  const loneId = 'Umslone00001';
  const strangerId = 'Umsstranger01';

  Future<void> applyEvidence(String subject, String object) async {
    await db.customStatement(
      '''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key)
VALUES ('ms-ev-$subject-$object', '$subject', '$object', 2, 2,
        'ms:$subject:$object')
ON CONFLICT (source_key) DO NOTHING
''',
    );
    await db.customStatement(
      "SELECT public.trust_project_pair('$subject', '$object')",
    );
    await db.customStatement(
      '''
SELECT mr_put_edge(subject, object, target_w, ''::text, 0)
FROM public.user_trust_edge
WHERE subject = '$subject' AND object = '$object'
''',
    );
  }

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      db = openDisposablePgDatabase(target);
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
      await tearDownDisposablePgWriter(session: session, drift: db);
    });
  }

  test(
    'reciprocalScoresForViewer returns a real score for a reciprocal '
    'positive trust edge',
    () async {
      await applyEvidence(aliceId, bobId);
      await applyEvidence(bobId, aliceId);

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
      await applyEvidence(aliceId, loneId);

      final scores = await lookup.reciprocalScoresForViewer(
        viewerId: aliceId,
        context: '',
      );

      expect(scores.containsKey(loneId), isFalse);
    },
    skip: skipReason,
  );
}
