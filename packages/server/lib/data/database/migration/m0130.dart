part of '_migrations.dart';

/// Additive cover/primary/media-stage columns and object-GC outbox.
///
/// Keeps legacy `icon_code` / `icon_background`. Contraction is m0131 (Step 10).
final m0130 = Migration('0130', [
  r'''
ALTER TABLE public.beacon
  ADD COLUMN primary_need_slug TEXT NULL,
  ADD COLUMN cover_image_id UUID NULL,
  ADD COLUMN cover_source SMALLINT NOT NULL DEFAULT 0,
  ADD CONSTRAINT beacon_cover_source_ck CHECK (cover_source IN (0, 1));
''',
  r'''
UPDATE public.beacon AS b
SET primary_need_slug = (
  SELECT canonical.slug
  FROM (VALUES
    ('transport',1),('storage',2),('pickup_delivery',3),('tools',4),
    ('physical_help',5),('calls',6),('translation',7),('writing',8),
    ('negotiation',9),('introductions',10),('local_knowledge',11),
    ('legal_navigation',12),('medical_navigation',13),('documents',14),
    ('verification',15),('pets',16),('childcare',17),('eldercare',18),
    ('emotional_support',19),('hosting',20),('money',21),('food',22),
    ('housing',23),('equipment',24),('workspace',25),('tech_help',26),
    ('repair',27),('manual_work',28),('software',29),('design',30),
    ('admin_paperwork',31),('time',32),('contact',33),('orders',34),
    ('gig',35),('job',36),('other',37)
  ) AS canonical(slug, ord)
  WHERE canonical.slug =
      ANY (regexp_split_to_array(b.needs, '\s*,\s*'))
  ORDER BY canonical.ord
  LIMIT 1
)
WHERE b.needs <> '';
''',
  r'''
WITH ranked AS (
  SELECT beacon_id,
         image_id,
         (row_number() OVER (
           PARTITION BY beacon_id ORDER BY position, image_id
         ) - 1)::integer AS new_position
  FROM public.beacon_image
)
UPDATE public.beacon_image AS bi
SET position = ranked.new_position
FROM ranked
WHERE bi.beacon_id = ranked.beacon_id
  AND bi.image_id = ranked.image_id;
''',
  r'''
ALTER TABLE public.beacon_image
  ADD CONSTRAINT beacon_image_position_uq
    UNIQUE (beacon_id, position) DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT beacon_image_image_id_uq UNIQUE (image_id);
''',
  r'''
UPDATE public.beacon AS b
SET cover_image_id = (
  SELECT bi.image_id
  FROM public.beacon_image AS bi
  WHERE bi.beacon_id = b.id
  ORDER BY bi.position, bi.image_id
  LIMIT 1
)
WHERE b.cover_image_id IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.beacon_image AS bi
    WHERE bi.beacon_id = b.id
  );
''',
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_cover_image_membership_fk
  FOREIGN KEY (id, cover_image_id)
  REFERENCES public.beacon_image (beacon_id, image_id)
  ON DELETE SET NULL (cover_image_id);
''',
  r'''
CREATE INDEX beacon_cover_image_id_idx
  ON public.beacon (cover_image_id)
  WHERE cover_image_id IS NOT NULL;
''',
  r'''
CREATE TABLE public.beacon_image_stage (
  image_id UUID PRIMARY KEY
    REFERENCES public.image(id) ON DELETE CASCADE,
  beacon_id TEXT NOT NULL
    REFERENCES public.beacon(id) ON DELETE CASCADE,
  staged_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
''',
  r'''
CREATE INDEX beacon_image_stage_expiry_idx
  ON public.beacon_image_stage (staged_at, beacon_id);
''',
  r'''
CREATE TABLE public.image_object_gc (
  image_id UUID PRIMARY KEY,
  author_id TEXT NOT NULL,
  enqueued_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT NULL,
  lease_owner TEXT NULL,
  lease_until TIMESTAMPTZ NULL
);
''',
  r'''
CREATE INDEX image_object_gc_claim_idx
  ON public.image_object_gc (next_attempt_at, lease_until, enqueued_at)
  WHERE attempts < 10;
''',
]);
