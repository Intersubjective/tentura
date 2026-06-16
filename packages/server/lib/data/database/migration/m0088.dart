part of '_migrations.dart';

/// Dirichlet-Bayesian user→user trust edges; drop vote_user MeritRank trigger.
final m0088 = Migration('0088', [
  '''
CREATE TABLE IF NOT EXISTS public.user_trust_edge (
  subject text NOT NULL,
  object text NOT NULL,
  c_very_bad double precision NOT NULL DEFAULT 0,
  c_bad double precision NOT NULL DEFAULT 0,
  c_no_effect double precision NOT NULL DEFAULT 0,
  c_good double precision NOT NULL DEFAULT 0,
  c_very_good double precision NOT NULL DEFAULT 0,
  last_decay_at timestamp with time zone NOT NULL DEFAULT now(),
  prev_sent_weight double precision NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_trust_edge_pkey PRIMARY KEY (subject, object),
  CONSTRAINT user_trust_edge_subject_fkey FOREIGN KEY (subject)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT user_trust_edge_object_fkey FOREIGN KEY (object)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',
  '''
DROP TRIGGER IF EXISTS notify_meritrank_vote_user_mutation ON public.vote_user;
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
    SELECT subject AS src, object AS dst, prev_sent_weight AS weight, 0::bigint AS magnitude, ''::text AS context FROM user_trust_edge
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
