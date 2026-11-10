part of '_migrations.dart';

/// #747 round 3 — `visible_attention_receipts` (m0277) authorized each
/// distinct Request of the viewer's history with its own
/// `beacon_can_read_content` call. That function is one CASE statement over
/// every visibility branch, so each call paid ~0.15 ms to start all of their
/// subplans whichever branch answered: a viewer with a long history paid it
/// for every Request in it on every attention read (AttentionFeed 57014 on
/// dev's 2-vCPU host).
///
/// Content readability is now settled set-based. The certain case — a
/// Request that is not deleted or a draft, the viewer's own or forwarded to
/// them on an active edge, and not hidden by a block (the leading branches of
/// `beacon_can_read_content`, in its order) — is a join. The rest go in one
/// call to `beacon_readable_ids`, the set-based twin of
/// `beacon_can_read_content` that the Field already uses and that
/// `beacon_readable_ids_parity_pg_test` holds to the same verdicts; it has a
/// fixed cost of ~2 ms, so it is called only when some Request is left.
/// `beacon_can_read_tombstone` is false
/// unless the Request is deleted (status 2), so it is asked only then. A
/// receipt whose Request row no longer exists is neither readable nor a
/// tombstone, as before. Signature and results are unchanged.
///
/// The body moves from SQL to plpgsql `RETURN QUERY`: a SQL function with
/// `SET search_path` is planned again on every call, while plpgsql keeps the
/// plan per pooled connection. The candidates carry only the columns the
/// policy reads next to the receipt, not every column twice.
///
/// `responsibility_scope_base_beacons` (m0251, body unchanged) moves to
/// plpgsql `RETURN QUERY` for the same planning reason: the feed statement's
/// scope re-planned it on every read.
final m0303 = Migration('0303', [
  r'''
CREATE OR REPLACE FUNCTION public.visible_attention_receipts(
  p_account_id text,
  p_live_obligations_only boolean DEFAULT false
) RETURNS TABLE(
  receipt_id text,
  tombstone_copy boolean,
  receipt public.notification_outbox
)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
RETURN QUERY
WITH candidates AS (
  SELECT
    n.id, n.beacon_id, n.access_policy, n.presentation_key,
    n.destination_kind, n.suppression_class, n.in_app_preference_class,
    n AS receipt
  FROM public.notification_outbox n
  WHERE n.account_id = p_account_id
    AND (
      NOT p_live_obligations_only
      OR (n.requires_action AND n.settlement_kind IS NULL)
    )
),
-- The leading branches of `beacon_can_read_content`, in its order, settled
-- set-based: not deleted or a draft, the viewer's own or forwarded to them
-- on an active edge, and not hidden by a block. Everything else is left to
-- `beacon_readable_ids`.
candidate_beacon AS MATERIALIZED (
  SELECT
    b.id,
    b.status,
    b.status NOT IN (2, 3)
      AND (
        b.user_id = p_account_id
        OR EXISTS (
          SELECT 1 FROM public.beacon_forward_edge fe
          WHERE fe.beacon_id = b.id
            AND fe.recipient_id = p_account_id
            AND fe.cancelled_at IS NULL
        )
      )
      AND NOT public.block_hides(b.user_id, p_account_id) AS surely_readable
  FROM (
    SELECT DISTINCT c.beacon_id
    FROM candidates c
    WHERE c.beacon_id IS NOT NULL
  ) candidate
  JOIN public.beacon b ON b.id = candidate.beacon_id
),
-- Read only when some Request is not settled above: one set-based call.
readable_rest AS MATERIALIZED (
  SELECT readable_id
  FROM public.beacon_readable_ids(
    p_account_id,
    ARRAY(
      SELECT cb.id FROM candidate_beacon cb WHERE NOT cb.surely_readable
    )
  ) AS readable_id
),
beacon_access AS MATERIALIZED (
  SELECT
    cb.id AS beacon_id,
    CASE
      WHEN cb.surely_readable THEN true
      ELSE cb.id IN (SELECT r.readable_id FROM readable_rest r)
    END AS can_read_content,
    cb.status = 2
      AND public.beacon_can_read_tombstone(cb.id, p_account_id)
      AS can_read_tombstone
  FROM candidate_beacon cb
)
SELECT
  c.id,
  (c.beacon_id IS NOT NULL
    AND NOT COALESCE(a.can_read_content, false)
    AND COALESCE(a.can_read_tombstone, false)) AS tombstone_copy,
  c.receipt
FROM candidates c
LEFT JOIN beacon_access a ON a.beacon_id = c.beacon_id
WHERE
  CASE c.access_policy
    WHEN 'legacy' THEN
      c.beacon_id IS NULL OR a.can_read_content OR a.can_read_tombstone
    WHEN 'beacon_content' THEN a.can_read_content
    WHEN 'beacon_tombstone' THEN a.can_read_tombstone
    WHEN 'recipient_safe' THEN
      c.presentation_key IN (
        'room_member_removed', 'offer_declined', 'offer_removed'
      )
      AND c.destination_kind = 'safe_terminal'
    WHEN 'profile' THEN
      c.beacon_id IS NULL
      AND c.presentation_key IN (
        'mutual_connection_formed', 'invite_accepted'
      )
      AND c.destination_kind = 'profile'
    ELSE false
  END
  AND (
    c.suppression_class <> 'noisy'
    OR c.in_app_preference_class IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM public.notification_preference np
      WHERE np.account_id = p_account_id
        AND c.in_app_preference_class = ANY(
          np.muted_in_app_event_classes
        )
    )
  );
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.responsibility_scope_base_beacons(p_account_id text) RETURNS TABLE(beacon_id text)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
RETURN QUERY
SELECT b.id
FROM public.beacon b
WHERE b.user_id = p_account_id
  AND b.kind = 0
  AND b.status <> 2
UNION
SELECT ho.beacon_id
FROM public.beacon_help_offer ho
INNER JOIN public.beacon b ON b.id = ho.beacon_id
WHERE ho.user_id = p_account_id
  AND ho.status = 0
  AND b.kind = 0
  AND b.status <> 2
UNION
SELECT ci.beacon_id
FROM public.coordination_item ci
INNER JOIN public.beacon b ON b.id = ci.beacon_id
WHERE ci.kind = 6
  AND ci.status = 0
  AND ci.target_person_id = p_account_id
  AND b.kind = 0
  AND b.status IN (0, 5, 7, 8)
  AND public.beacon_effective_admission(ci.beacon_id, p_account_id);
END;
$$
''',
]);
