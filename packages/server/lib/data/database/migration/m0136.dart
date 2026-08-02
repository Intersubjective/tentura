part of '_migrations.dart';

/// User blocking enforcement: beacon visibility wall and signup inheritance.
/// See docs/plans/user-block-implementation-spec.md §3.1 and §4.
final m0136 = Migration('0136', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_can_read_content(
  p_beacon_id text,
  p_viewer_id text
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
SELECT COALESCE((
  SELECT CASE
    WHEN public.block_hides(b.user_id, p_viewer_id) THEN false
    WHEN b.status = 3 THEN b.user_id = p_viewer_id
    WHEN b.status = 2 THEN false
    WHEN b.user_id = p_viewer_id THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = p_beacon_id
        AND fe.recipient_id = p_viewer_id
        AND fe.cancelled_at IS NULL
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_participant bp
      WHERE bp.beacon_id = p_beacon_id
        AND bp.user_id = p_viewer_id
        AND (bp.role = 1 OR bp.room_access = 3)
    ) THEN true
    WHEN EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = p_beacon_id
        AND ho.user_id = p_viewer_id
        AND ho.status = 0
    ) THEN true
    ELSE false
  END
  FROM public.beacon b
  WHERE b.id = p_beacon_id
), false);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.user_block_inherit_on_invite()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.descendant_user_id IS NULL OR NEW.ancestor_user_id IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
  SELECT ub.blocker_id, NEW.descendant_user_id, ub.origin_id
  FROM public.user_block ub
  WHERE ub.blocked_id = NEW.ancestor_user_id
    AND ub.blocker_id <> NEW.descendant_user_id
    AND EXISTS (
      SELECT 1 FROM public.user_block_intent i
      WHERE i.blocker_id = ub.blocker_id
        AND i.blocked_id = ub.origin_id
        AND i.cascade_mode > 0)
  ON CONFLICT DO NOTHING;
  RETURN NULL;
END; $$;
''',
  '''
CREATE OR REPLACE TRIGGER user_block_inherit_trg
  AFTER INSERT ON public.invite_genealogy
  FOR EACH ROW EXECUTE FUNCTION public.user_block_inherit_on_invite();
''',
  r'''
CREATE OR REPLACE FUNCTION public.graph(
  focus text,
  context text,
  positive_only boolean,
  hasura_session json
) RETURNS SETOF public.graph_score
  LANGUAGE sql
  STABLE
  AS $$
SELECT
  g.src,
  g.dst,
  g.score_cluster_of_ego AS src_score,
  g.score_cluster_of_dst AS dst_score,
  public.user_trust_edge_degree(g.src, positive_only) AS src_total_neighbor_count,
  public.user_trust_edge_degree(g.dst, positive_only) AS dst_total_neighbor_count
FROM
  mr_graph(
    hasura_session ->> 'x-hasura-user-id',
    focus,
    context,
    positive_only,
    0,
    100
  ) AS g
WHERE NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', g.src)
  AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', g.dst);
$$;
''',
  'DROP FUNCTION IF EXISTS public.graph_edges_between(text[], boolean);',
  r'''
CREATE OR REPLACE FUNCTION public.graph_edges_between(
  node_ids text[],
  positive_only boolean,
  hasura_session json
) RETURNS SETOF public.graph_score
  LANGUAGE sql
  STABLE
  AS $$
SELECT
  e.subject AS src,
  e.object AS dst,
  (0)::double precision AS src_score,
  e.prev_sent_weight AS dst_score,
  public.user_trust_edge_degree(e.subject, positive_only) AS src_total_neighbor_count,
  public.user_trust_edge_degree(e.object, positive_only) AS dst_total_neighbor_count
FROM public.user_trust_edge e
WHERE e.subject = ANY(node_ids)
  AND e.object = ANY(node_ids)
  AND (positive_only = false OR e.prev_sent_weight > 0)
  AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', e.subject)
  AND NOT public.block_hides(hasura_session ->> 'x-hasura-user-id', e.object);
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.mutual_friends(
  alice_id text,
  bob_id text,
  ctx text
) RETURNS SETOF public."user"
  LANGUAGE sql
  STABLE
  AS $$
WITH c AS (
  SELECT coalesce(ctx, '') AS v
),
alice_peers AS (
  SELECT
    CASE WHEN ms.src = alice_id THEN ms.dst ELSE ms.src END AS peer_id,
    CASE WHEN ms.src = alice_id THEN ms.score_value_of_dst
         ELSE ms.score_value_of_src END::double precision AS fwd_alice,
    CASE WHEN ms.src = alice_id THEN ms.score_value_of_src
         ELSE ms.score_value_of_dst END::double precision AS rev_alice
  FROM mr_mutual_scores(alice_id, (SELECT v FROM c)) ms
  WHERE (ms.src = alice_id OR ms.dst = alice_id)
    AND ms.score_value_of_src > 0::double precision
    AND ms.score_value_of_dst > 0::double precision
    AND CASE WHEN ms.src = alice_id THEN ms.dst ELSE ms.src END LIKE 'U%'
    AND CASE WHEN ms.src = alice_id THEN ms.dst ELSE ms.src END <> alice_id
    AND CASE WHEN ms.src = alice_id THEN ms.dst ELSE ms.src END <> bob_id
),
bob_peers AS (
  SELECT
    CASE WHEN ms.src = bob_id THEN ms.dst ELSE ms.src END AS peer_id,
    CASE WHEN ms.src = bob_id THEN ms.score_value_of_dst
         ELSE ms.score_value_of_src END::double precision AS fwd_bob,
    CASE WHEN ms.src = bob_id THEN ms.score_value_of_src
         ELSE ms.score_value_of_dst END::double precision AS rev_bob
  FROM mr_mutual_scores(bob_id, (SELECT v FROM c)) ms
  WHERE (ms.src = bob_id OR ms.dst = bob_id)
    AND ms.score_value_of_src > 0::double precision
    AND ms.score_value_of_dst > 0::double precision
    AND CASE WHEN ms.src = bob_id THEN ms.dst ELSE ms.src END LIKE 'U%'
    AND CASE WHEN ms.src = bob_id THEN ms.dst ELSE ms.src END <> alice_id
    AND CASE WHEN ms.src = bob_id THEN ms.dst ELSE ms.src END <> bob_id
),
intersection AS (
  SELECT
    a.peer_id,
    a.fwd_alice * a.rev_alice * b.fwd_bob * b.rev_bob AS bridge_score
  FROM alice_peers a
  INNER JOIN bob_peers b ON a.peer_id = b.peer_id
)
SELECT u.*
FROM public."user" u
INNER JOIN intersection i ON u.id = i.peer_id
WHERE NOT public.block_hides(alice_id, bob_id)
  AND NOT public.block_hides(alice_id, u.id)
ORDER BY i.bridge_score DESC, u.display_name;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.user_presence_hidden_for_viewer(
  user_presence_row public.user_presence,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
  SELECT public.block_hides(
    hasura_session ->> 'x-hasura-user-id',
    user_presence_row.user_id
  );
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.user_hidden_for_viewer(
  user_row public."user",
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
  SELECT public.block_hides(hasura_session ->> 'x-hasura-user-id', user_row.id);
$$;
''',
]);
