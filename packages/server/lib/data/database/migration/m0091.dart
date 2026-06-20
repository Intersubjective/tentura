part of '_migrations.dart';

/// Beacon lifecycle redesign: coerce legacy states, tighten CHECK, extensions_used,
/// beacon_archived table, m0071 reopen (5→0) tombstone revert.
final m0091 = Migration('0091', [
  // Data coercion BEFORE CHECK swap (state 4 forbidden; state 1 = old CLOSED → 6).
  r'''
UPDATE public.beacon SET state = 6 WHERE state = 4;
''',
  r'''
UPDATE public.beacon SET state = 6 WHERE state = 1;
''',
  r'''
ALTER TABLE public.beacon
  DROP CONSTRAINT IF EXISTS beacon_state_range;
''',
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_state_range
  CHECK (state IN (0, 1, 2, 3, 5, 6));
''',
  r'''
ALTER TABLE public.beacon_review_window
  ADD COLUMN IF NOT EXISTS extensions_used integer NOT NULL DEFAULT 0;
''',
  r'''
CREATE TABLE public.beacon_archived (
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  archived_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, beacon_id)
);
''',
  r'''
CREATE INDEX idx_beacon_archived_user_id
  ON public.beacon_archived(user_id);
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
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = ii.user_id
          AND ho.status = 0
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
        FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = ii.beacon_id
          AND ho.user_id = ii.user_id
          AND ho.status = 0
      );
  END IF;

  IF OLD.state = 5 AND NEW.state = 6 THEN
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

  -- Reopen from Wrapping up (5→0): revert the 0→5 tombstone for non-responders.
  IF OLD.state = 5 AND NEW.state = 0 THEN
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
