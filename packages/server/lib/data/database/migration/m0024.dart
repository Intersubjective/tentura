part of '_migrations.dart';

// Before-response tombstone: inbox_item.status 3/4, terminal timestamps, dismiss,
// beacon trigger + guards against client-forged tombstone status changes.
final m0024 = Migration('0024', [
  '''
ALTER TABLE public.inbox_item
  ADD COLUMN IF NOT EXISTS before_response_terminal_at timestamptz,
  ADD COLUMN IF NOT EXISTS tombstone_dismissed_at timestamptz;
''',
  '''
COMMENT ON COLUMN public.inbox_item.status IS
  '0=needs_me,1=watching,2=rejected,3=closed_before_response,4=deleted_before_response';
''',
  '''
COMMENT ON COLUMN public.inbox_item.before_response_terminal_at IS
  'When the row first entered a before-response terminal status (3 or 4)';
''',
  '''
COMMENT ON COLUMN public.inbox_item.tombstone_dismissed_at IS
  'When set, client hides passive tombstone card; does not change stance';
''',
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_guard_tombstone()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  allow text;
BEGIN
  allow := current_setting('tentura.allow_inbox_tombstone_transition', true);
  IF TG_OP = 'INSERT' AND NEW.status IN (3, 4) THEN
    IF allow IS DISTINCT FROM '1' THEN
      RAISE EXCEPTION 'inbox_item cannot insert tombstone status without beacon trigger';
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status IN (3, 4) THEN
      IF NEW.status IS DISTINCT FROM OLD.status
         OR NEW.rejection_message IS DISTINCT FROM OLD.rejection_message THEN
        RAISE EXCEPTION 'inbox_item tombstone rows cannot change status or rejection_message';
      END IF;
    END IF;
    IF NEW.tombstone_dismissed_at IS DISTINCT FROM OLD.tombstone_dismissed_at THEN
      IF NEW.status NOT IN (3, 4) THEN
        RAISE EXCEPTION 'tombstone_dismissed_at only when inbox_item is a tombstone';
      END IF;
    END IF;
    IF NEW.status IN (3, 4) AND OLD.status NOT IN (3, 4) THEN
      IF allow IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'inbox_item cannot transition to tombstone status without beacon trigger';
      END IF;
    END IF;
    IF OLD.status IN (3, 4) AND NEW.status IN (3, 4)
       AND OLD.status IS DISTINCT FROM NEW.status THEN
      IF allow IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'inbox_item tombstone status upgrade requires beacon trigger';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS inbox_item_guard_tombstone_trg ON public.inbox_item;
''',
  '''
CREATE TRIGGER inbox_item_guard_tombstone_trg
  BEFORE INSERT OR UPDATE ON public.inbox_item
  FOR EACH ROW EXECUTE FUNCTION public.inbox_item_guard_tombstone();
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_apply_inbox_before_response_tombstone()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF TG_OP <> 'UPDATE' OR NEW.state IS NOT DISTINCT FROM OLD.state THEN
    RETURN NEW;
  END IF;

  PERFORM set_config('tentura.allow_inbox_tombstone_transition', '1', true);

  IF NEW.state IN (1, 5, 6) AND OLD.state = 0 THEN
    UPDATE public.inbox_item ii
    SET
      status = 3,
      before_response_terminal_at = coalesce(
        ii.before_response_terminal_at,
        now()
      )
    WHERE ii.beacon_id = NEW.id
      AND ii.status = 0
      AND NOT EXISTS (
        SELECT 1
        FROM public.beacon_commitment bc
        WHERE bc.beacon_id = ii.beacon_id
          AND bc.user_id = ii.user_id
          AND bc.status = 0
      );
  END IF;

  IF NEW.state = 2 THEN
    UPDATE public.inbox_item ii
    SET
      status = 4,
      before_response_terminal_at = coalesce(
        ii.before_response_terminal_at,
        now()
      )
    WHERE ii.beacon_id = NEW.id
      AND ii.status IN (0, 3)
      AND NOT EXISTS (
        SELECT 1
        FROM public.beacon_commitment bc
        WHERE bc.beacon_id = ii.beacon_id
          AND bc.user_id = ii.user_id
          AND bc.status = 0
      );
  END IF;

  RETURN NEW;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS beacon_apply_inbox_tombstone_trg ON public.beacon;
''',
  '''
CREATE TRIGGER beacon_apply_inbox_tombstone_trg
  AFTER UPDATE OF state ON public.beacon
  FOR EACH ROW EXECUTE FUNCTION public.beacon_apply_inbox_before_response_tombstone();
''',
  '''
CREATE INDEX IF NOT EXISTS ii_user_tombstone_visible
  ON public.inbox_item (user_id, before_response_terminal_at DESC)
  WHERE status IN (3, 4) AND tombstone_dismissed_at IS NULL;
''',
]);
