part of '_migrations.dart';

/// After m0037 dropped `comment` / `vote_comment`, the `meritrank_init`
/// function still referenced them. Backfill those edges from `beacon_room_message`
/// instead (same id/author graph shape as legacy comments; no vote_comment analogue).
final m0044 = Migration('0044', [
  r'''
CREATE OR REPLACE FUNCTION public.meritrank_init()
  RETURNS integer
    LANGUAGE plpgsql
    STABLE
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
    SELECT subject AS src, object AS dst, amount::float8 AS weight, ticker::bigint AS magnitude, ''::text AS context FROM vote_user
    UNION ALL
    SELECT id, user_id, 1.0::float8, 0::bigint, coalesce(context, ''::text) FROM "beacon"
    UNION ALL
    SELECT user_id, id, 1.0::float8, ticker::bigint, coalesce(context, ''::text) FROM "beacon"
    UNION ALL
    SELECT vb.subject, vb.object, vb.amount::float8, vb.ticker::bigint, coalesce(b.context, ''::text) FROM vote_beacon vb JOIN "beacon" b ON b.id = vb.object
    UNION ALL
    SELECT m.id, m.author_id, 1.0::float8, 0::bigint, coalesce(b.context, ''::text) FROM public.beacon_room_message m JOIN "beacon" b ON m.beacon_id = b.id
    UNION ALL
    SELECT m.author_id, m.id, 1.0::float8, 0::bigint, coalesce(b.context, ''::text) FROM public.beacon_room_message m JOIN "beacon" b ON m.beacon_id = b.id
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

  IF _meritrank_new_edges_enabled THEN
    SELECT _total + count(*)::int INTO _total FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;
  END IF;

  RETURN _total;
END;
$$;
''',
]);
