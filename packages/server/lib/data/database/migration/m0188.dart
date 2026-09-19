part of '_migrations.dart';

/// U10d — grouped-row provenance gets a callable source (§0.1a, card spec §4).
///
/// Forward notes and the relay chain have only ever existed on the **Inbox**
/// query, as the Hasura computed field `inbox_item.inbox_provenance_data`.
/// `AttentionReceipt` carries none, so a grouped `beacon:` row in the For You
/// read model cannot render the note that is the whole premise of the card.
///
/// The card spec is explicit that this must not grow a second provenance DTO:
/// the JSON shape stays byte-for-byte the one `InboxProvenance.parse` and
/// `withoutViewer` already consume. So the body of
/// `inbox_item_inbox_provenance_data` moves *out* into a plain function that
/// takes its inputs as arguments instead of reading them off an `inbox_item`
/// row, and the computed field becomes a one-line delegation. One body, one
/// shape, two callers — the same settlement U10a made for the visible/surface
/// CTE.
///
/// **The one deliberate difference, and why it is a parameter.** The attention
/// read path must exclude senders the viewer is blocked from — provenance
/// names *people*, and a `totalDistinctSenders` that counts a hidden person
/// leaks their existence just as surely as listing them would. The Hasura
/// computed field has never applied that filter. Quietly adding it here would
/// change Inbox behaviour under the cover of a refactor, so the exclusion is
/// `p_exclude_blocked` and the delegation passes `false`: identical output to
/// m0103 for Inbox, blocked-aware output for attention. That the Inbox path
/// wants the same treatment is a real finding, and a separate decision.
final m0188 = Migration('0188', [
  r'''
CREATE OR REPLACE FUNCTION public.attention_provenance_data(
  p_beacon_id text,
  p_recipient_id text,
  p_viewer_id text,
  p_inbox_context text,
  p_exclude_blocked boolean
) RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  AS $$
DECLARE
  ctx text;
  result jsonb;
BEGIN
  IF p_viewer_id IS NULL OR p_recipient_id IS NULL OR p_beacon_id IS NULL THEN
    RETURN '{"senders":[],"totalDistinctSenders":0,"strongestNotePreview":""}'::jsonb;
  END IF;

  SELECT coalesce(
      nullif(trim(p_inbox_context), ''),
      nullif(trim(b.context), '')
    )
  INTO ctx
  FROM public.beacon b
  WHERE b.id = p_beacon_id;

  ctx := coalesce(ctx, '');

  WITH senders AS (
    SELECT DISTINCT ON (bfe.sender_id)
      bfe.sender_id,
      bfe.note,
      bfe.created_at
    FROM public.beacon_forward_edge bfe
    WHERE bfe.recipient_id = p_recipient_id
      AND bfe.beacon_id = p_beacon_id
      AND bfe.sender_id <> p_recipient_id
      AND bfe.recipient_rejected = false
      AND bfe.cancelled_at IS NULL
      AND (
        nullif(trim(p_inbox_context), '') IS NULL
        OR nullif(trim(bfe.context), '') IS NULL
        OR bfe.context IS NOT DISTINCT FROM p_inbox_context
      )
      AND (
        NOT p_exclude_blocked
        OR NOT public.block_hides(bfe.sender_id, p_viewer_id)
      )
    ORDER BY bfe.sender_id, bfe.created_at DESC
  ),
  ms_raw AS (
    SELECT
      ms.src,
      ms.dst,
      ms.score_value_of_src::double precision AS score_value_of_src,
      ms.score_value_of_dst::double precision AS score_value_of_dst
    FROM mr_mutual_scores(p_viewer_id, ctx) ms
  ),
  ranked AS (
    SELECT
      s.sender_id,
      s.note AS last_note,
      coalesce(max(
        CASE
          WHEN m.src = p_viewer_id AND m.dst = s.sender_id THEN m.score_value_of_dst
          WHEN m.dst = p_viewer_id AND m.src = s.sender_id THEN m.score_value_of_src
          ELSE NULL::double precision
        END
      ), 0::double precision) AS mr
    FROM senders s
    LEFT JOIN ms_raw m ON (m.src = p_viewer_id AND m.dst = s.sender_id)
      OR (m.dst = p_viewer_id AND m.src = s.sender_id)
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
    WHERE pce.subject_user_id = p_recipient_id
      AND pce.beacon_id       = p_beacon_id
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

  RETURN result;
END;
$$;
''',

  // The Hasura computed field keeps its signature and its exact m0103 output;
  // only the body it used to spell out has moved.
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
BEGIN
  IF viewer_id IS NULL THEN
    RETURN '{"senders":[],"totalDistinctSenders":0,"strongestNotePreview":""}';
  END IF;

  RETURN public.attention_provenance_data(
    inbox_row.beacon_id,
    inbox_row.user_id,
    viewer_id,
    inbox_row.context,
    false
  )::text;
END;
$$;
''',

  '''
COMMENT ON FUNCTION public.attention_provenance_data(
  text, text, text, text, boolean
) IS
  'The one forward-provenance body (card spec §4 / plan §0.1a). Returns the exact `inbox_provenance_data` JSON shape — senders[] {id, displayName, imageId, notePreview, reasonSlugs[], mr}, totalDistinctSenders, strongestNotePreview — so InboxProvenance.parse and withoutViewer work unchanged on both callers. p_exclude_blocked drops blocked senders from the list *and* from the count; the Hasura computed field passes false to preserve its m0103 behaviour, the attention read path passes true.';
''',
]);
