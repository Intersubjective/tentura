part of '_migrations.dart';

/// Single beacon status: merge coordination_status into status, rename state->status.
final m0097 = Migration('0097', [
  // Drop m0091 CHECK before backfill: values 7/8 are not in (0,1,2,3,5,6).
  '''
ALTER TABLE public.beacon
  DROP CONSTRAINT IF EXISTS beacon_state_range;
''',
  // Backfill open-family substates from coordination_status before column drop.
  '''
UPDATE public.beacon
SET state = 7
WHERE state = 0 AND coordination_status = 2;
''',
  '''
UPDATE public.beacon
SET state = 8
WHERE state = 0 AND coordination_status = 3;
''',
  '''
ALTER TABLE public.beacon
  RENAME COLUMN state TO status;
''',
  '''
ALTER TABLE public.beacon
  RENAME COLUMN coordination_status_updated_at TO status_changed_at;
''',
  '''
ALTER TABLE public.beacon
  DROP COLUMN IF EXISTS coordination_status;
''',
  '''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_status_range
  CHECK (status IN (0, 1, 2, 3, 5, 6, 7, 8));
''',
  '''
COMMENT ON COLUMN public.beacon.status IS
  '0=open, 1=cancelled, 2=deleted, 3=draft, 5=reviewOpen, 6=closed, 7=needsMoreHelp, 8=enoughHelp';
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_apply_inbox_before_response_tombstone()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF TG_OP <> 'UPDATE' OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  PERFORM set_config('tentura.allow_inbox_tombstone_transition', '1', true);

  -- Open-family {0,7,8} -> terminal lifecycle (cancelled, reviewOpen, closed).
  IF NEW.status IN (1, 5, 6) AND OLD.status IN (0, 7, 8) THEN
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
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = ii.user_id
          AND ho.status = 0
      );
  END IF;

  IF NEW.status = 2 THEN
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
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = ii.user_id
          AND ho.status = 0
      );
  END IF;

  IF OLD.status = 5 AND NEW.status = 6 THEN
    UPDATE public.inbox_item ii
    SET
      status = 3,
      before_response_terminal_at = coalesce(
        ii.before_response_terminal_at,
        now()
      )
    WHERE ii.beacon_id = NEW.id
      AND ii.status IN (0, 1)
      AND EXISTS (
        SELECT 1
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = ii.user_id
          AND ho.status = 1
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = ii.user_id
          AND ho.status = 0
      );
  END IF;

  -- Reopen from Wrapping up (5 -> open-family): revert the open->5 tombstone.
  IF OLD.status = 5 AND NEW.status IN (0, 7, 8) THEN
    UPDATE public.inbox_item ii
    SET
      status = 0,
      before_response_terminal_at = NULL,
      tombstone_dismissed_at = NULL
    WHERE ii.beacon_id = NEW.id
      AND ii.status = 3
      AND NOT EXISTS (
        SELECT 1
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = ii.user_id
          AND ho.status = 0
      );
  END IF;

  RETURN NEW;
END;
$$;
''',
]);
