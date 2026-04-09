part of '_migrations.dart';

// 1) After commit withdraw on non-OPEN beacon: set tombstone immediately (not Watching).
// 2) 5→6: also fix stuck needs_me (0) when user had committed during earlier transitions.
final m0026 = Migration('0026', [
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_apply_tombstone_after_withdraw(
  p_user_id text,
  p_beacon_id text
) RETURNS void
  LANGUAGE plpgsql
  AS $$
BEGIN
  PERFORM set_config('tentura.allow_inbox_tombstone_transition', '1', true);
  UPDATE public.inbox_item ii
  SET
    status = CASE (SELECT b.state FROM public.beacon b WHERE b.id = p_beacon_id)
      WHEN 2 THEN 4 ELSE 3 END,
    before_response_terminal_at = coalesce(
      ii.before_response_terminal_at,
      now()
    )
  WHERE ii.user_id = p_user_id
    AND ii.beacon_id = p_beacon_id
    AND EXISTS (
      SELECT 1
      FROM public.beacon b
      WHERE b.id = p_beacon_id AND b.state <> 0
    );
END;
$$;
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
        FROM public.beacon_commitment bc
        WHERE bc.beacon_id = ii.beacon_id
          AND bc.user_id = ii.user_id
          AND bc.status = 1
      )
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
  r'''
DO $repair$
BEGIN
  PERFORM set_config('tentura.allow_inbox_tombstone_transition', '1', true);
  UPDATE public.inbox_item ii
  SET
    status = 3,
    before_response_terminal_at = coalesce(
      ii.before_response_terminal_at,
      now()
    )
  FROM public.beacon b
  WHERE b.id = ii.beacon_id
    AND b.state = 6
    AND ii.status IN (0, 1)
    AND EXISTS (
      SELECT 1
      FROM public.beacon_commitment bc
      WHERE bc.beacon_id = ii.beacon_id
        AND bc.user_id = ii.user_id
        AND bc.status = 1
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.beacon_commitment bc
      WHERE bc.beacon_id = ii.beacon_id
        AND bc.user_id = ii.user_id
        AND bc.status = 0
    );
END
$repair$;
''',
]);
