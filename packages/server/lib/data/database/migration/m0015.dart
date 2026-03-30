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
]);
