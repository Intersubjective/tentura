part of '_migrations.dart';

/// Request-only SQL exclusions (plan §4): a Post (`beacon.kind = 1`) is not in
/// the responsibility scope and gets no before-response inbox tombstones.
final m0213 = Migration('0213', [
  r'''
CREATE OR REPLACE FUNCTION public.responsibility_scope_base_beacons(p_account_id text) RETURNS TABLE(beacon_id text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT b.id
FROM public.beacon b
WHERE b.user_id = p_account_id
  AND b.kind = 0
  AND b.status <> 2
UNION
SELECT ho.beacon_id
FROM public.beacon_help_offer ho
INNER JOIN public.beacon b ON b.id = ho.beacon_id
WHERE ho.user_id = p_account_id
  AND ho.status = 0
  AND b.kind = 0
  AND b.status <> 2;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_apply_inbox_before_response_tombstone() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP <> 'UPDATE'
     OR NEW.kind <> 0
     OR NEW.status IS NOT DISTINCT FROM OLD.status THEN
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
$$
''',
]);
