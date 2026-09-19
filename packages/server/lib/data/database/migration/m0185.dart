part of '_migrations.dart';

/// U09a remediation — an unanswered forward may not be dismissed, and the
/// database is what says so.
///
/// m0183 was right to stop restricting `tombstone_dismissed_at` to statuses 3
/// and 4: every **answered** outcome kind — `helping`, `watching`,
/// `notInterested`, `closedBeforeResponse`, `deletedBeforeResponse` — carries
/// its own `×` and must be dismissible. Do not narrow it back to `IN (3, 4)`;
/// that was the original defect.
///
/// But widening it made one more thing legal at the row level: dismissing an
/// **unanswered** forward. `status = 0` is two different rows wearing one
/// number — `helping` when the viewer is in the Request's responsibility
/// scope, and "still waiting for your answer" when they are not (see the
/// `forward_outcome` CASE in `attention_repository.dart`). Only the second is
/// forbidden.
///
/// **Why this is a trigger and not just a predicate.** Owner decision A: the
/// sweep clears only rows that carry their own `×` and **never** anything
/// awaiting a decision, because hiding an unanswered forward silently
/// discards someone's request for help without answering them. After m0183
/// that guarantee lived only in `AttentionDismissibleSql`'s `eligible_pinned`
/// exclusion — a *read* predicate. Any permissive write path (a direct Hasura
/// `update_inbox_item`, a future caller that composes its own SQL) could set
/// the column anyway. A guarantee that depends on every caller remembering is
/// not a guarantee. Do **not** relax this back to "the sweep already filters
/// that": the sweep is one caller, and it is not the one this protects
/// against.
///
/// Un-dismissal (U09c undo, `tombstone_dismissed_at := NULL`) is untouched,
/// and so is every other write to an unanswered row — the rule fires only
/// when the column is being *set*.
final m0185 = Migration('0185', [
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_guard_unanswered_dismissal()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  answered boolean;
BEGIN
  IF NEW.tombstone_dismissed_at IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.tombstone_dismissed_at IS NOT DISTINCT FROM OLD.tombstone_dismissed_at THEN
    RETURN NEW;
  END IF;
  IF NEW.status <> 0 THEN
    RETURN NEW;
  END IF;

  -- status 0 is `helping` exactly when the Request is in the viewer's
  -- responsibility scope. This mirrors the `scope` CTE shared by
  -- `AttentionDismissibleSql.prelude` and `attention_repository.dart`: the
  -- base beacons (authored, or an open help offer) plus any Request carrying
  -- a live, unsettled obligation receipt for this viewer.
  SELECT EXISTS (
    SELECT 1
    FROM public.responsibility_scope_base_beacons(NEW.user_id) base
    WHERE base.beacon_id = NEW.beacon_id
  ) OR EXISTS (
    SELECT 1
    FROM public.visible_attention_receipts(NEW.user_id) authorized
    JOIN public.notification_outbox outbox
      ON outbox.id = authorized.receipt_id
    WHERE outbox.beacon_id = NEW.beacon_id
      AND outbox.requires_action
      AND outbox.settlement_kind IS NULL
  ) INTO answered;

  IF NOT answered THEN
    RAISE EXCEPTION
      'inbox_item unanswered forward cannot be dismissed (owner decision A: a row awaiting a decision never carries its own x)';
  END IF;

  RETURN NEW;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS inbox_item_guard_unanswered_dismissal
  ON public.inbox_item;
''',
  '''
CREATE TRIGGER inbox_item_guard_unanswered_dismissal
  BEFORE INSERT OR UPDATE ON public.inbox_item
  FOR EACH ROW
  EXECUTE FUNCTION public.inbox_item_guard_unanswered_dismissal();
''',
]);
