part of '_migrations.dart';

/// On-demand mutual friends sorted by bridge score.
///
/// Bridge score for each mutual friend P: alice→P (fwd) × P→alice (rev) ×
/// bob→P (fwd) × P→bob (rev). Computed in a single pass over
/// `mr_mutual_scores` for each side with no additional queries.
///
/// Column semantics of `mr_mutual_scores(viewer, ctx)`:
///   src = viewer, dst = peer  →  score_value_of_dst = viewer→peer (fwd)
///                                score_value_of_src = peer→viewer (rev)
///   src = peer,   dst = viewer →  score_value_of_src = viewer→peer (fwd)
///                                score_value_of_dst = peer→viewer (rev)
final m0031 = Migration('0031', [
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
ORDER BY i.bridge_score DESC, u.title;
$$;
''',
]);
