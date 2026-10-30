part of '_migrations.dart';

/// #747 — `visible_attention_receipts` authorized every receipt on its own:
/// `beacon_can_read_content` ran about twice per receipt, so a busy Request
/// paid for its whole history on every attention read
/// (AttentionLiveObligations slow, AttentionFeed 57014).
///
/// Visibility is a per-Request fact, so it is now evaluated once per distinct
/// Request in a materialized CTE and joined back to the receipts. The policy
/// itself (the `access_policy` CASE, the tombstone copy, in-app mutes) is
/// unchanged from m0193.
///
/// Two additions, which change the signature (drop and recreate):
/// * `receipt` returns the authorized `notification_outbox` row, so a reader
///   needing its columns does not read the table a second time by id.
/// * `p_live_obligations_only` narrows the candidates to live obligations
///   (`requires_action AND settlement_kind IS NULL`) before any visibility
///   work, so the live-obligations read authorizes only those Requests.
final m0277 = Migration('0277', [
  'DROP FUNCTION public.visible_attention_receipts(text)',
  r'''
CREATE FUNCTION public.visible_attention_receipts(
  p_account_id text,
  p_live_obligations_only boolean DEFAULT false
) RETURNS TABLE(
  receipt_id text,
  tombstone_copy boolean,
  receipt public.notification_outbox
)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH candidates AS (
  SELECT n.*, n AS receipt
  FROM public.notification_outbox n
  WHERE n.account_id = p_account_id
    AND (
      NOT p_live_obligations_only
      OR (n.requires_action AND n.settlement_kind IS NULL)
    )
),
beacon_access AS MATERIALIZED (
  SELECT
    candidate.beacon_id,
    public.beacon_can_read_content(candidate.beacon_id, p_account_id)
      AS can_read_content,
    public.beacon_can_read_tombstone(candidate.beacon_id, p_account_id)
      AS can_read_tombstone
  FROM (
    SELECT DISTINCT c.beacon_id
    FROM candidates c
    WHERE c.beacon_id IS NOT NULL
  ) candidate
)
SELECT
  c.id,
  c.beacon_id IS NOT NULL
    AND NOT a.can_read_content
    AND a.can_read_tombstone AS tombstone_copy,
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
$$
''',
]);
