part of '_migrations.dart';

/// Additive storage for the request-centric attention model
/// (implementation manifest §0.1): optional-clear state, obligation identity,
/// per-viewer Request state, and sweep-operation bookkeeping.
///
/// Purely additive. No row is written or rewritten here: every new column
/// stays NULL on existing rows and the three new tables start empty. The
/// legacy-seen backfill (`clear_reason = 'legacy_seen'`) belongs to U18, and
/// the CHECK constraints below deliberately admit that shape
/// (`cleared_by_operation_id IS NULL` on a cleared optional receipt).
///
/// Indexes are created with plain `CREATE INDEX`, never `CONCURRENTLY`:
/// migrant applies every statement of one migration inside a single
/// transaction, and `CONCURRENTLY` cannot run there. This deployment ships a
/// single release with a `kDefaultMinClientVersion` bump and has no live
/// users, so the brief write lock is acceptable — do not "fix" this.
///
/// Every statement is guarded (`IF NOT EXISTS` / `pg_constraint` lookups) so
/// re-running the whole migration against an already-upgraded database is a
/// no-op rather than an error.
final m0178 = Migration('0178', [
  // 1. Preflight. The partial UNIQUE below would otherwise fail with an
  // opaque unique-violation deep inside the index build. Until U05 lands,
  // dispatch still rewrites `occurrence_id` on the `ON CONFLICT (dedup_key)`
  // path, so duplicate pairs are conceivable in a long-lived database. Abort
  // loudly, naming the offending pairs, instead of letting Postgres guess.
  r'''
DO $$
DECLARE
  duplicate_pairs text;
BEGIN
  SELECT string_agg(
           format('(occurrence_id=%s, account_id=%s) x%s', occurrence_id, account_id, pair_count),
           '; ' ORDER BY occurrence_id, account_id
         )
    INTO duplicate_pairs
    FROM (
      SELECT occurrence_id, account_id, count(*) AS pair_count
        FROM public.notification_outbox
       WHERE occurrence_id IS NOT NULL
       GROUP BY occurrence_id, account_id
      HAVING count(*) > 1
    ) AS duplicates;

  IF duplicate_pairs IS NOT NULL THEN
    RAISE EXCEPTION
      'm0178 preflight failed: notification_outbox holds duplicate (occurrence_id, account_id) pairs, so the immutable receipt identity index cannot be built. Repair these rows first: %',
      duplicate_pairs
      USING ERRCODE = 'unique_violation';
  END IF;
END;
$$;
''',

  // 2. New outbox columns. Nullable, no defaults: existing rows keep their
  // meaning and `seen_at` keeps meaning "read", not "cleared".
  '''
ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS cleared_at timestamptz,
  ADD COLUMN IF NOT EXISTS clear_reason text,
  ADD COLUMN IF NOT EXISTS cleared_by_operation_id text,
  ADD COLUMN IF NOT EXISTS logical_task_key text,
  ADD COLUMN IF NOT EXISTS lifecycle_generation integer;
''',

  // 3. Sweep operation header. `surface` and `status` are intentionally plain
  // `text`: the manifest has not frozen their vocabularies, and inventing an
  // enum here would bind a later unit. The counters are what U04 can prove.
  '''
CREATE TABLE IF NOT EXISTS public.attention_clear_operation (
  id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  surface text NOT NULL,
  status text NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT now(),
  undo_deadline timestamptz,
  applied integer NOT NULL DEFAULT 0,
  skipped integer NOT NULL DEFAULT 0,
  failed integer NOT NULL DEFAULT 0,
  CONSTRAINT attention_clear_operation__counters_chk
    CHECK (applied >= 0 AND skipped >= 0 AND failed >= 0)
);
''',
  '''
CREATE INDEX IF NOT EXISTS attention_clear_operation__account
  ON public.attention_clear_operation (account_id, captured_at DESC);
''',

  // 4. Sweep membership: captured once, never extended on retry — the
  // primary key is the idempotency guarantee.
  '''
CREATE TABLE IF NOT EXISTS public.attention_clear_operation_member (
  operation_id text NOT NULL
    REFERENCES public.attention_clear_operation(id) ON DELETE CASCADE,
  receipt_id text NOT NULL
    REFERENCES public.notification_outbox(id) ON DELETE CASCADE,
  beacon_id text,
  outcome_generation integer NOT NULL,
  state text NOT NULL,
  PRIMARY KEY (operation_id, receipt_id),
  CONSTRAINT attention_clear_operation_member__generation_chk
    CHECK (outcome_generation >= 0)
);
''',
  '''
CREATE INDEX IF NOT EXISTS attention_clear_operation_member__receipt
  ON public.attention_clear_operation_member (receipt_id);
''',

  // 5. Per-viewer Request state: the stable ordering anchor plus outcome
  // identity. Starts empty; no backfill in this unit.
  '''
CREATE TABLE IF NOT EXISTS public.attention_request_state (
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  first_entry_at timestamptz NOT NULL DEFAULT now(),
  outcome_generation integer NOT NULL DEFAULT 0,
  decision_revision integer NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, beacon_id),
  CONSTRAINT attention_request_state__generations_chk
    CHECK (outcome_generation >= 0 AND decision_revision >= 0)
);
''',

  // 6. Constraints on the new outbox columns. `ALTER TABLE … ADD CONSTRAINT`
  // has no `IF NOT EXISTS` form in PostgreSQL, hence the catalogue guards.
  r'''
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.notification_outbox'::regclass
       AND conname = 'notification_outbox__clear_reason_chk'
  ) THEN
    ALTER TABLE public.notification_outbox
      ADD CONSTRAINT notification_outbox__clear_reason_chk
      CHECK (
        clear_reason IS NULL
        OR clear_reason IN ('explicit', 'request_open', 'sweep', 'legacy_seen')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.notification_outbox'::regclass
       AND conname = 'notification_outbox__clear_optional_only_chk'
  ) THEN
    ALTER TABLE public.notification_outbox
      ADD CONSTRAINT notification_outbox__clear_optional_only_chk
      CHECK (
        NOT requires_action
        OR (cleared_at IS NULL AND clear_reason IS NULL
            AND cleared_by_operation_id IS NULL)
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.notification_outbox'::regclass
       AND conname = 'notification_outbox__clear_facts_chk'
  ) THEN
    -- Internal coherence only: a cleared receipt records when and why.
    -- `cleared_by_operation_id` stays optional so U18 can backfill
    -- `legacy_seen` without a sweep row. Whether a receipt may be cleared at
    -- all is the optional-only constraint's job, so that an offending write
    -- on an obligation always names that constraint.
    ALTER TABLE public.notification_outbox
      ADD CONSTRAINT notification_outbox__clear_facts_chk
      CHECK (
        (cleared_at IS NULL AND clear_reason IS NULL
          AND cleared_by_operation_id IS NULL)
        OR (cleared_at IS NOT NULL AND clear_reason IS NOT NULL)
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.notification_outbox'::regclass
       AND conname = 'notification_outbox__logical_task_chk'
  ) THEN
    -- Obligation-only, and deliberately weaker than the legacy
    -- `attention_thread_key` rule: existing live obligations carry no
    -- logical task key until U05 writes one.
    ALTER TABLE public.notification_outbox
      ADD CONSTRAINT notification_outbox__logical_task_chk
      CHECK (
        (requires_action
          OR (logical_task_key IS NULL AND lifecycle_generation IS NULL))
        AND (lifecycle_generation IS NULL OR lifecycle_generation >= 0)
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.notification_outbox'::regclass
       AND conname = 'notification_outbox__cleared_by_operation_fkey'
  ) THEN
    ALTER TABLE public.notification_outbox
      ADD CONSTRAINT notification_outbox__cleared_by_operation_fkey
      FOREIGN KEY (cleared_by_operation_id)
      REFERENCES public.attention_clear_operation(id) ON DELETE SET NULL;
  END IF;
END;
$$;
''',

  // 7. Immutable receipt identity. Partial: legacy receipts predating the
  // occurrence topology have `occurrence_id IS NULL` and must stay valid.
  '''
CREATE UNIQUE INDEX IF NOT EXISTS notification_outbox__occurrence_account
  ON public.notification_outbox (occurrence_id, account_id)
  WHERE occurrence_id IS NOT NULL;
''',

  // 8. One live obligation per logical task.
  '''
CREATE UNIQUE INDEX IF NOT EXISTS notification_outbox__live_logical_task
  ON public.notification_outbox (account_id, logical_task_key)
  WHERE requires_action AND settlement_kind IS NULL
    AND logical_task_key IS NOT NULL;
''',

  // 9. Request-scoped lookups for the two attention axes.
  '''
CREATE INDEX IF NOT EXISTS notification_outbox__active_optional_beacon
  ON public.notification_outbox (account_id, beacon_id)
  WHERE NOT requires_action AND cleared_at IS NULL AND beacon_id IS NOT NULL;
''',
  '''
CREATE INDEX IF NOT EXISTS notification_outbox__live_obligation_beacon
  ON public.notification_outbox (account_id, beacon_id)
  WHERE requires_action AND settlement_kind IS NULL AND beacon_id IS NOT NULL;
''',
  '''
CREATE INDEX IF NOT EXISTS notification_outbox__cleared_by_operation
  ON public.notification_outbox (cleared_by_operation_id)
  WHERE cleared_by_operation_id IS NOT NULL;
''',

  // 10. Realtime change detection. m0164 taught the trigger about the
  // settlement axis; without the clear and logical-task columns here, a
  // clear would never reach a second device and the dot would linger.
  r'''
CREATE OR REPLACE FUNCTION public.notify_notification_outbox_update()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  affected_account_id text;
BEGIN
  FOR affected_account_id IN
    WITH changed_rows AS (
      SELECT old_row.account_id AS old_account_id,
             new_row.account_id AS new_account_id
      FROM old_rows old_row
      FULL OUTER JOIN new_rows new_row ON new_row.id = old_row.id
      WHERE ROW(
        old_row.id,
        old_row.account_id,
        old_row.category,
        old_row.kind,
        old_row.priority,
        old_row.title,
        old_row.body,
        old_row.action_url,
        old_row.created_at,
        old_row.read_at,
        old_row.collapsed_count,
        old_row.beacon_id,
        old_row.coordination_item_id,
        old_row.actor_user_id,
        old_row.seen_at,
        old_row.settlement_kind,
        old_row.settled_at,
        old_row.settled_by_user_id,
        old_row.settled_by_occurrence_id,
        old_row.cleared_at,
        old_row.clear_reason,
        old_row.cleared_by_operation_id,
        old_row.logical_task_key,
        old_row.lifecycle_generation,
        old_row.source_event_key,
        old_row.destination_kind,
        old_row.target_entity_id,
        old_row.presentation_key,
        old_row.presentation_payload,
        old_row.in_app_preference_class,
        old_row.suppression_class,
        old_row.access_policy
      ) IS DISTINCT FROM ROW(
        new_row.id,
        new_row.account_id,
        new_row.category,
        new_row.kind,
        new_row.priority,
        new_row.title,
        new_row.body,
        new_row.action_url,
        new_row.created_at,
        new_row.read_at,
        new_row.collapsed_count,
        new_row.beacon_id,
        new_row.coordination_item_id,
        new_row.actor_user_id,
        new_row.seen_at,
        new_row.settlement_kind,
        new_row.settled_at,
        new_row.settled_by_user_id,
        new_row.settled_by_occurrence_id,
        new_row.cleared_at,
        new_row.clear_reason,
        new_row.cleared_by_operation_id,
        new_row.logical_task_key,
        new_row.lifecycle_generation,
        new_row.source_event_key,
        new_row.destination_kind,
        new_row.target_entity_id,
        new_row.presentation_key,
        new_row.presentation_payload,
        new_row.in_app_preference_class,
        new_row.suppression_class,
        new_row.access_policy
      )
    ),
    affected_accounts AS (
      SELECT old_account_id AS account_id FROM changed_rows
      UNION
      SELECT new_account_id AS account_id FROM changed_rows
    )
    SELECT account_id
    FROM affected_accounts
    WHERE account_id IS NOT NULL AND account_id <> ''
    ORDER BY account_id
  LOOP
    PERFORM public.emit_realtime_entity_change(
      'notification',
      affected_account_id,
      'update',
      ARRAY[affected_account_id]
    );
  END LOOP;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_notification_outbox_update failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',

  // 11. Documentation for the next reader.
  '''
COMMENT ON COLUMN public.notification_outbox.cleared_at IS
  'When an optional receipt stopped asking for attention. Distinct from seen_at, which only means read. NULL on every obligation (CHECK).';
''',
  '''
COMMENT ON COLUMN public.notification_outbox.clear_reason IS
  'Why an optional receipt was cleared: explicit | request_open | sweep | legacy_seen. legacy_seen is reserved for the U18 cutover backfill and carries no operation id.';
''',
  '''
COMMENT ON COLUMN public.notification_outbox.cleared_by_operation_id IS
  'Sweep operation that cleared this receipt, when one did. NULL for explicit, request_open and legacy_seen clears.';
''',
  '''
COMMENT ON COLUMN public.notification_outbox.logical_task_key IS
  'Obligation identity across renewals; one live obligation per (account_id, logical_task_key). Not a rename of attention_thread_key, which keeps its legacy meaning. Populated from U05 onwards.';
''',
  '''
COMMENT ON COLUMN public.notification_outbox.lifecycle_generation IS
  'Monotonic generation of the logical task; a renewal supersedes its predecessor, a delivery retry does not. Populated from U05 onwards.';
''',
  '''
COMMENT ON TABLE public.attention_clear_operation IS
  'Header of one clear/dismiss-all sweep. surface and status are free text until a later unit freezes their vocabularies.';
''',
  '''
COMMENT ON TABLE public.attention_clear_operation_member IS
  'Receipts captured by a sweep. Captured once and never extended on retry: the (operation_id, receipt_id) primary key is that guarantee. beacon_id is an unreferenced snapshot so the audit survives beacon deletion.';
''',
  '''
COMMENT ON TABLE public.attention_request_state IS
  'Per-viewer Request state: stable ordering anchor (first_entry_at) plus outcome identity. Starts empty; U04 backfills nothing.';
''',
]);
