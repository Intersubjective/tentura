part of '_migrations.dart';

/// No trust edge from a user to themselves.
///
/// Before the own-invite fix (660a077df), accepting your own invite from the
/// in-app code entry wrote a `vote_user` row with `subject = object`.
/// `trust_fold_pair` folds that into a 0.5 vouch, `trust_project_pair` turns
/// it into a self `user_trust_edge`, and MeritRank refuses the whole bulk load
/// at start ("Self-reference is not allowed"). Its graph then stays empty, and
/// visibility falls back to mutual explicit trust only. On dev one QA account
/// did this, and every Field lost its MeritRank-based people and trust chains.
///
/// This drops every self row from the trust tables, forbids new ones with
/// CHECK constraints (`trust_evidence` has had one since m0202), and keeps
/// `meritrank_init` from ever sending one.
final m0267 = Migration('0267', [
  // Every table lock the ALTERs below need, up front and in one order: a
  // live trust write holding vote_user while it waits on the visibility
  // generation row (which the edge DELETE takes) cannot deadlock with us.
  '''
LOCK TABLE public.vote_user, public.user_trust_edge, public.trust_publish_queue
  IN ACCESS EXCLUSIVE MODE
''',
  'DELETE FROM public.trust_publish_queue WHERE subject_user_id = object_user_id',
  'DELETE FROM public.user_trust_edge WHERE subject = object',
  'DELETE FROM public.vote_user WHERE subject = object',
  // Deleting a vote can re-project the pair; drop anything that brought back.
  'DELETE FROM public.user_trust_edge WHERE subject = object',
  'DELETE FROM public.trust_publish_queue WHERE subject_user_id = object_user_id',
  '''
ALTER TABLE public.vote_user ADD CONSTRAINT vote_user_not_self_ck
  CHECK (subject <> object)
''',
  '''
ALTER TABLE public.user_trust_edge ADD CONSTRAINT user_trust_edge_not_self_ck
  CHECK (subject <> object)
''',
  '''
ALTER TABLE public.trust_publish_queue ADD CONSTRAINT trust_publish_queue_not_self_ck
  CHECK (subject_user_id <> object_user_id)
''',
  r'''
CREATE OR REPLACE FUNCTION public.meritrank_init() RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  _meritrank_new_edges_enabled constant boolean := false;
  _src text[];
  _dst text[];
  _weight float8[];
  _magnitude bigint[];
  _context text[];
  _total integer := 0;
  _edge_count integer;
BEGIN
  WITH all_edges AS (
    SELECT subject AS src, object AS dst, target_w AS weight, 0::bigint AS magnitude, ''::text AS context FROM user_trust_edge WHERE target_w <> 0 AND subject <> object
    UNION ALL
    SELECT pv.id, p.id, 1.0::float8, 0::bigint, ''::text FROM polling p JOIN polling_variant pv ON p.id = pv.polling_id WHERE p.enabled = true
    UNION ALL
    SELECT pa.author_id, pa.polling_variant_id, 1.0::float8, 0::bigint, ''::text FROM polling_act pa JOIN polling p ON p.id = pa.polling_id WHERE p.enabled = true
  ),
  agg AS (
    SELECT
      coalesce(array_agg(src), ARRAY[]::text[]) AS src_arr,
      coalesce(array_agg(dst), ARRAY[]::text[]) AS dst_arr,
      coalesce(array_agg(weight), ARRAY[]::float8[]) AS weight_arr,
      coalesce(array_agg(magnitude), ARRAY[]::bigint[]) AS magnitude_arr,
      coalesce(array_agg(context), ARRAY[]::text[]) AS context_arr,
      count(*)::int AS cnt
    FROM all_edges
  )
  SELECT src_arr, dst_arr, weight_arr, magnitude_arr, context_arr, cnt
  INTO _src, _dst, _weight, _magnitude, _context, _edge_count
  FROM agg;

  _total := _total + _edge_count;
  PERFORM mr_bulk_load_edges(_src, _dst, _weight, _magnitude, _context, 120000::bigint);

  IF _meritrank_new_edges_enabled THEN
    SELECT _total + count(*)::int INTO _total FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;
  END IF;

  RETURN _total;
END;
$$
''',
]);
