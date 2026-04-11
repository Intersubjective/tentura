part of '_migrations.dart';

/// Introduces `beacon_image` join table for multi-image beacons.
///
/// 1. Creates `beacon_image` with composite PK `(beacon_id, image_id)` and
///    a `position` column that controls display order.
/// 2. Migrates existing `beacon.image_id` rows into `beacon_image` at position 0.
/// 3. Drops the now-redundant `beacon.image_id` column and its FK constraint.
final m0029 = Migration('0029', [
  '''
CREATE TABLE IF NOT EXISTS public.beacon_image (
  beacon_id TEXT NOT NULL,
  image_id  UUID NOT NULL,
  position  SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (beacon_id, image_id),
  CONSTRAINT beacon_image__beacon_id__fkey
    FOREIGN KEY (beacon_id) REFERENCES public.beacon(id)
    ON UPDATE RESTRICT ON DELETE CASCADE,
  CONSTRAINT beacon_image__image_id__fkey
    FOREIGN KEY (image_id) REFERENCES public.image(id)
    ON UPDATE RESTRICT ON DELETE CASCADE
);
''',

  '''
CREATE INDEX IF NOT EXISTS beacon_image__beacon_id__idx
  ON public.beacon_image (beacon_id);
''',

  'ALTER TABLE public."beacon" DISABLE TRIGGER ALL;',

  '''
INSERT INTO public.beacon_image (beacon_id, image_id, position)
  SELECT id, image_id, 0
    FROM public.beacon
    WHERE image_id IS NOT NULL
  ON CONFLICT DO NOTHING;
''',

  'ALTER TABLE public."beacon" ENABLE TRIGGER ALL;',

  '''
ALTER TABLE public."beacon"
  DROP CONSTRAINT IF EXISTS beacon__image_id__fkey;
''',

  '''
ALTER TABLE public."beacon"
  DROP COLUMN IF EXISTS image_id;
''',
]);
