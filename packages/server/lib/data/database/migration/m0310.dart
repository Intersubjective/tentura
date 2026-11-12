part of '_migrations.dart';

/// `visible_attention_receipts` (m0303) computed `surely_readable` as NULL for
/// a Request with no author (`beacon.user_id` is `ON DELETE SET NULL`) when
/// the viewer had no forward edge: `NOT surely_readable` was then NULL too, so
/// the Request never reached `beacon_readable_ids` and read as unreadable for
/// participants, stewards and helpers the content wall admits. The expression
/// is wrapped in `COALESCE(..., false)`; the body is otherwise m0303's,
/// frozen here for deterministic replay. m0303 itself stays as shipped.
final m0310 = Migration('0310', [
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
    COALESCE(
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
        AND NOT public.block_hides(b.user_id, p_account_id),
      false
    ) AS surely_readable
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
]);
