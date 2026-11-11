part of '_migrations.dart';

/// Preserve composer text through failed Post delivery, until the root commits.
final m0307 = Migration('0307', [
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
      AND (description = '' OR post_root_message_id IS NULL)
      AND cover_image_id IS NULL
    )
  )
''',
]);
