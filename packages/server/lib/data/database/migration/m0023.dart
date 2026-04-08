part of '_migrations.dart';

// Add per-sender notePreview to inbox provenance JSON (for inbox card UI).
final m0023 = Migration('0023', [
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
  top3_joined AS (
    SELECT
      t.sender_id,
      t.mr,
      coalesce(nullif(trim(u.title), ''), '') AS title,
      u.image_id::text AS image_id,
      left(
        coalesce(nullif(trim(t.last_note), ''), ''),
        200
      ) AS note_preview
    FROM top3 t
    JOIN public."user" u ON u.id = t.sender_id
  )
  SELECT jsonb_build_object(
    'senders', coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', sender_id,
            'title', title,
            'mr', mr,
            'imageId', image_id,
            'notePreview', nullif(note_preview, '')
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
