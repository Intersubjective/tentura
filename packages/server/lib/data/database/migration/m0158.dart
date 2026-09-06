part of '_migrations.dart';

/// Irreversible legacy ask/promise/blocker + non-General thread cleanup (Task 09).
///
/// Deployment gate (not executed by this migration): capture a verified backup as
/// `tentura-nested-cleanup-<UTC-ISO8601>-<source-db>` before maintenance; rollback
/// is full restore + matching application versions, never a down-migration.
///
/// Idempotent in shape: [nested_requests_apply_legacy_cleanup] may be invoked again
/// after a successful run; subsequent passes delete/update zero rows.
final m0158 = Migration('0158', [
  r'''
CREATE OR REPLACE FUNCTION public.nested_requests_apply_legacy_cleanup()
  RETURNS void
  LANGUAGE plpgsql
  AS $$
BEGIN
  -- §5.3 step 2 — snapshot doomed sets (transaction-local).
  CREATE TEMP TABLE m0158_doomed_items ON COMMIT DROP AS
    SELECT id
    FROM public.coordination_item
    WHERE kind IN (2, 3, 5);

  CREATE TEMP TABLE m0158_doomed_messages ON COMMIT DROP AS
    SELECT id
    FROM public.beacon_room_message
    WHERE thread_item_id IS NOT NULL;

  CREATE TEMP TABLE m0158_doomed_attachment_images ON COMMIT DROP AS
    SELECT DISTINCT a.image_id, i.author_id
    FROM public.beacon_room_message_attachment a
    INNER JOIN public.image i ON i.id = a.image_id
    INNER JOIN m0158_doomed_messages dm ON dm.id = a.message_id
    WHERE a.image_id IS NOT NULL;

  CREATE TEMP TABLE m0158_affected_receipts ON COMMIT DROP AS
    SELECT n.id, n.occurrence_id
    FROM public.notification_outbox n
    WHERE n.coordination_item_id IN (SELECT id FROM m0158_doomed_items)
       OR n.target_entity_id IN (SELECT id FROM m0158_doomed_messages)
       OR COALESCE(n.presentation_payload ->> 'coordinationItemId', '')
            IN (SELECT id FROM m0158_doomed_items)
       OR COALESCE(n.presentation_payload ->> 'messageId', '')
            IN (SELECT id FROM m0158_doomed_messages);

  CREATE TEMP TABLE m0158_affected_occurrences ON COMMIT DROP AS
    SELECT DISTINCT occ.id
    FROM public.attention_occurrence occ
    WHERE occ.id IN (
      SELECT occurrence_id FROM m0158_affected_receipts WHERE occurrence_id IS NOT NULL
    );

  -- §5.3 step 3 — preserve supported rows; null dangling provenance only.
  UPDATE public.beacon_fact_card
  SET source_message_id = NULL
  WHERE source_message_id IN (SELECT id FROM m0158_doomed_messages);

  UPDATE public.beacon_promotions
  SET source_message_id = NULL
  WHERE source_message_id IN (SELECT id FROM m0158_doomed_messages);

  UPDATE public.coordination_item ci
  SET target_item_id = NULL
  WHERE ci.target_item_id IN (SELECT id FROM m0158_doomed_items);

  UPDATE public.coordination_item ci
  SET linked_message_id = NULL
  WHERE ci.linked_message_id IN (SELECT id FROM m0158_doomed_messages);

  UPDATE public.coordination_item ci
  SET target_message_id = NULL
  WHERE ci.target_message_id IN (SELECT id FROM m0158_doomed_messages);

  UPDATE public.beacon_room_message m
  SET reply_to_message_id = NULL
  WHERE m.reply_to_message_id IN (SELECT id FROM m0158_doomed_messages)
    AND m.id NOT IN (SELECT id FROM m0158_doomed_messages);

  -- §5.3 step 4 — remove obsolete General anchors; clear retired links on survivors.
  DELETE FROM public.beacon_room_message m
  WHERE m.thread_item_id IS NULL
    AND m.linked_item_id IN (SELECT id FROM m0158_doomed_items)
    AND m.linked_event_kind IS NOT NULL;

  UPDATE public.beacon_room_message m
  SET
    linked_item_id = NULL,
    linked_event_kind = NULL,
    system_payload = NULL
  WHERE m.thread_item_id IS NULL
    AND m.linked_item_id IN (SELECT id FROM m0158_doomed_items);

  UPDATE public.beacon_room_state rs
  SET open_blocker_id = NULL
  WHERE rs.open_blocker_id IN (SELECT id FROM m0158_doomed_items);

  -- §5.3 step 5 — attention / destinations in verified FK order.
  DELETE FROM public.beacon_activity_event e
  WHERE e.coordination_item_id IN (SELECT id FROM m0158_doomed_items)
     OR e.source_message_id IN (SELECT id FROM m0158_doomed_messages);

  DELETE FROM public.attention_channel_delivery d
  WHERE d.receipt_id IN (SELECT id FROM m0158_affected_receipts)
     OR d.occurrence_id IN (SELECT id FROM m0158_affected_occurrences);

  DELETE FROM public.notification_outbox n
  WHERE n.id IN (SELECT id FROM m0158_affected_receipts);

  DELETE FROM public.attention_occurrence_recipient r
  WHERE r.occurrence_id IN (SELECT id FROM m0158_affected_occurrences);

  DELETE FROM public.attention_occurrence o
  WHERE o.id IN (SELECT id FROM m0158_affected_occurrences);

  -- §5.3 step 6 — room-owned polls, then semantic messages, then retired items.
  CREATE TEMP TABLE m0158_doomed_polls ON COMMIT DROP AS
    SELECT DISTINCT m.linked_polling_id AS id
    FROM public.beacon_room_message m
    WHERE m.id IN (SELECT id FROM m0158_doomed_messages)
      AND m.linked_polling_id IS NOT NULL;

  DELETE FROM public.polling_act pa
  WHERE pa.polling_id IN (SELECT id FROM m0158_doomed_polls);

  DELETE FROM public.polling_variant pv
  WHERE pv.polling_id IN (SELECT id FROM m0158_doomed_polls);

  DELETE FROM public.polling p
  WHERE p.id IN (SELECT id FROM m0158_doomed_polls);

  DELETE FROM public.beacon_room_message m
  WHERE m.id IN (SELECT id FROM m0158_doomed_messages);

  DELETE FROM public.beacon_room_seen s
  WHERE s.thread_item_id IS NOT NULL;

  DELETE FROM public.coordination_item ci
  WHERE ci.id IN (SELECT id FROM m0158_doomed_items);

  -- §5.3 step 7 — queue then drop unreferenced attachment blobs (DB only).
  INSERT INTO public.image_object_gc (image_id, author_id)
  SELECT dai.image_id, dai.author_id
  FROM m0158_doomed_attachment_images dai
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.beacon_room_message_attachment att
    WHERE att.image_id = dai.image_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_image bi WHERE bi.image_id = dai.image_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon b
    WHERE b.cover_image_id = dai.image_id
       OR b.cover_thumb_image_id = dai.image_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_image_stage s WHERE s.image_id = dai.image_id
  )
  ON CONFLICT (image_id) DO NOTHING;

  DELETE FROM public.image i
  USING m0158_doomed_attachment_images dai
  WHERE i.id = dai.image_id
    AND EXISTS (
      SELECT 1 FROM public.image_object_gc gc WHERE gc.image_id = dai.image_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.beacon_room_message_attachment att
      WHERE att.image_id = dai.image_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.beacon_image bi WHERE bi.image_id = dai.image_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.beacon b
      WHERE b.cover_image_id = dai.image_id
         OR b.cover_thumb_image_id = dai.image_id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.beacon_image_stage s WHERE s.image_id = dai.image_id
    );

  -- §5.3 step 8 — rebuild only affected preview pointers from remaining data.
  UPDATE public.beacon_room_state rs
  SET last_room_meaningful_change = NULL
  WHERE rs.last_room_meaningful_change IN (SELECT id FROM m0158_doomed_messages);

  UPDATE public.beacon_room_message m
  SET linked_polling_id = NULL
  WHERE m.linked_polling_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.polling p WHERE p.id = m.linked_polling_id
    );
END;
$$;
''',
  r'''
SELECT public.nested_requests_apply_legacy_cleanup();
''',
]);
