part of '_migrations.dart';

// Inbox status enum + rejection cascade + beacon rejected_user_ids computed field.
final m0015 = Migration('0015', [
  // inbox_item: status (0=needs_me, 1=watching, 2=rejected) + optional message
  r'''
ALTER TABLE public.inbox_item
  ADD COLUMN IF NOT EXISTS status smallint DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS rejection_message text DEFAULT ''::text NOT NULL;
''',
  r'''
ALTER TABLE public.inbox_item
  DROP CONSTRAINT IF EXISTS ii_rejection_message_length;
''',
  r'''
ALTER TABLE public.inbox_item
  ADD CONSTRAINT ii_rejection_message_length
    CHECK (char_length(rejection_message) <= 200);
''',

  // beacon_forward_edge: denormalized rejection for forwarder / timeline visibility
  r'''
ALTER TABLE public.beacon_forward_edge
  ADD COLUMN IF NOT EXISTS recipient_rejected boolean DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS recipient_rejection_message text DEFAULT ''::text NOT NULL;
''',

  // Migrate booleans -> status (hidden wins over watching)
  r'''
UPDATE public.inbox_item SET status = 1 WHERE is_watching = true;
''',
  r'''
UPDATE public.inbox_item SET status = 2 WHERE is_hidden = true;
''',

  r'''
ALTER TABLE public.inbox_item
  DROP COLUMN IF EXISTS is_watching;
''',
  r'''
ALTER TABLE public.inbox_item
  DROP COLUMN IF EXISTS is_hidden;
''',

  r'''
DROP INDEX IF EXISTS ii_user_context_latest;
''',
  r'''
CREATE INDEX IF NOT EXISTS ii_user_context_status_latest
  ON public.inbox_item USING btree (user_id, context, status, latest_forward_at DESC);
''',

  // Backfill forward edges from inbox_item
  r'''
UPDATE public.beacon_forward_edge bfe
SET recipient_rejected = (ii.status = 2),
    recipient_rejection_message = CASE
      WHEN ii.status = 2 THEN ii.rejection_message
      ELSE ''::text
    END
FROM public.inbox_item ii
WHERE bfe.recipient_id = ii.user_id AND bfe.beacon_id = ii.beacon_id;
''',

  // Cascade inbox_item rejection to beacon_forward_edge
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_on_rejection_update()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF NEW.status = 2 THEN
    UPDATE public.beacon_forward_edge
    SET recipient_rejected = true,
        recipient_rejection_message = NEW.rejection_message
    WHERE recipient_id = NEW.user_id AND beacon_id = NEW.beacon_id;
  ELSIF OLD.status = 2 AND NEW.status <> 2 THEN
    UPDATE public.beacon_forward_edge
    SET recipient_rejected = false,
        recipient_rejection_message = ''::text
    WHERE recipient_id = NEW.user_id AND beacon_id = NEW.beacon_id;
  END IF;
  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS inbox_item_on_status_update ON public.inbox_item;
''',
  r'''
CREATE TRIGGER inbox_item_on_status_update
  AFTER UPDATE OF status, rejection_message ON public.inbox_item
  FOR EACH ROW EXECUTE FUNCTION public.inbox_item_on_rejection_update();
''',

  // Hasura computed field: user ids who rejected this beacon (for forward screen)
  r'''
CREATE OR REPLACE FUNCTION public.beacon_get_rejected_user_ids(
  beacon_row public.beacon,
  hasura_session json
) RETURNS SETOF text
  LANGUAGE sql
  STABLE
  AS $$
SELECT user_id
FROM public.inbox_item
WHERE beacon_id = beacon_row.id AND status = 2;
$$;
''',

  // --- Beacon lifecycle: backfill state from legacy enabled + keep DELETED (2).
  r'''
UPDATE public.beacon SET state = CASE
  WHEN state = 2 THEN 2
  WHEN enabled = true THEN 0
  ELSE 1
END;
''',
  r'''
ALTER TABLE public.beacon
  DROP CONSTRAINT IF EXISTS beacon_state_range;
''',
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_state_range
  CHECK (state >= 0 AND state <= 4);
''',

  // Keep `enabled` column in sync for legacy readers: "listed" when OPEN/DRAFT/PENDING_REVIEW.
  r'''
CREATE OR REPLACE FUNCTION public.beacon_sync_enabled_from_state()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  NEW.enabled := (NEW.state IN (0, 3, 4));
  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS beacon_set_enabled_from_state ON public.beacon;
''',
  r'''
CREATE TRIGGER beacon_set_enabled_from_state
  BEFORE INSERT OR UPDATE OF state ON public.beacon
  FOR EACH ROW EXECUTE FUNCTION public.beacon_sync_enabled_from_state();
''',

  // Inbox row provenance JSON for Hasura computed field `inbox_provenance_data` (type String / json).
  // Register in Hasura: inbox_item.inbox_provenance_data -> inbox_item_inbox_provenance_data
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_inbox_provenance_data(
  inbox_row public.inbox_item,
  hasura_session json
) RETURNS text
  LANGUAGE plpgsql
  STABLE
  AS $$
DECLARE
  viewer_id text := nullif(trim(hasura_session ->> 'x-hasura-user-id'), '');
  ctx text;
  result jsonb;
BEGIN
  IF viewer_id IS NULL THEN
    RETURN '{"senders":[],"totalDistinctSenders":0,"strongestNotePreview":""}';
  END IF;

  SELECT coalesce(
      nullif(trim(inbox_row.context), ''),
      nullif(trim(b.context), '')
    )
  INTO ctx
  FROM public.beacon b
  WHERE b.id = inbox_row.beacon_id;

  ctx := coalesce(ctx, '');

  WITH senders AS (
    SELECT DISTINCT ON (bfe.sender_id)
      bfe.sender_id,
      bfe.note,
      bfe.created_at
    FROM public.beacon_forward_edge bfe
    WHERE bfe.recipient_id = inbox_row.user_id
      AND bfe.beacon_id = inbox_row.beacon_id
      AND bfe.recipient_rejected = false
      AND (
        inbox_row.context IS NULL
        OR bfe.context IS NOT DISTINCT FROM inbox_row.context
      )
    ORDER BY bfe.sender_id, bfe.created_at DESC
  ),
  ms_raw AS (
    SELECT
      ms.src,
      ms.dst,
      ms.src_score::double precision AS src_score,
      ms.dst_score::double precision AS dst_score
    FROM mr_mutual_scores(viewer_id, ctx) ms
  ),
  ranked AS (
    SELECT
      s.sender_id,
      s.note AS last_note,
      coalesce(max(
        CASE
          WHEN m.src = viewer_id AND m.dst = s.sender_id THEN m.dst_score
          WHEN m.dst = viewer_id AND m.src = s.sender_id THEN m.src_score
          ELSE NULL::double precision
        END
      ), 0::double precision) AS mr
    FROM senders s
    LEFT JOIN ms_raw m ON (m.src = viewer_id AND m.dst = s.sender_id)
      OR (m.dst = viewer_id AND m.src = s.sender_id)
    GROUP BY s.sender_id, s.note
  ),
  top3 AS (
    SELECT sender_id, mr
    FROM ranked
    ORDER BY mr DESC, sender_id ASC
    LIMIT 3
  ),
  total AS (
    SELECT count(*)::int AS cnt FROM senders
  ),
  best AS (
    SELECT last_note
    FROM ranked
    ORDER BY mr DESC, sender_id ASC
    LIMIT 1
  ),
  top3_joined AS (
    SELECT
      t.sender_id,
      t.mr,
      coalesce(nullif(trim(u.title), ''), '') AS title,
      u.image_id::text AS image_id
    FROM top3 t
    JOIN public."user" u ON u.id = t.sender_id
  )
  SELECT jsonb_build_object(
    'senders', coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', sender_id,
            'title', title,
            'mr', mr,
            'imageId', image_id
          )
          ORDER BY mr DESC, sender_id ASC
        )
        FROM top3_joined
      ),
      '[]'::jsonb
    ),
    'totalDistinctSenders', (SELECT cnt FROM total),
    'strongestNotePreview', left(
      coalesce(nullif(trim((SELECT last_note FROM best)), ''), ''),
      200
    )
  )
  INTO result;

  RETURN result::text;
END;
$$;
''',
]);
