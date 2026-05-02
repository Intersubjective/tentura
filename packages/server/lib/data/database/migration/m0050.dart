part of '_migrations.dart';

final m0050 = Migration('0050', [
  '''
ALTER TABLE public.person_capability_event
  ADD COLUMN is_negative boolean NOT NULL DEFAULT false;
''',
  '''
DROP INDEX IF EXISTS public.pce_private_label_uq;
''',
  '''
CREATE UNIQUE INDEX pce_private_label_uq
  ON public.person_capability_event(observer_user_id, subject_user_id, tag_slug)
  WHERE source_type = 0 AND is_negative = false AND deleted_at IS NULL;
''',
  '''
CREATE UNIQUE INDEX pce_tombstone_uq
  ON public.person_capability_event(observer_user_id, subject_user_id, tag_slug)
  WHERE is_negative = true AND deleted_at IS NULL;
''',
]);
