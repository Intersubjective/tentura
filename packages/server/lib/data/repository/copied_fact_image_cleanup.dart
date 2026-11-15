/// CTE list for discarding the duplicated images of copied facts (facts with
/// an origin) when a draft loses them. Selects the images in the head
/// revision of every fact matching [factFilter] (SQL over alias `f`) that
/// [actorParam] authored, queues their objects for GC and deletes their rows.
/// An ordinary fact's images are shared with room messages and stay.
String copiedFactImageCleanupCtes({
  required String factFilter,
  required String actorParam,
}) =>
    '''
copied_images AS (
  SELECT DISTINCT (e.value->>'imageId')::uuid AS image_id
  FROM public.beacon_fact_card f
  JOIN public.beacon_fact_card_revision r
    ON r.fact_card_id = f.id AND r.seq = f.revision_seq
  CROSS JOIN LATERAL jsonb_array_elements(r.attachments_json) e
  WHERE f.origin_fact_card_id IS NOT NULL
    AND ($factFilter)
    AND e.value->>'imageId' ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$'
    AND e.value->>'imageAuthorId' = $actorParam::text
),
copied_images_gc AS (
  INSERT INTO public.image_object_gc (image_id, author_id)
  SELECT image_id, $actorParam::text FROM copied_images
  ON CONFLICT (image_id) DO NOTHING
  RETURNING image_id
),
copied_images_purge AS (
  DELETE FROM public.image i
  USING copied_images c
  WHERE i.id = c.image_id AND i.author_id = $actorParam::text
  RETURNING i.id
)
''';

/// CTE `copied_files(file_key)`: the storage keys of the file objects owned
/// by copied facts (facts with an origin) matching [factFilter] (SQL over
/// alias `f`), from their head revisions. A copy owns every `fileKey` entry
/// it holds; the caller removes those objects after its delete committed.
String copiedFactFilesCte({required String factFilter}) =>
    '''
copied_files AS (
  SELECT DISTINCT e.value->>'fileKey' AS file_key
  FROM public.beacon_fact_card f
  JOIN public.beacon_fact_card_revision r
    ON r.fact_card_id = f.id AND r.seq = f.revision_seq
  CROSS JOIN LATERAL jsonb_array_elements(r.attachments_json) e
  WHERE f.origin_fact_card_id IS NOT NULL
    AND ($factFilter)
    AND (e.value->>'kind')::int = 2
    AND COALESCE(e.value->>'fileKey', '') <> ''
)
''';
