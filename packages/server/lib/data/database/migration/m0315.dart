part of '_migrations.dart';

/// Settles live «new help offer» obligations left behind by offers admitted
/// before the author-side settle existed, and by withdrawn or missing offers.
/// Only history after the helper's latest offer counts, so a re-offer stays
/// live. Frozen copy of the rule reconcile uses; a rerun changes nothing.
final m0315 = Migration('0315', [
  '''
WITH live AS (
  SELECT outbox.id, outbox.beacon_id, outbox.target_entity_id
  FROM public.notification_outbox AS outbox
  JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
  WHERE occ.event_type = 'helpOfferSubmitted'
    AND outbox.requires_action
    AND outbox.settlement_kind IS NULL
    AND outbox.logical_task_key IS NOT NULL
),
judged AS (
  SELECT
    live.id,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM public.beacon_commitment_event AS ce
        WHERE ce.beacon_id = live.beacon_id
          AND ce.user_id = live.target_entity_id
          AND ce.kind IN (3, 5, 7)
          AND ce.seq > COALESCE((
            SELECT max(offered.seq)
            FROM public.beacon_commitment_event AS offered
            WHERE offered.beacon_id = live.beacon_id
              AND offered.user_id = live.target_entity_id
              AND offered.kind = 0
          ), 0)
      ) THEN 'superseded'
      WHEN offer.user_id IS NULL THEN 'superseded'
      WHEN offer.withdraw_reason IS NOT NULL THEN 'superseded'
      WHEN b.status IN (1, 2, 6) THEN 'superseded'
      WHEN EXISTS (
        SELECT 1 FROM public.beacon_commitment_event AS ce
        WHERE ce.beacon_id = live.beacon_id
          AND ce.user_id = live.target_entity_id
          AND ce.kind IN (1, 2, 4)
          AND ce.seq > COALESCE((
            SELECT max(offered.seq)
            FROM public.beacon_commitment_event AS offered
            WHERE offered.beacon_id = live.beacon_id
              AND offered.user_id = live.target_entity_id
              AND offered.kind = 0
          ), 0)
      ) THEN 'resolved'
      WHEN offer.status <> 0 THEN 'resolved'
      ELSE NULL
    END AS settlement
  FROM live
  JOIN public.beacon AS b ON b.id = live.beacon_id
  LEFT JOIN public.beacon_help_offer AS offer
    ON offer.beacon_id = live.beacon_id
   AND offer.user_id = live.target_entity_id
)
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = judged.settlement,
  settled_at = now(),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL
FROM judged
WHERE outbox.id = judged.id
  AND judged.settlement IS NOT NULL
  AND outbox.settlement_kind IS NULL
''',
]);
