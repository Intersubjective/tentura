part of '_migrations.dart';

/// Poll feature migrated from beacon to beacon room.
/// - Adds `linked_polling_id` to `beacon_room_message`.
/// - Drops `polling_id` from `beacon` (polls are no longer tied to beacons).
/// - Drops meritrank `polling_results` function (replaced by SQL COUNT).
/// - Drops `neighbors_score` view (only existed to back `polling_results`).
/// - Updates `meritrank_init` to remove stale polling edges.
final m0053 = Migration('0053', [
  '''
ALTER TABLE public.beacon_room_message
  ADD COLUMN IF NOT EXISTS linked_polling_id text NULL
  CONSTRAINT beacon_room_message__linked_polling_id__fkey
  REFERENCES public.polling(id) ON UPDATE RESTRICT ON DELETE CASCADE;
''',
  '''
ALTER TABLE public.beacon DROP COLUMN IF EXISTS polling_id;
''',
  '''
DROP FUNCTION IF EXISTS public.polling_results(text, json);
''',
  '''
DROP VIEW IF EXISTS public.neighbors_score;
''',
  r'''
CREATE OR REPLACE FUNCTION public.meritrank_init()
  RETURNS integer
  LANGUAGE plpgsql
  STABLE
  AS $$
DECLARE
  _src text[];
  _dst text[];
  _weight float8[];
  _magnitude bigint[];
  _context text[];
  _total integer := 0;
  _edge_count integer;
BEGIN
  WITH all_edges AS (
    -- Edges User -> User (vote)
    SELECT subject AS src, object AS dst, amount::float8 AS weight, ticker::bigint AS magnitude, ''::text AS context
    FROM vote_user
    UNION ALL
    -- Edges Beacon -> Author
    SELECT id, user_id, 1.0::float8, 0::bigint, coalesce(context, ''::text) FROM "beacon"
    UNION ALL
    -- Edges Author -> Beacon
    SELECT user_id, id, 1.0::float8, ticker::bigint, coalesce(context, ''::text) FROM "beacon"
    UNION ALL
    -- Edges User -> Beacon (vote)
    SELECT vb.subject, vb.object, vb.amount::float8, vb.ticker::bigint, coalesce(b.context, ''::text)
    FROM vote_beacon vb JOIN "beacon" b ON b.id = vb.object
    UNION ALL
    -- Edges Comment -> Author
    SELECT c.id, c.user_id, 1.0::float8, 0::bigint, coalesce(b.context, ''::text)
    FROM "comment" c JOIN "beacon" b ON c.beacon_id = b.id
    UNION ALL
    -- Edges Author -> Comment
    SELECT c.user_id, c.id, 1.0::float8, c.ticker::bigint, coalesce(b.context, ''::text)
    FROM "comment" c JOIN "beacon" b ON c.beacon_id = b.id
    UNION ALL
    -- Edges User -> Comment (vote)
    SELECT vc.subject, vc.object, vc.amount::float8, vc.ticker::bigint, coalesce(b.context, ''::text)
    FROM vote_comment vc
    JOIN "comment" c ON c.id = vc.object
    JOIN "beacon" b ON b.id = c.beacon_id
    UNION ALL
    -- Edges Author -> Opinion
    SELECT subject, id, (abs(amount))::float8, ticker::bigint, ''::text FROM "opinion"
    UNION ALL
    -- Edges Opinion -> Author
    SELECT id, subject, 1.0::float8, ticker::bigint, ''::text FROM "opinion"
    UNION ALL
    -- Edges Opinion -> User
    SELECT id, object, (sign(amount))::float8, ticker::bigint, ''::text FROM "opinion"
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

  -- Read Updates Filters
  SELECT _total + count(*)::int INTO _total
  FROM (SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates) AS _;

  RETURN _total;
END;
$$;
''',
]);
