part of '_migrations.dart';

/// Drops `public.opinion` and MeritRank hooks; updates `meritrank_init()` bulk-load
/// to exclude opinion edges.
final m0062 = Migration('0062', [
  '''
DROP TRIGGER IF EXISTS notify_meritrank_opinion_mutation ON public.opinion;
''',
  '''
DROP TRIGGER IF EXISTS public_opinion_before_insert ON public.opinion;
''',
  '''
DROP FUNCTION IF EXISTS public.notify_meritrank_opinion_mutation();
''',
  '''
DROP FUNCTION IF EXISTS public.opinion_before_insert();
''',
  '''
DROP FUNCTION IF EXISTS public.opinion_get_scores(public.opinion, json);
''',
  '''
DROP FUNCTION IF EXISTS public.opinions(text, integer, integer, json);
''',
  '''
DROP TABLE IF EXISTS public.opinion CASCADE;
''',
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
