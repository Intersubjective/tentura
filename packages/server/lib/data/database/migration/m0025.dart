part of '_migrations.dart';

// Tombstone for post-withdraw "watching": commit→withdraw uses upsertWatchingForSender,
// so inbox is status=1 when beacon goes closedReviewOpen(5)→closedReviewComplete(6).
// Explicit watchers (no beacon_commitment row) keep Watching per watching-mechanism doc.
final m0025 = Migration('0025', [
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
      AND ii.status = 1
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
]);
