part of '_migrations.dart';

/// The forward-row outcome tick (#601-a).
///
/// A forward row on Activity is synthetic (`inbox:<beaconId>`) and had no
/// read marker of its own. When somebody other than the recipient relabels
/// it to an outcome (the author closing or deleting the Request before the
/// recipient answered), the row moves up to the relabel and carries one
/// unread tick until the recipient marks it seen. The recipient's own
/// decisions never tick.
///
/// * `outcome_changed_at` / `outcome_changed_by` — written by a trigger on
///   every status change, so every relabel path (repositories, the beacon
///   lifecycle trigger, Hasura's `InboxSetStatus`) records it. The actor is
///   the server's `tentura.mutating_user_id`, else Hasura's session user.
///   A change with no known actor is not attributable and records nothing,
///   except a move to 3/4 (closed / deleted before the recipient answered):
///   only the Request's lifecycle or a forward cancel writes those, never
///   the recipient, so it is recorded with a NULL actor ("not the
///   recipient").
/// * `outcome_seen_at` — written by `markSeen` for an `inbox:<beaconId>` id.
///
/// Existing rows are not backfilled: no relabel is known for them.
final m0301 = Migration('0301', [
  '''
ALTER TABLE public.inbox_item
  ADD COLUMN outcome_changed_at timestamptz,
  ADD COLUMN outcome_changed_by text,
  ADD COLUMN outcome_seen_at timestamptz
''',
  r'''
CREATE FUNCTION public.inbox_item_record_outcome_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  actor_id text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
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
  '''
CREATE TRIGGER inbox_item_record_outcome_change_trg
  BEFORE UPDATE OF status ON public.inbox_item
  FOR EACH ROW EXECUTE FUNCTION public.inbox_item_record_outcome_change()
''',
]);
