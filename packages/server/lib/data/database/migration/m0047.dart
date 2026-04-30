part of '_migrations.dart';

/// One active fact per source room message; dedupe legacy rows.
final m0047 = Migration('0047', [
  '''
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY source_message_id
           ORDER BY created_at DESC
         ) AS rn
  FROM public.beacon_fact_card
  WHERE source_message_id IS NOT NULL
    AND status = 0
)
UPDATE public.beacon_fact_card c
SET status = 2,
    updated_at = now()
FROM ranked r
WHERE c.id = r.id
  AND r.rn > 1;
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS beacon_fact_card_unique_active_source_idx
  ON public.beacon_fact_card (source_message_id)
  WHERE status = 0
    AND source_message_id IS NOT NULL;
''',
]);
