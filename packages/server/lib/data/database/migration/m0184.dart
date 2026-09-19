part of '_migrations.dart';

/// U09a step 3 — `attention_request_state` gets its first writer.
///
/// `outcome_generation` and `decision_revision` were added empty by m0178 and
/// read as `0/0` ever since. Undo (U09c) is defined against them: it restores
/// a member only if the outcome it dismissed is still *the same outcome* and
/// the viewer has not decided anything since. With nobody maintaining these
/// two counters, undo could not tell a restored `notInterested` or a fresh
/// forward generation from the state it captured, and would happily re-hide
/// a row the viewer had just brought back.
///
/// **Why a trigger and not a repository.** The viewer's stance is written from
/// more places than the Dart server owns: the client changes it through
/// Hasura (`update_inbox_item`, which is also how *Restore* works), the beacon
/// trigger from m0024 writes terminal statuses, and
/// `inbox_item_apply_tombstone_after_withdraw` writes from SQL.
/// `InboxRepository.setStatus` has no server-side caller at all. A Dart-level
/// writer would therefore miss exactly the transition undo cares about most.
/// The trigger sees every writer.
///
/// **What each counter means:**
///
/// * `decision_revision` — the viewer *decided* something: `status` changed,
///   or the `rejection_message` carried by that decision changed. Read by
///   U09c to refuse an undo whose stance moved underneath it, and by U09b to
///   skip a member whose Request was decided between capture and apply.
/// * `outcome_generation` — the identity of the *visible outcome row*
///   changed: every decision, plus a new forward generation
///   (`latest_forward_at` advancing, which replaces the outcome row's
///   content) and the arrival of a before-response terminal state. U09b
///   captures it per outcome member; U09c compares it before restoring; U10
///   reads it for the "uncleared outcome" predicate (D09).
/// * `first_entry_at` — lazily initialised here, on the viewer's first inbox
///   row for a Request, as the stable ordering anchor D08 needs. U10 owns the
///   sort keys; this only guarantees the column is populated.
///
/// **What deliberately does not bump:** `tombstone_dismissed_at`. Dismissal
/// and un-dismissal are presentation facts, not decisions — and if dismissing
/// bumped the generation, every sweep would invalidate its own undo.
///
/// Additive and restartable: `CREATE OR REPLACE FUNCTION`, a dropped-then-
/// created trigger, no backfill. Existing Requests acquire a state row on
/// their next inbox write; every reader already coalesces a missing row to
/// `0/0`.
final m0184 = Migration('0184', [
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_maintain_attention_request_state()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  decision_bump int := 0;
  outcome_bump int := 0;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.attention_request_state
      (account_id, beacon_id, first_entry_at, outcome_generation, decision_revision)
    VALUES (NEW.user_id, NEW.beacon_id, now(), 0, 0)
    ON CONFLICT (account_id, beacon_id) DO NOTHING;
    RETURN NULL;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     OR NEW.rejection_message IS DISTINCT FROM OLD.rejection_message THEN
    decision_bump := 1;
  END IF;

  outcome_bump := decision_bump;
  IF NEW.latest_forward_at IS DISTINCT FROM OLD.latest_forward_at
     OR NEW.before_response_terminal_at IS DISTINCT FROM OLD.before_response_terminal_at THEN
    outcome_bump := 1;
  END IF;

  IF decision_bump = 0 AND outcome_bump = 0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.attention_request_state
    (account_id, beacon_id, first_entry_at, outcome_generation, decision_revision)
  VALUES (NEW.user_id, NEW.beacon_id, now(), outcome_bump, decision_bump)
  ON CONFLICT (account_id, beacon_id) DO UPDATE SET
    outcome_generation =
      public.attention_request_state.outcome_generation + outcome_bump,
    decision_revision =
      public.attention_request_state.decision_revision + decision_bump;

  RETURN NULL;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS inbox_item_attention_request_state_trg ON public.inbox_item;
''',
  '''
CREATE TRIGGER inbox_item_attention_request_state_trg
  AFTER INSERT OR UPDATE ON public.inbox_item
  FOR EACH ROW EXECUTE FUNCTION public.inbox_item_maintain_attention_request_state();
''',
  '''
COMMENT ON COLUMN public.attention_request_state.outcome_generation IS
  'Identity of the viewer''s visible outcome row for this Request. Bumped by inbox_item_attention_request_state_trg on every decision, on a new forward generation, and on a before-response terminal state. Deliberately not bumped by tombstone_dismissed_at: a sweep must not invalidate its own undo. Captured per outcome member by the sweep (U09b) and compared before restoring (U09c).';
''',
  '''
COMMENT ON COLUMN public.attention_request_state.decision_revision IS
  'How many times the viewer decided something about this Request (status or rejection_message). Maintained by inbox_item_attention_request_state_trg, which is a trigger and not a repository because Hasura — including Restore — and the m0024 beacon trigger also write inbox_item. A mismatch means somebody decided between capture and apply, or between apply and undo: skip that member.';
''',
  '''
COMMENT ON COLUMN public.attention_request_state.first_entry_at IS
  'When this Request first entered the viewer''s attention, as the stable ordering anchor D08 needs. Lazily initialised by inbox_item_attention_request_state_trg on the first inbox row; U10 owns the sort keys themselves.';
''',
]);
