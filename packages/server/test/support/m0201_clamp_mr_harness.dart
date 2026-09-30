import 'package:tentura_server/data/database/tentura_db.dart';

/// Pair ids shared by m0201 clamp pg/mr fixtures.
const m0201ClampMrAliceId = 'Um0201alice01';
const m0201ClampMrBobId = 'Um0201bob0001';
const m0201ClampMrAllIds = [m0201ClampMrAliceId, m0201ClampMrBobId];

/// Same entry path as [m0201_clamp_mr_test] setUp / tearDown.
Future<void> m0201ClampMrPrepareEmptyPairFixture(TenturaDb db) async {
  await m0201ClampMrCleanup(db);
  for (final id in m0201ClampMrAllIds) {
    await m0201ClampMrInsertUser(db, id);
  }
}

/// Post-m0202 pair seed (replaces pre-m0202 `trust_apply_source_evidence`, which
/// wrote `trust_evidence_event` / `user_trust_source_edge`).
Future<void> m0201ClampMrSeedDefaultPair(TenturaDb db) async {
  await db.customStatement('''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key)
VALUES (
  'm0201-mr-harness-seed',
  '$m0201ClampMrAliceId',
  '$m0201ClampMrBobId',
  2,
  2,
  'm0201-mr:harness:seed'
)
ON CONFLICT (source_key) DO NOTHING
''');
}

Future<void> m0201ClampMrCleanup(TenturaDb db) async {
  final idList = m0201ClampMrAllIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.trust_evidence '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
    'OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    '''DELETE FROM public."user" WHERE id IN ($idList)''',
  );
}

Future<void> m0201ClampMrInsertUser(TenturaDb db, String id) =>
    db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
