part of '_migrations.dart';

// Meritrank API 0.5.1+ adaptation: disable new-edges/filter stack behind flag (unimplemented/WIP).
// No calls to mr_set_new_edges_filter / mr_get_new_edges_filter / mr_fetch_new_edges when flag is off.
final m0013 = Migration('0013', [
  // meritrank_init: gate "Read Updates Filters" block on _meritrank_new_edges_enabled (default false).
  r'''
CREATE OR REPLACE FUNCTION public.meritrank_init()
  RETURNS integer
  LANGUAGE plpgsql
  STABLE
  AS $$
DECLARE
  -- Unimplemented/WIP: new-edges filter feature disabled; Meritrank service no longer supports
  -- mr_set_new_edges_filter / mr_fetch_new_edges / mr_get_new_edges_filter. Set to true when reimplemented.
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
    SELECT subject AS src, object AS dst, amount::float8 AS weight, ticker::bigint AS magnitude, ''::text AS context FROM vote_user
    UNION ALL
    SELECT id, user_id, 1.0::float8, 0::bigint, coalesce(context, ''::text) FROM "beacon"
    UNION ALL
    SELECT user_id, id, 1.0::float8, ticker::bigint, coalesce(context, ''::text) FROM "beacon"
    UNION ALL
    SELECT vb.subject, vb.object, vb.amount::float8, vb.ticker::bigint, coalesce(b.context, ''::text) FROM vote_beacon vb JOIN "beacon" b ON b.id = vb.object
    UNION ALL
    SELECT c.id, c.user_id, 1.0::float8, 0::bigint, coalesce(b.context, ''::text) FROM "comment" c JOIN "beacon" b ON c.beacon_id = b.id
    UNION ALL
    SELECT c.user_id, c.id, 1.0::float8, c.ticker::bigint, coalesce(b.context, ''::text) FROM "comment" c JOIN "beacon" b ON c.beacon_id = b.id
    UNION ALL
    SELECT vc.subject, vc.object, vc.amount::float8, vc.ticker::bigint, coalesce(b.context, ''::text) FROM vote_comment vc JOIN "comment" c ON c.id = vc.object JOIN "beacon" b ON b.id = c.beacon_id
    UNION ALL
    SELECT subject, id, (abs(amount))::float8, ticker::bigint, ''::text FROM "opinion"
    UNION ALL
    SELECT id, subject, 1.0::float8, ticker::bigint, ''::text FROM "opinion"
    UNION ALL
    SELECT id, object, (sign(amount))::float8, ticker::bigint, ''::text FROM "opinion"
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

  -- Unimplemented/WIP: new-edges filter; no calls when flag off.
  IF _meritrank_new_edges_enabled THEN
    SELECT _total + count(*)::int INTO _total FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;
  END IF;

  RETURN _total;
END;
$$;
''',
  //
  // public.updates: return empty set when flag off; no calls to mr_fetch_new_edges / mr_get_new_edges_filter.
  r'''
CREATE OR REPLACE FUNCTION public.updates(prefix text, hasura_session json)
  RETURNS SETOF public.mutual_score
  LANGUAGE plpgsql
  AS $$
DECLARE
  -- Unimplemented/WIP: new-edges filter feature disabled; returns empty set when flag off.
  _meritrank_new_edges_enabled constant boolean := false;
BEGIN
  IF NOT _meritrank_new_edges_enabled THEN
    RETURN QUERY SELECT NULL::text AS src, NULL::text AS dst, NULL::double precision AS src_score, NULL::double precision AS dst_score WHERE false;
    RETURN;
  END IF;

  RETURN QUERY
  WITH new_edges AS (
    SELECT
      src,
      dst,
      score_cluster_of_src AS src_score,
      score_cluster_of_dst AS dst_score
    FROM
      mr_fetch_new_edges(hasura_session ->> 'x-hasura-user-id', prefix)
  ),
  new_filter AS (
    INSERT INTO
      user_updates
    VALUES(
        hasura_session ->> 'x-hasura-user-id',
        mr_get_new_edges_filter(hasura_session ->> 'x-hasura-user-id')
      )
    ON CONFLICT DO NOTHING
  )
  SELECT new_edges.src, new_edges.dst, new_edges.src_score, new_edges.dst_score FROM new_edges;
END;
$$;
''',
]);
