part of '_migrations.dart';

/// U15R-b — R4: the provenance document gains the card's first slot.
///
/// D-171-5a pins the first collapsed slot of a For You card to **the latest
/// forward carrying a note**. m0188's document answers a different question:
/// it returns the three senders MeritRank ranks highest, and reads
/// `strongestNotePreview` off the top-ranked one *without* requiring that
/// sender to have written anything. Those selections diverge in the ordinary
/// case — a recent note from a fourth-ranked sender is absent from the payload
/// entirely — so U16 cannot recover the first slot by sorting what it is
/// given. This is a defect in the contract, not in the card.
///
/// **Additive, on the one body.** §0.1a's settlement is that
/// `InboxProvenance.parse` and `withoutViewer` work unchanged on both callers,
/// so the fix adds a key rather than forking the shape: `latestNoteForward`,
/// `null` when no forward carries a note. The client parser ignores unknown
/// keys, so the Inbox delegate keeps working against the same body, and the
/// `p_exclude_blocked: false` it passes — issue #188, a product decision —
/// is untouched.
///
/// **The authorization property is structural, not repeated.** The new
/// selection reads from the same `edges` CTE the sender list and the count are
/// built from, so every filter that already drops a forward — blocked in
/// either direction, cancelled, rejected by the recipient, out of context,
/// self-forwarded — drops it from the first slot by construction. There is no
/// second WHERE clause to keep in step with the first one. What the content
/// wall answers for is unchanged: a Request the viewer may not read yields no
/// document at all, decided a level up in `_attachGroupedProvenance`.
///
/// Ties break on `id DESC` after `created_at DESC`, so the slot is stable for
/// two forwards stamped at the same instant.
final m0190 = Migration('0190', [
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
    RETURN '{"senders":[],"totalDistinctSenders":0,'
      || '"strongestNotePreview":"","latestNoteForward":null}';
  END IF;

  SELECT coalesce(
      nullif(trim(p_inbox_context), ''),
      nullif(trim(b.context), '')
    )
  INTO ctx
  FROM public.beacon b
  WHERE b.id = p_beacon_id;

  ctx := coalesce(ctx, '');

  WITH edges AS (
    SELECT
      bfe.id,
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
  ),
  senders AS (
    SELECT DISTINCT ON (e.sender_id)
      e.sender_id,
      e.note,
      e.created_at
    FROM edges e
    ORDER BY e.sender_id, e.created_at DESC
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
  -- D-171-5a. Selected from `edges`, so it inherits every exclusion the list
  -- and the count already apply; there is no second wall to maintain.
  latest_note_edge AS (
    SELECT e.id, e.sender_id, e.note, e.created_at
    FROM edges e
    WHERE nullif(trim(e.note), '') IS NOT NULL
    ORDER BY e.created_at DESC, e.id DESC
    LIMIT 1
  ),
  latest_note_joined AS (
    SELECT jsonb_build_object(
      'forwardId', l.id,
      'senderId', l.sender_id,
      'displayName', coalesce(nullif(trim(u.display_name), ''), ''),
      'imageId', u.image_id::text,
      'notePreview', left(trim(l.note), 200),
      'reasonSlugs', coalesce(srs.slugs, '{}'),
      'forwardedAt', to_char(
        l.created_at AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    ) AS doc
    FROM latest_note_edge l
    JOIN public."user" u ON u.id = l.sender_id
    LEFT JOIN sender_reason_slugs srs ON srs.sender_id = l.sender_id
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
    ),
    'latestNoteForward', (SELECT doc FROM latest_note_joined)
  )
  INTO result;

  RETURN result;
END;
$$;
''',

  '''
COMMENT ON FUNCTION public.attention_provenance_data(
  text, text, text, text, boolean
) IS
  'The one forward-provenance body (card spec §4 / plan §0.1a). Returns the `inbox_provenance_data` JSON shape — senders[] {id, displayName, imageId, notePreview, reasonSlugs[], mr}, totalDistinctSenders, strongestNotePreview — plus `latestNoteForward` {forwardId, senderId, displayName, imageId, notePreview, reasonSlugs[], forwardedAt} or null (D-171-5a: the card pins its first collapsed slot to the latest forward carrying a note, which the MR-ranked window cannot reach). The addition is additive, so InboxProvenance.parse and withoutViewer keep working on both callers. Every selection reads from one filtered `edges` CTE: p_exclude_blocked drops blocked senders from the list, the count *and* the pinned forward; the Hasura computed field passes false to preserve its m0103 behaviour (issue #188), the attention read path passes true.';
''',
]);
