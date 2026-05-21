part of '_migrations.dart';

/// Rename user identity column `title` → `display_name`; update SQL that references it.
final m0078 = Migration('0078', [
  r'''
ALTER TABLE public."user" RENAME COLUMN title TO display_name;
''',
  r'''
ALTER TABLE public."user" RENAME CONSTRAINT user__title_len TO user__display_name_len;
''',
  // mutual_friends ORDER BY (from m0031)
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
ORDER BY i.bridge_score DESC, u.display_name;
$$;
''',
  // inbox provenance (from m0051)
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_inbox_provenance_data(
  inbox_row public.inbox_item,
  hasura_session json
) RETURNS text
  LANGUAGE plpgsql
  STABLE
  AS $$
DECLARE
  viewer_id text := nullif(trim(hasura_session ->> 'x-hasura-user-id'), '');
  ctx text;
  result jsonb;
BEGIN
  IF viewer_id IS NULL THEN
    RETURN '{"senders":[],"totalDistinctSenders":0,"strongestNotePreview":""}';
  END IF;

  SELECT coalesce(
      nullif(trim(inbox_row.context), ''),
      nullif(trim(b.context), '')
    )
  INTO ctx
  FROM public.beacon b
  WHERE b.id = inbox_row.beacon_id;

  ctx := coalesce(ctx, '');

  WITH senders AS (
    SELECT DISTINCT ON (bfe.sender_id)
      bfe.sender_id,
      bfe.note,
      bfe.created_at
    FROM public.beacon_forward_edge bfe
    WHERE bfe.recipient_id = inbox_row.user_id
      AND bfe.beacon_id = inbox_row.beacon_id
      AND bfe.recipient_rejected = false
      AND (
        inbox_row.context IS NULL
        OR bfe.context IS NOT DISTINCT FROM inbox_row.context
      )
    ORDER BY bfe.sender_id, bfe.created_at DESC
  ),
  ms_raw AS (
    SELECT
      ms.src,
      ms.dst,
      ms.score_value_of_src::double precision AS score_value_of_src,
      ms.score_value_of_dst::double precision AS score_value_of_dst
    FROM mr_mutual_scores(viewer_id, ctx) ms
  ),
  ranked AS (
    SELECT
      s.sender_id,
      s.note AS last_note,
      coalesce(max(
        CASE
          WHEN m.src = viewer_id AND m.dst = s.sender_id THEN m.score_value_of_dst
          WHEN m.dst = viewer_id AND m.src = s.sender_id THEN m.score_value_of_src
          ELSE NULL::double precision
        END
      ), 0::double precision) AS mr
    FROM senders s
    LEFT JOIN ms_raw m ON (m.src = viewer_id AND m.dst = s.sender_id)
      OR (m.dst = viewer_id AND m.src = s.sender_id)
    GROUP BY s.sender_id, s.note
  ),
  top3 AS (
    SELECT sender_id, mr, last_note
    FROM ranked
    ORDER BY mr DESC, sender_id ASC
    LIMIT 3
  ),
  total AS (
    SELECT count(*)::int AS cnt FROM senders
  ),
  best AS (
    SELECT last_note
    FROM ranked
    ORDER BY mr DESC, sender_id ASC
    LIMIT 1
  ),
  sender_reason_slugs AS (
    SELECT
      pce.observer_user_id AS sender_id,
      array_agg(DISTINCT pce.tag_slug ORDER BY pce.tag_slug) AS slugs
    FROM public.person_capability_event pce
    WHERE pce.subject_user_id = inbox_row.user_id
      AND pce.beacon_id       = inbox_row.beacon_id
      AND pce.source_type     = 1
      AND pce.deleted_at IS NULL
      AND pce.is_negative     = false
    GROUP BY pce.observer_user_id
  ),
  top3_joined AS (
    SELECT
      t.sender_id,
      t.mr,
      coalesce(nullif(trim(u.display_name), ''), '') AS display_name,
      u.image_id::text AS image_id,
      left(
        coalesce(nullif(trim(t.last_note), ''), ''),
        200
      ) AS note_preview,
      coalesce(srs.slugs, '{}') AS reason_slugs
    FROM top3 t
    JOIN public."user" u ON u.id = t.sender_id
    LEFT JOIN sender_reason_slugs srs ON srs.sender_id = t.sender_id
  )
  SELECT jsonb_build_object(
    'senders', coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', sender_id,
            'displayName', display_name,
            'mr', mr,
            'imageId', image_id,
            'notePreview', nullif(note_preview, ''),
            'reasonSlugs', reason_slugs
          )
          ORDER BY mr DESC, sender_id ASC
        )
        FROM top3_joined
      ),
      '[]'::jsonb
    ),
    'totalDistinctSenders', (SELECT cnt FROM total),
    'strongestNotePreview', left(
      coalesce(nullif(trim((SELECT last_note FROM best)), ''), ''),
      200
    )
  )
  INTO result;

  RETURN result::text;
END;
$$;
''',
]);
