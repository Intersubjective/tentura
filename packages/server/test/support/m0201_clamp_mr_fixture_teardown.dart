import 'package:tentura_server/data/database/tentura_db.dart';

import 'm0201_clamp_mr_harness.dart';

/// Reference teardown copied from [m0201_clamp_pg_test] `_cleanup` (post-m0202).
Future<void> m0201ClampPgReferenceCleanup(TenturaDb db) async {
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
    'DELETE FROM public.user_block '
    'WHERE blocker_id IN ($idList) OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    '''DELETE FROM public."user" WHERE id IN ($idList)''',
  );
}

/// Seeds the same post-m0202 rows pg/mr clamp tests rely on between cases.
Future<void> m0201ClampMrSeedFullPairFixture(TenturaDb db) async {
  for (final id in m0201ClampMrAllIds) {
    await m0201ClampMrInsertUser(db, id);
  }
  await m0201ClampMrSeedDefaultPair(db);
  await db.customStatement(
    "SELECT public.trust_project_pair("
    "'${m0201ClampMrAliceId}', '${m0201ClampMrBobId}')",
  );
  await db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('${m0201ClampMrAliceId}', '${m0201ClampMrBobId}', '${m0201ClampMrAliceId}')
ON CONFLICT DO NOTHING
''');
}

/// Row counts for every table pg clamp `_cleanup` clears for the MR pair ids.
Future<Map<String, int>> m0201ClampMrFixtureTableCounts(TenturaDb db) async {
  final idList = m0201ClampMrAllIds.map((id) => "'$id'").join(', ');
  Future<int> count(String sql) async {
    final row = await db.customSelect(sql).getSingle();
    return row.read<int>('c');
  }

  return {
    'trust_evidence': await count(
      'SELECT count(*)::int AS c FROM public.trust_evidence '
      'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
    ),
    'user_trust_edge': await count(
      'SELECT count(*)::int AS c FROM public.user_trust_edge '
      'WHERE subject IN ($idList) OR object IN ($idList)',
    ),
    'trust_publish_queue': await count(
      'SELECT count(*)::int AS c FROM public.trust_publish_queue '
      'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
    ),
    'user_block': await count(
      'SELECT count(*)::int AS c FROM public.user_block '
      'WHERE blocker_id IN ($idList) OR blocked_id IN ($idList)',
    ),
    'user': await count(
      'SELECT count(*)::int AS c FROM public."user" WHERE id IN ($idList)',
    ),
  };
}
