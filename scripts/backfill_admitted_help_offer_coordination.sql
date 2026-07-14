-- Local-dev backfill: admitted active help offers missing coordination rows.
-- Mirrors HelpOfferCase._autoAdmitIfTrusted / CoordinationCase.acceptHelpOffer:
--   response_type 0 = useful; admission action 0 = auto_admit, 1 = accept.
-- Safe to re-run: skips rows that already have coordination or admission events.

BEGIN;

WITH gaps AS (
  SELECT
    ho.beacon_id,
    ho.user_id AS offer_user_id,
    b.user_id AS author_user_id,
    ho.created_at AS offer_created_at,
    EXISTS (
      SELECT 1
      FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = ho.beacon_id
        AND fe.sender_id = b.user_id
        AND fe.recipient_id = ho.user_id
        AND fe.cancelled_at IS NULL
    ) AS direct_author_forward
  FROM public.beacon_help_offer ho
  JOIN public.beacon_participant bp
    ON bp.beacon_id = ho.beacon_id
   AND bp.user_id = ho.user_id
  JOIN public.beacon b ON b.id = ho.beacon_id
  WHERE ho.status = 0
    AND bp.room_access = 3
    AND NOT EXISTS (
      SELECT 1
      FROM public.beacon_help_offer_coordination c
      WHERE c.offer_beacon_id = ho.beacon_id
        AND c.offer_user_id = ho.user_id
    )
),
inserted_coordination AS (
  INSERT INTO public.beacon_help_offer_coordination (
    offer_beacon_id,
    offer_user_id,
    author_user_id,
    response_type,
    created_at,
    updated_at
  )
  SELECT
    g.beacon_id,
    g.offer_user_id,
    g.author_user_id,
    0,
    g.offer_created_at,
    g.offer_created_at
  FROM gaps g
  RETURNING offer_beacon_id, offer_user_id
),
inserted_admission AS (
  INSERT INTO public.beacon_help_offer_admission_event (
    id,
    beacon_id,
    offer_user_id,
    actor_user_id,
    action,
    reason,
    created_at
  )
  SELECT
    'HA' || lower(substr(md5(g.beacon_id || g.offer_user_id || 'admit'), 1, 12)),
    g.beacon_id,
    g.offer_user_id,
    g.author_user_id,
    CASE WHEN g.direct_author_forward THEN 0 ELSE 1 END,
    NULL,
    g.offer_created_at
  FROM gaps g
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.beacon_help_offer_admission_event ae
    WHERE ae.beacon_id = g.beacon_id
      AND ae.offer_user_id = g.offer_user_id
  )
  RETURNING beacon_id, offer_user_id
)
SELECT
  (SELECT count(*) FROM gaps) AS gap_rows,
  (SELECT count(*) FROM inserted_coordination) AS coordination_inserted,
  (SELECT count(*) FROM inserted_admission) AS admission_inserted;

COMMIT;
