part of '_migrations.dart';

/// Post draft composer state (#1236 S1): lifetime hours and forward policy
/// persist on the beacon row until publish; `description` holds draft text.
final m0304 = Migration('0304', [
  '''
ALTER TABLE public.beacon
  ADD COLUMN post_lifetime_hours smallint
''',
  '''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_post_lifetime_hours_check
  CHECK (
    post_lifetime_hours IS NULL
    OR (
      kind = 1
      AND post_lifetime_hours >= 1
      AND post_lifetime_hours <= 72
    )
  )
''',
  '''
ALTER TABLE public.beacon
  DROP CONSTRAINT beacon_post_shape_ck
''',
  '''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_post_shape_ck CHECK (
    kind = 0
    OR (
      status IN (0, 2, 3, 6)
      AND is_discoverable = false
      AND parent_beacon_id IS NULL
      AND start_at IS NULL
      AND end_at IS NULL
      AND title = ''
      AND (description = '' OR status = 3)
      AND cover_image_id IS NULL
    )
  )
''',
]);
