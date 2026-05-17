part of '_migrations.dart';

/// m0063 renamed `beacon_commitment` → `beacon_help_offer` but left
/// `beacon_apply_inbox_before_response_tombstone` on the old table name.
/// Closing a beacon (state 0→5) fires that trigger and failed with 42P01.
final m0071 = Migration('0071', [
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

  RETURN NEW;
END;
$$;
''',
]);
