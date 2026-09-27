part of '_migrations.dart';

/// Fact-owned attachment snapshots on each revision (fact card image UX).
///
/// Attachments stop living only on the source room message: each revision
/// stores `attachments_json` (same shape as room `attachmentsJson`). Pin
/// copies the source message's attachments into seq 1; list/quote/restore
/// read the revision snapshot. Correct may change text and/or attachments.
final m0200 = Migration('0200', [
  r'''
ALTER TABLE public.beacon_fact_card_revision
  ADD COLUMN attachments_json jsonb NOT NULL DEFAULT '[]'::jsonb;
''',

  // Backfill every existing revision from the fact's current source message
  // attachments (best available snapshot; pre-0200 history did not version
  // attachments).
  r'''
UPDATE public.beacon_fact_card_revision r
SET attachments_json = COALESCE(src.attachments_json, '[]'::jsonb)
FROM (
  SELECT
    f.id AS fact_card_id,
    COALESCE(
      (
        SELECT jsonb_agg(item ORDER BY item->>'position')
        FROM (
          SELECT jsonb_build_object(
            'id', a.id,
            'kind', a.kind,
            'position', a.position,
            'mime', a.mime,
            'sizeBytes', a.size_bytes,
            'fileName', a.file_name,
            'imageId', COALESCE(i.id::text, ''),
            'imageAuthorId', COALESCE(i.author_id, ''),
            'blurHash', COALESCE(i.hash, ''),
            'width', COALESCE(i.width, 0),
            'height', COALESCE(i.height, 0)
          ) AS item
          FROM public.beacon_room_message_attachment a
          LEFT JOIN public.image i ON i.id = a.image_id
          WHERE a.message_id = f.source_message_id
        ) q
      ),
      '[]'::jsonb
    ) AS attachments_json
  FROM public.beacon_fact_card f
) src
WHERE r.fact_card_id = src.fact_card_id;
''',
]);
