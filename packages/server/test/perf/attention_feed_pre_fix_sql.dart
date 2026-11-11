/// The AttentionFeed SQL exactly as it shipped before the per-row visibility
/// fix, frozen as text so a test can compare it with the SQL the server runs
/// now. It is read-only reference data: do not "update" it to match the
/// repository — its whole value is that it does not move.
///
/// Every statement is valid against the schema through migration
/// [preFixSchemaVersion] (the last migration before the fix), which is the
/// schema the reference runs on. Parameters, as the repository bound them:
///
/// * feed statements: `$1` viewer, `$2` view (`'all'`), `$3` search (null),
///   `$4` surface (null for history, `'activity'`), `$5` page limit + 1;
/// * [preFixLiveObligationBeaconsSql]: `$1` viewer;
/// * [preFixUnreadForThreeBeaconsSql]: `$1` viewer, `$2`–`$4` Request ids.
library;

/// Last migration of the schema the frozen statements were written against.
const preFixSchemaVersion = '0302';

/// `attentionFeed(view: all, surface: null)` — the history page and summary.
const preFixAttentionFeedHistorySql = r'''
WITH visible_raw AS (
  SELECT (authorized.receipt).*, authorized.tombstone_copy
  FROM public.visible_attention_receipts($1) authorized
),
scope AS (
  SELECT base.beacon_id
  FROM public.responsibility_scope_base_beacons($1) base
  -- A pending author invite keeps the Request on the invite card in For You
  -- even when the viewer offered first; re-offering accepts it (Arch §5.4).
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.beacon_author_invite bai
    WHERE bai.beacon_id = base.beacon_id
      AND bai.invitee_id = $1
      AND bai.status = 0
  )
  UNION
  SELECT DISTINCT visible_raw.beacon_id
  FROM visible_raw
  WHERE visible_raw.requires_action
    AND visible_raw.settlement_kind IS NULL
    AND visible_raw.beacon_id IS NOT NULL
),
visible AS (
  SELECT
    visible_raw.*,
    CASE
      WHEN visible_raw.beacon_id IS NOT NULL
       AND visible_raw.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 'myWork'
      ELSE 'activity'
    END AS surface
  FROM visible_raw
),
summary AS (
  SELECT COUNT(*) FILTER (
    WHERE (((NOT v.requires_action AND v.cleared_at IS NULL) OR (v.requires_action AND v.settlement_kind IS NULL)) AND NOT EXISTS (SELECT 1 FROM public.beacon lb WHERE lb.id = v.beacon_id AND lb.kind = 1 AND (lb.status = 0 AND lb.expires_at > now()) IS NOT TRUE))
      AND ($4::text IS NULL OR v.surface = $4)
  )::int AS unread_total,
  COUNT(*) FILTER (
    WHERE v.requires_action AND v.settlement_kind IS NULL
  )::int AS needs_you_total
  FROM visible v
),
page AS (
  SELECT visible.*,
    NOT EXISTS (SELECT 1 FROM public.beacon lb WHERE lb.id = visible.beacon_id AND lb.kind = 1 AND (lb.status = 0 AND lb.expires_at > now()) IS NOT TRUE) AS history_lifecycle_eligible
  FROM visible
  WHERE (
    $2 = 'all'
    OR ($2 = 'unread' AND (((NOT visible.requires_action AND visible.cleared_at IS NULL) OR (visible.requires_action AND visible.settlement_kind IS NULL)) AND NOT EXISTS (SELECT 1 FROM public.beacon lb WHERE lb.id = visible.beacon_id AND lb.kind = 1 AND (lb.status = 0 AND lb.expires_at > now()) IS NOT TRUE)))
    OR ($2 = 'needsYou' AND visible.requires_action AND visible.settlement_kind IS NULL)
  )
  AND (
    $3::text IS NULL
    OR to_tsvector(
      'simple',
      coalesce(visible.presentation_payload ->> 'eventType', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'beaconId', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'coordinationItemId', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'targetEntityId', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'messageId', '')
    ) @@ websearch_to_tsquery('simple', $3)
    OR EXISTS (
      SELECT 1 FROM public."user" actor
      WHERE actor.id = visible.actor_user_id
        AND strpos(lower(actor.display_name), lower($3)) > 0
    )
  )
  AND ($4::text IS NULL OR visible.surface = $4)
    
  ORDER BY visible.created_at DESC, visible.id DESC
  LIMIT $5
)
SELECT summary.unread_total, summary.needs_you_total, page.*
FROM summary
LEFT JOIN LATERAL (SELECT * FROM page) page ON true
ORDER BY page.created_at DESC NULLS LAST, page.id DESC NULLS LAST
''';

/// `attentionFeed(view: all, surface: activity)` — the activity page and
/// summary.
const preFixAttentionFeedActivitySql = r'''
WITH visible_raw AS (
  SELECT (authorized.receipt).*, authorized.tombstone_copy
  FROM public.visible_attention_receipts($1) authorized
),
scope AS (
  SELECT base.beacon_id
  FROM public.responsibility_scope_base_beacons($1) base
  -- A pending author invite keeps the Request on the invite card in For You
  -- even when the viewer offered first; re-offering accepts it (Arch §5.4).
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.beacon_author_invite bai
    WHERE bai.beacon_id = base.beacon_id
      AND bai.invitee_id = $1
      AND bai.status = 0
  )
  UNION
  SELECT DISTINCT visible_raw.beacon_id
  FROM visible_raw
  WHERE visible_raw.requires_action
    AND visible_raw.settlement_kind IS NULL
    AND visible_raw.beacon_id IS NOT NULL
),
visible AS (
  SELECT
    visible_raw.*,
    CASE
      WHEN visible_raw.beacon_id IS NOT NULL
       AND visible_raw.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 'myWork'
      ELSE 'activity'
    END AS surface
  FROM visible_raw
),
summary AS (
  SELECT COUNT(*) FILTER (
    WHERE (((NOT v.requires_action AND v.cleared_at IS NULL) OR (v.requires_action AND v.settlement_kind IS NULL)) AND NOT EXISTS (SELECT 1 FROM public.beacon lb WHERE lb.id = v.beacon_id AND lb.kind = 1 AND (lb.status = 0 AND lb.expires_at > now()) IS NOT TRUE))
      AND ($4::text IS NULL OR v.surface = $4)
  )::int AS unread_total,
  COUNT(*) FILTER (
    WHERE v.requires_action AND v.settlement_kind IS NULL
  )::int AS needs_you_total
  FROM visible v
),
eligible_pinned AS (
  SELECT ii.beacon_id
  FROM public.inbox_item ii
  JOIN public.beacon b ON b.id = ii.beacon_id
  WHERE ii.user_id = $1
    AND b.kind = 0
    AND ii.tombstone_dismissed_at IS NULL
    AND ii.status = 0
    AND public.beacon_can_read_content(ii.beacon_id, $1)
    AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
),
request_entry AS (
  SELECT state.beacon_id, state.first_entry_at
  FROM public.attention_request_state state
  WHERE state.account_id = $1
),
eligible_forward AS (
  SELECT
    ii.beacon_id,
    ii.status,
    ii.forward_count,
    ii.latest_forward_at,
    COALESCE(re.first_entry_at, ii.latest_forward_at) AS entry_at,
    -- #601-a: the outcome tick. Somebody other than the viewer relabelled
    -- the row (a NULL actor is a system change, not the viewer) after the
    -- viewer last marked it seen.
    ii.outcome_changed_at,
    (
      ii.outcome_changed_at > COALESCE(ii.outcome_seen_at, '-infinity')
      AND ii.outcome_changed_by IS DISTINCT FROM $1
    ) AS outcome_unseen,
    ii.tombstone_dismissed_at,
    b.title AS beacon_title,
    b.status AS beacon_status,
    public.beacon_can_read_content(ii.beacon_id, $1) AS can_read_content,
    public.beacon_can_read_tombstone(ii.beacon_id, $1) AS can_read_tombstone
  FROM public.inbox_item ii
  JOIN public.beacon b ON b.id = ii.beacon_id
  LEFT JOIN request_entry re ON re.beacon_id = ii.beacon_id
  WHERE ii.user_id = $1
    AND b.kind = 0
    -- #412: the author's own Request is never an outcome of theirs ("You
    -- offered help"); it lives on My Work. Mirrored in Set O
    -- (AttentionDismissibleSql.dismissibleOutcomes) so dismissible == visible.
    AND b.user_id <> $1
    AND ii.tombstone_dismissed_at IS NULL
    -- #400: a status-3 tombstone of a Request the viewer answered (an offer
    -- that was later withdrawn or removed by a block) is not "closed before
    -- you answered"; the viewer did answer, so there is no outcome row.
    -- Mirrored in Set O (AttentionDismissibleSql.dismissibleOutcomes).
    AND NOT (
      ii.status = 3
      AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
      AND EXISTS (
        SELECT 1
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = $1
      )
    )
    AND (
      ii.status <> 0
      OR ii.beacon_id IN (SELECT scope.beacon_id FROM scope)
    )
    AND (
      public.beacon_can_read_content(ii.beacon_id, $1)
      OR (
        ii.status IN (3, 4)
        AND public.beacon_can_read_tombstone(ii.beacon_id, $1)
      )
    )
),
-- U15R-a / R1 — *representative* now means "an attention object that owns
-- this Request's children", and only the pinned zone is one. An outcome row
-- is a dated memory of the viewer's own act (contract section 7, owner
-- decision B): it carries no dot and no sub-cards, so it cannot be the thing
-- a live optional event hangs from. Before this, being answered — or having
-- the answer's trace dismissed — silently vetoed the Request's live
-- attention while that attention kept feeding the tab total: a lit tab over
-- a surface with nothing on it.
eligible_representative AS (
  SELECT beacon_id FROM eligible_pinned
),
activity_child_receipts AS (
  SELECT v.*
  FROM visible v
  WHERE v.surface = 'activity'
    AND v.beacon_id IS NOT NULL
    AND ((v.presentation_key IS DISTINCT FROM 'relay_received' OR EXISTS (SELECT 1 FROM public.beacon pk WHERE pk.id = v.beacon_id AND pk.kind = 1)) AND NOT EXISTS (SELECT 1 FROM public.notification_beacon_mute nm JOIN public.beacon mb ON mb.id = nm.beacon_id WHERE nm.account_id = v.account_id AND nm.beacon_id = v.beacon_id AND mb.kind = 1 AND (nm.muted_until IS NULL OR nm.muted_until > now()) AND v.kind IS DISTINCT FROM 'roomMention') AND NOT EXISTS (SELECT 1 FROM public.beacon lb WHERE lb.id = v.beacon_id AND lb.kind = 1 AND (lb.status = 0 AND lb.expires_at > now()) IS NOT TRUE))
    -- U11/D16, the load-bearing one. Everything a grouped For You row says
    -- about itself comes from here: `event_total` (the count),
    -- `event_unseen_count` (the dot), `MIN(created_at)` (its position) and
    -- `MAX(created_at)` (its freshness). A hierarchy notice propagated from a
    -- child is in the parent's log and in none of those — and because
    -- `event_total` is also the gate on the synthetic `requestActivity` row, a
    -- Request whose only receipt is such a notice grows no card at all.
    AND v.placement = 'primary'
    -- #189: For You carries only what can be skipped — no reminder about the
    -- viewer's own duty reaches a card, its count or its dot.
    AND (v.presentation_key IS NULL OR v.presentation_key <> ALL (ARRAY['closure_draft_reminder', 'deadline_reminder', 'plan_change_pending', 'plan_step_due', 'plan_step_overdue', 'plan_step_reminder', 'plan_step_turn', 'request_stale', 'stale_reminder']::text[]))
    -- Plan C6: a pinned row with a pending invite is the invite card; its
    -- `authorInviteReceived` receipt is the card, not one of its events.
    AND NOT ((v.kind = 'authorInviteReceived' AND EXISTS ( SELECT 1 FROM public.beacon_author_invite bai WHERE bai.beacon_id = v.beacon_id AND bai.invitee_id = v.account_id AND bai.status = 0)) AND v.beacon_id IN (SELECT beacon_id FROM eligible_pinned))
),
beacon_activity_stats AS (
  SELECT
    beacon_id,
    MAX(created_at) AS max_created_at,
    MIN(created_at) AS min_created_at,
    -- #189: optional events only. `activeAttention` also admits live
    -- obligations, and For You never carries anything the viewer owes; an
    -- obligation lives on My Work (its Request is in scope by construction,
    -- so this is a guard on the rule rather than a change in membership).
    COUNT(*) FILTER (
      WHERE NOT child.requires_action AND child.cleared_at IS NULL
    )::int AS event_total,
    COUNT(*) FILTER (
      WHERE NOT child.requires_action AND child.cleared_at IS NULL
    )::int AS event_unseen_count
  FROM activity_child_receipts child
  GROUP BY beacon_id
),
page_stream AS (
  SELECT
        v.id,
    v.account_id,
    v.category,
    v.kind,
    v.priority,
    v.title,
    v.body,
    v.action_url,
    v.created_at,
    v.collapsed_count,
    v.beacon_id,
    v.coordination_item_id,
    v.actor_user_id,
    v.seen_at,
    v.source_event_key,
    v.destination_kind,
    v.target_entity_id,
    v.presentation_key,
    v.presentation_payload,
    v.in_app_preference_class,
    v.suppression_class,
    v.access_policy,
    v.requires_action,
    v.attention_thread_key,
    v.settlement_kind,
    v.settled_at,
    v.settled_by_user_id,
    v.settled_by_occurrence_id,
    v.tombstone_copy,
    v.cleared_at,
    v.clear_reason,
    v.surface,
    (
      ((NOT v.requires_action AND v.cleared_at IS NULL) OR (v.requires_action AND v.settlement_kind IS NULL))
      AND v.placement = 'primary'
    ) AS is_active_attention,
    'receipt'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    NULL::int AS digest_count,
    NULL::int AS event_total,
    NULL::int AS event_unseen_count
  FROM visible v
  WHERE v.surface = 'activity'
    AND v.beacon_id IS NULL

  UNION ALL

  SELECT
    ('inbox:' || ef.beacon_id) AS id,
    $1::text AS account_id,
    'coordination'::text AS category,
    'newRelay'::text AS kind,
    'normal'::text AS priority,
    CASE
      WHEN ef.can_read_content THEN COALESCE(ef.beacon_title, '')
      ELSE ''::text
    END AS title,
    ''::text AS body,
    ('/#/view?id=' || ef.beacon_id) AS action_url,
    -- U10c: the *position* key. A forward row sits where the Request
    -- entered, not where its newest child event is (see the contract's
    -- section 6). The latest-event key stays available via the stats.
    -- #601-a: a relabel to an outcome moves it up (GREATEST skips NULL).
    GREATEST(ef.entry_at, ef.outcome_changed_at) AS created_at,
    0 AS collapsed_count,
    ef.beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    -- U15R-a / R1: an outcome row carries no dot (owner decision B,
    -- contract section 7); its Request's live attention lights the
    -- `requestActivity` row instead. #601-a: its one read marker is the
    -- outcome tick — unseen only after somebody else relabelled it.
    CASE
      WHEN ef.outcome_unseen THEN NULL::timestamptz
      ELSE ef.latest_forward_at
    END AS seen_at,
    NULL::text AS source_event_key,
    'beacon'::text AS destination_kind,
    ef.beacon_id AS target_entity_id,
    'relay_received'::text AS presentation_key,
    -- #367: the stage of an accepted helper rides the payload; the outcome
    -- word stays 'helping' so shipped clients keep their sentence.
    jsonb_strip_nulls(jsonb_build_object(
      'helperStage', hs.helper_stage,
      'roleLabel', CASE
        WHEN hs.helper_stage IS NOT NULL THEN NULLIF(btrim(hs.role_label), '')
      END,
      -- #507: who accepted the offer (the author or a steward).
      'actorUserId', CASE
        WHEN hs.helper_stage = 'accepted' THEN hs.acceptor_id
      END,
      -- #665: the helper was admitted by accepting the author's invitation
      -- (a bud invite), not by having an offer accepted.
      'acceptedInvite', CASE
        WHEN hs.helper_stage = 'accepted'
          AND hs.accepted_invite_inviter_id IS NOT NULL THEN true
      END,
      'inviterId', CASE
        WHEN hs.helper_stage = 'accepted' THEN hs.accepted_invite_inviter_id
      END,
      -- #725: a 'notInterested' row that is the viewer's answer to an
      -- author invitation ("Can't make it"), not a dismissed forward: the
      -- viewer's latest invite to this Request was declined.
      'declinedInvite', CASE
        WHEN ef.status = 2
          AND ef.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
          AND (
            SELECT ai.status
            FROM public.beacon_author_invite ai
            WHERE ai.beacon_id = ef.beacon_id
              AND ai.invitee_id = $1
            ORDER BY ai.created_at DESC, ai.id DESC
            LIMIT 1
          ) = 2 THEN true
      END
    )) AS presentation_payload,
    NULL::text AS in_app_preference_class,
    'standard'::text AS suppression_class,
    'beacon_content'::text AS access_policy,
    false AS requires_action,
    NULL::text AS attention_thread_key,
    NULL::text AS settlement_kind,
    NULL::timestamptz AS settled_at,
    NULL::text AS settled_by_user_id,
    NULL::text AS settled_by_occurrence_id,
    (
      NOT ef.can_read_content
      AND NOT (
        ef.status IN (3, 4)
        AND ef.can_read_tombstone
      )
    ) AS tombstone_copy,
    NULL::timestamptz AS cleared_at,
    NULL::text AS clear_reason,
    'activity'::text AS surface,
    -- U15R-a / R1: an outcome row is dismissible, but it is not a second
    -- attention object and it never carries the dot — the children it used
    -- to borrow one from now own their own row.
    false AS is_active_attention,
    'forward'::text AS item_kind,
    CASE
      WHEN ef.beacon_id IN (SELECT scope.beacon_id FROM scope) THEN 'helping'
      WHEN ef.status = 1 THEN 'watching'
      WHEN ef.status = 2 THEN 'notInterested'
      WHEN ef.status = 3 THEN 'closedBeforeResponse'
      WHEN ef.status = 4 THEN 'deletedBeforeResponse'
      ELSE NULL::text
    END AS forward_outcome,
    ef.forward_count AS forward_count,
    NULL::int AS digest_count,
    -- U15R-a / R1: "no sub-cards" for every outcome, not only the helping
    -- one. The counts stay reachable — on the Request's own row.
    0 AS event_total,
    0 AS event_unseen_count
  FROM eligible_forward ef
  -- #367: an accepted helper — in scope, with a live offer, admitted to the
  -- Request's room — is told so ('accepted'), and again when the Request
  -- enters Wrapping up ('wrappingUp'). Closed and cancelled Requests carry
  -- no stage and read as plain 'helping'.
  LEFT JOIN LATERAL (
    SELECT
      CASE
        WHEN ef.beacon_status = 5 THEN 'wrappingUp'
        WHEN ef.beacon_status NOT IN (1, 6) THEN 'accepted'
      END AS helper_stage,
      ho.role_label,
      -- #507: the actor of the helper's latest acknowledgement (kind 1).
      (
        SELECT ce.actor_user_id
        FROM public.beacon_commitment_event ce
        WHERE ce.beacon_id = ef.beacon_id
          AND ce.user_id = $1
          AND ce.kind = 1
        ORDER BY ce.seq DESC
        LIMIT 1
      ) AS acceptor_id,
      -- #665: the latest acknowledgement came from the viewer accepting an
      -- author invite: the invite was accepted in (or after) the same
      -- transaction that recorded it. A later ordinary accept is newer.
      -- The inviter rides along so the client names them, not the author.
      (
        SELECT ai.inviter_id
        FROM public.beacon_author_invite ai
        WHERE ai.beacon_id = ef.beacon_id
          AND ai.invitee_id = $1
          AND ai.status = 1
          AND ai.resolved_at >= (
            SELECT ce.created_at
            FROM public.beacon_commitment_event ce
            WHERE ce.beacon_id = ef.beacon_id
              AND ce.user_id = $1
              AND ce.kind = 1
            ORDER BY ce.seq DESC
            LIMIT 1
          )
        ORDER BY ai.resolved_at DESC
        LIMIT 1
      ) AS accepted_invite_inviter_id
    FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = ef.beacon_id
      AND ho.user_id = $1
      AND ho.status = 0
      AND ef.beacon_id IN (SELECT scope.beacon_id FROM scope)
      AND EXISTS (
        SELECT 1
        FROM public.beacon_participant bp
        WHERE bp.beacon_id = ef.beacon_id
          AND bp.user_id = $1
          AND bp.room_access = 3
      )
    LIMIT 1
  ) hs ON true

  UNION ALL

  SELECT
    ('activity-beacon:' || stats.beacon_id) AS id,
    $1::text AS account_id,
    'coordination'::text AS category,
    'roomActivityLowPriority'::text AS kind,
    'normal'::text AS priority,
    CASE
      WHEN public.beacon_can_read_content(stats.beacon_id, $1)
      THEN COALESCE(b.title, '')
      ELSE ''::text
    END AS title,
    ''::text AS body,
    ('/#/view?id=' || stats.beacon_id) AS action_url,
    -- U10c: a synthetic group has no inbox row and therefore no
    -- `first_entry_at`; its entry is the first child that put it on the
    -- surface, which is immutable and does not move when a second arrives.
    -- Post (kind = 1): position is the newest child instead.
    CASE WHEN b.kind = 1 THEN stats.max_created_at
      ELSE stats.min_created_at END AS created_at,
    0 AS collapsed_count,
    stats.beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    CASE
      WHEN stats.event_unseen_count > 0 THEN NULL::timestamptz
      ELSE stats.max_created_at
    END AS seen_at,
    NULL::text AS source_event_key,
    'beacon'::text AS destination_kind,
    stats.beacon_id AS target_entity_id,
    'request_status_changed'::text AS presentation_key,
    '{}'::jsonb AS presentation_payload,
    NULL::text AS in_app_preference_class,
    'standard'::text AS suppression_class,
    'beacon_content'::text AS access_policy,
    false AS requires_action,
    NULL::text AS attention_thread_key,
    NULL::text AS settlement_kind,
    NULL::timestamptz AS settled_at,
    NULL::text AS settled_by_user_id,
    NULL::text AS settled_by_occurrence_id,
    NOT public.beacon_can_read_content(stats.beacon_id, $1) AS tombstone_copy,
    NULL::timestamptz AS cleared_at,
    NULL::text AS clear_reason,
    'activity'::text AS surface,
    (stats.event_unseen_count > 0) AS is_active_attention,
    'requestActivity'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    NULL::int AS digest_count,
    stats.event_total,
    stats.event_unseen_count
  FROM beacon_activity_stats stats
  JOIN public.beacon b ON b.id = stats.beacon_id
  WHERE stats.event_total > 0
    AND stats.beacon_id NOT IN (SELECT beacon_id FROM eligible_representative)
    -- U15R-a / R1: deliberately *not* gated on `tombstone_dismissed_at`.
    -- Putting the memory away is not a decision about what the Request does
    -- next. The tombstone itself stays gone — `eligible_forward` still
    -- excludes it — so nothing is resurrected here; only live attention that
    -- the tab is already counting becomes reachable again.
    AND stats.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)

  UNION ALL

  SELECT
    'watching-digest'::text AS id,
    $1::text AS account_id,
    'ambient'::text AS category,
    'roomActivityLowPriority'::text AS kind,
    'low'::text AS priority,
    ''::text AS title,
    ''::text AS body,
    ''::text AS action_url,
    digest.max_created_at AS created_at,
    0 AS collapsed_count,
    NULL::text AS beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    NULL::timestamptz AS seen_at,
    NULL::text AS source_event_key,
    NULL::text AS destination_kind,
    NULL::text AS target_entity_id,
    'request_status_changed'::text AS presentation_key,
    '{}'::jsonb AS presentation_payload,
    NULL::text AS in_app_preference_class,
    'standard'::text AS suppression_class,
    'legacy'::text AS access_policy,
    false AS requires_action,
    NULL::text AS attention_thread_key,
    NULL::text AS settlement_kind,
    NULL::timestamptz AS settled_at,
    NULL::text AS settled_by_user_id,
    NULL::text AS settled_by_occurrence_id,
    false AS tombstone_copy,
    NULL::timestamptz AS cleared_at,
    NULL::text AS clear_reason,
    'activity'::text AS surface,
    true AS is_active_attention,
    'watchingDigest'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    digest.beacon_count AS digest_count,
    NULL::int AS event_total,
    NULL::int AS event_unseen_count
  FROM (
    SELECT
      MAX(v.created_at) AS max_created_at,
      COUNT(DISTINCT ii.beacon_id)::int AS beacon_count
    FROM public.inbox_item ii
    INNER JOIN visible v
      ON v.beacon_id = ii.beacon_id
     AND NOT v.requires_action AND v.cleared_at IS NULL
     AND v.placement = 'primary'
     AND NOT EXISTS (SELECT 1 FROM public.beacon lb WHERE lb.id = v.beacon_id AND lb.kind = 1 AND (lb.status = 0 AND lb.expires_at > now()) IS NOT TRUE)
     AND v.created_at > ii.latest_forward_at
    WHERE ii.user_id = $1
      AND ii.status = 1
      AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
  ) digest
  WHERE digest.beacon_count > 0
),
page AS (
  SELECT stream.*
  FROM page_stream stream
  WHERE (
    $2 = 'all'
    OR ($2 = 'unread' AND stream.is_active_attention)
    OR ($2 = 'needsYou' AND stream.requires_action AND stream.settlement_kind IS NULL)
  )
  AND (
    $3::text IS NULL
    OR to_tsvector(
      'simple',
      coalesce(stream.presentation_payload ->> 'eventType', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'beaconId', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'coordinationItemId', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'targetEntityId', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'messageId', '')
    ) @@ websearch_to_tsquery('simple', $3)
    OR EXISTS (
      SELECT 1 FROM public."user" actor
      WHERE actor.id = stream.actor_user_id
        AND strpos(lower(actor.display_name), lower($3)) > 0
    )
  )
  
  ORDER BY stream.created_at DESC, stream.id DESC
  LIMIT $5
)
SELECT summary.unread_total, summary.needs_you_total, page.*
FROM summary
LEFT JOIN LATERAL (SELECT * FROM page) page ON true
ORDER BY page.created_at DESC NULLS LAST, page.id DESC NULLS LAST
''';

/// `liveObligationBeacons` — Requests with a live obligation for the viewer.
const preFixLiveObligationBeaconsSql = r'''
SELECT DISTINCT (visible.receipt).beacon_id AS beacon_id
FROM public.visible_attention_receipts($1, true) visible
''';

/// `unreadForBeacons` for three Requests — which of them still have active
/// attention for the viewer.
const preFixUnreadForThreeBeaconsSql = r'''
SELECT DISTINCT receipt.beacon_id
FROM public.visible_attention_receipts($1) visible
JOIN public.notification_outbox receipt ON receipt.id = visible.receipt_id
WHERE ((NOT receipt.requires_action AND receipt.cleared_at IS NULL) OR (receipt.requires_action AND receipt.settlement_kind IS NULL))
  AND receipt.placement = 'primary'
  AND NOT EXISTS (SELECT 1 FROM public.beacon lb WHERE lb.id = receipt.beacon_id AND lb.kind = 1 AND (lb.status = 0 AND lb.expires_at > now()) IS NOT TRUE)
  AND receipt.beacon_id IN ($2,$3,$4)
''';
