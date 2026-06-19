part of '_migrations.dart';

/// Backfill `beaconPublished` (type 15) activity events for beacons published
/// before the V2 `beaconPublish` mutation existed.
final m0089 = Migration('0089', [
  r'''
INSERT INTO public.beacon_activity_event (
  id,
  beacon_id,
  visibility,
  type,
  actor_id,
  diff,
  created_at
)
SELECT
  concat('V', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  b.id,
  0,
  15,
  b.user_id,
  jsonb_strip_nulls(
    jsonb_build_object(
      'title', NULLIF(trim(b.title), ''),
      'needSummary', NULLIF(trim(b.need_summary), '')
    )
  ),
  b.created_at
FROM public.beacon b
WHERE b.state NOT IN (2, 3)
  AND NOT EXISTS (
    SELECT 1
    FROM public.beacon_activity_event e
    WHERE e.beacon_id = b.id
      AND e.type = 15
  );
''',
]);
