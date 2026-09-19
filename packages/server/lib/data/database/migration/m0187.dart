part of '_migrations.dart';

/// U10c step 1 — `first_entry_at` becomes an *entry* time, not a write time.
///
/// D08 asks ordering to be stable: a Request entering a surface establishes
/// its place then and keeps it. U09a gave the column its first writer, which
/// stamped `now()` — the moment the `inbox_item` row happened to be written.
/// For the live path those two are the same instant. For anything that writes
/// history — a fixture, an import, a backfill, a forward replayed out of
/// order — they are not, and the anchor ends up ordering Requests by when the
/// database noticed them instead of by when they arrived.
///
/// So the insert now stamps `LEAST(now(), NEW.latest_forward_at)`: the
/// earliest evidence we have that this Request entered the viewer's
/// attention. `LEAST` and not the forward time alone, because an
/// `inbox_item` can be created without a forward (`latest_forward_at` is
/// nullable), and because an anchor must never be in the future.
///
/// The `ON CONFLICT DO NOTHING` is what keeps it stable afterwards: a
/// re-forward bumps `latest_forward_at` and never touches the anchor, which
/// is exactly D08's "a repeated forward does not reorder an existing pinned
/// card".
///
/// **Backfill, unlike m0184.** Two holes are closed here rather than left for
/// the read path to paper over, because the read path's fallback
/// (`latest_forward_at`) is only correct while nobody has re-forwarded:
///
/// 1. `inbox_item` rows that predate m0184 have no state row at all.
/// 2. State rows written by m0184 carry the write instant.
///
/// Both are repaired from `inbox_item.latest_forward_at`, and only ever
/// downwards (`LEAST`), so re-running the migration cannot walk an anchor
/// forward.
final m0187 = Migration('0187', [
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
    VALUES (
      NEW.user_id,
      NEW.beacon_id,
      LEAST(now(), COALESCE(NEW.latest_forward_at, now())),
      0,
      0
    )
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
  VALUES (
    NEW.user_id,
    NEW.beacon_id,
    LEAST(now(), COALESCE(NEW.latest_forward_at, now())),
    outcome_bump,
    decision_bump
  )
  ON CONFLICT (account_id, beacon_id) DO UPDATE SET
    outcome_generation =
      public.attention_request_state.outcome_generation + outcome_bump,
    decision_revision =
      public.attention_request_state.decision_revision + decision_bump;

  RETURN NULL;
END;
$$;
''',

  // Hole 1 — inbox rows with no state row at all.
  '''
INSERT INTO public.attention_request_state
  (account_id, beacon_id, first_entry_at, outcome_generation, decision_revision)
SELECT
  ii.user_id,
  ii.beacon_id,
  LEAST(now(), COALESCE(ii.latest_forward_at, now())),
  0,
  0
FROM public.inbox_item ii
ON CONFLICT (account_id, beacon_id) DO NOTHING;
''',

  // Hole 2 — state rows anchored at their write instant.
  '''
UPDATE public.attention_request_state state
SET first_entry_at = LEAST(state.first_entry_at, ii.latest_forward_at)
FROM public.inbox_item ii
WHERE ii.user_id = state.account_id
  AND ii.beacon_id = state.beacon_id
  AND ii.latest_forward_at IS NOT NULL
  AND ii.latest_forward_at < state.first_entry_at;
''',

  '''
COMMENT ON COLUMN public.attention_request_state.first_entry_at IS
  'When this Request entered the viewer''s attention, as the stable ordering anchor D08 needs: LEAST(now(), latest_forward_at) at the first inbox row, never bumped afterwards, so a re-forward does not reorder an existing pinned card. U10c orders the For-you pinned zone and the grouped forward rows by it, falling back to latest_forward_at where no row exists.';
''',
]);
