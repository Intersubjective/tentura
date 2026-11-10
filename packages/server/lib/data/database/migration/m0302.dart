part of '_migrations.dart';

/// The forward-row outcome tick records only a move INTO an outcome status
/// (#601-a follow-up). m0301 (which stays as shipped) recorded every status
/// change with a known actor, so the reopen revert 3 → 0 (m0246) and a
/// re-forward / re-invite putting a row back to pending 0 by another user
/// ticked the row. Status 0 is no outcome: such a change records nothing and
/// leaves the earlier `outcome_changed_at` / `outcome_changed_by` in place.
/// An outcome (1, 2, 3, 4) is recorded as before: with the acting user, or
/// with a NULL actor for 3 / 4, which only the Request's lifecycle or a
/// forward cancel writes.
final m0302 = Migration('0302', [
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_record_outcome_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  actor_id text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status OR NEW.status = 0 THEN
    RETURN NEW;
  END IF;
  actor_id := COALESCE(
    NULLIF(current_setting('tentura.mutating_user_id', true), ''),
    NULLIF(
      trim(NULLIF(current_setting('hasura.user', true), '')::jsonb
        ->> 'x-hasura-user-id'),
      ''
    )
  );
  IF actor_id IS NOT NULL OR NEW.status IN (3, 4) THEN
    NEW.outcome_changed_at := now();
    NEW.outcome_changed_by := actor_id;
  END IF;
  RETURN NEW;
END;
$$
''',
]);
