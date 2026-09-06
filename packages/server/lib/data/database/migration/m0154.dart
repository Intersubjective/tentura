part of '_migrations.dart';

/// Nested-request hierarchy storage: parent/publication columns, command and
/// promotion provenance, lifecycle event outbox, and system-authored room messages.
final m0154 = Migration('0154', [
  r'''
ALTER TABLE public.beacon
  ADD COLUMN parent_beacon_id text NULL,
  ADD COLUMN published_at timestamptz NULL,
  ADD COLUMN hierarchy_event_sequence bigint NOT NULL DEFAULT 0;
''',
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_parent_beacon_id_fkey
    FOREIGN KEY (parent_beacon_id)
    REFERENCES public.beacon(id)
    ON DELETE RESTRICT;
''',
  r'''
COMMENT ON COLUMN public.beacon.parent_beacon_id IS
  'Immutable nesting parent (distinct from lineage_parent_beacon_id). Assigned on insert only.';
''',
  r'''
COMMENT ON COLUMN public.beacon.published_at IS
  'Set once at publication; NULL for drafts. Backfilled from created_at for existing published rows.';
''',
  r'''
COMMENT ON COLUMN public.beacon.hierarchy_event_sequence IS
  'Monotonic per-source hierarchy lifecycle event sequence, incremented under beacon row lock.';
''',
  r'''
UPDATE public.beacon
SET published_at = created_at
WHERE status <> 3 AND published_at IS NULL;
''',
  r'''
CREATE INDEX beacon_parent_published_children_idx ON public.beacon (
  parent_beacon_id, published_at DESC, id DESC
)
WHERE parent_beacon_id IS NOT NULL AND published_at IS NOT NULL;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_parent_beacon_id_insert_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  parent_row public.beacon%ROWTYPE;
  cycle_hit text;
BEGIN
  IF NEW.parent_beacon_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.parent_beacon_id = NEW.id THEN
    RAISE EXCEPTION 'beacon_parent_self_reference'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO parent_row FROM public.beacon WHERE id = NEW.parent_beacon_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'beacon_parent_missing'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF parent_row.published_at IS NULL OR parent_row.status = 3 THEN
    RAISE EXCEPTION 'beacon_parent_not_published'
      USING ERRCODE = 'check_violation';
  END IF;

  WITH RECURSIVE ancestors AS (
    SELECT id, parent_beacon_id
    FROM public.beacon
    WHERE id = NEW.parent_beacon_id
    UNION ALL
    SELECT b.id, b.parent_beacon_id
    FROM public.beacon b
    JOIN ancestors a ON b.id = a.parent_beacon_id
    WHERE a.parent_beacon_id IS NOT NULL
  )
  SELECT id INTO cycle_hit
  FROM ancestors
  WHERE id = NEW.id
  LIMIT 1;

  IF cycle_hit IS NOT NULL THEN
    RAISE EXCEPTION 'beacon_parent_cycle'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_parent_beacon_id_update_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  IF NEW.parent_beacon_id IS DISTINCT FROM OLD.parent_beacon_id THEN
    RAISE EXCEPTION 'beacon_parent_immutable'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS beacon_parent_beacon_id_insert_guard_trg ON public.beacon;
''',
  r'''
CREATE TRIGGER beacon_parent_beacon_id_insert_guard_trg
  BEFORE INSERT ON public.beacon
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_parent_beacon_id_insert_guard();
''',
  r'''
DROP TRIGGER IF EXISTS beacon_parent_beacon_id_update_guard_trg ON public.beacon;
''',
  r'''
CREATE TRIGGER beacon_parent_beacon_id_update_guard_trg
  BEFORE UPDATE OF parent_beacon_id ON public.beacon
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_parent_beacon_id_update_guard();
''',
  r'''
CREATE TABLE public.beacon_child_commands (
  actor_user_id text NOT NULL
    REFERENCES public."user"(id) ON DELETE RESTRICT,
  client_command_id text NOT NULL,
  normalized_input_hash text NOT NULL,
  result_beacon_id text NULL
    REFERENCES public.beacon(id) ON DELETE SET NULL,
  result_state smallint NOT NULL
    CHECK (result_state BETWEEN 0 AND 2),
  deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_user_id, client_command_id),
  CONSTRAINT beacon_child_commands_deleted_result_ck
    CHECK (NOT deleted OR result_beacon_id IS NULL)
);
''',
  r'''
COMMENT ON TABLE public.beacon_child_commands IS
  'Idempotent child-create command ledger. result_state: 0=created,1=replayed,2=alreadyPromoted.';
''',
  r'''
CREATE INDEX beacon_child_commands_result_beacon_idx
  ON public.beacon_child_commands (result_beacon_id)
  WHERE result_beacon_id IS NOT NULL;
''',
  r'''
CREATE TABLE public.beacon_promotions (
  child_beacon_id text PRIMARY KEY
    REFERENCES public.beacon(id) ON DELETE RESTRICT,
  parent_beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON DELETE RESTRICT,
  source_message_id text NULL
    REFERENCES public.beacon_room_message(id) ON DELETE SET NULL,
  promoter_user_id text NULL
    REFERENCES public."user"(id) ON DELETE SET NULL,
  published_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beacon_promotions_source_general_ck
    CHECK (source_message_id IS NOT NULL OR published_at IS NULL)
);
''',
  r'''
CREATE UNIQUE INDEX beacon_promotions_published_source_uidx
  ON public.beacon_promotions (source_message_id)
  WHERE published_at IS NOT NULL AND source_message_id IS NOT NULL;
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_promotions_consistency_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  child_parent text;
  source_beacon text;
  source_thread text;
BEGIN
  SELECT parent_beacon_id INTO child_parent
  FROM public.beacon
  WHERE id = NEW.child_beacon_id;

  IF child_parent IS DISTINCT FROM NEW.parent_beacon_id THEN
    RAISE EXCEPTION 'beacon_promotion_parent_mismatch'
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.source_message_id IS NOT NULL THEN
    SELECT beacon_id, thread_item_id
    INTO source_beacon, source_thread
    FROM public.beacon_room_message
    WHERE id = NEW.source_message_id;

    IF source_beacon IS DISTINCT FROM NEW.parent_beacon_id THEN
      RAISE EXCEPTION 'beacon_promotion_source_beacon_mismatch'
        USING ERRCODE = 'check_violation';
    END IF;

    IF source_thread IS NOT NULL THEN
      RAISE EXCEPTION 'beacon_promotion_source_not_general'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS beacon_promotions_consistency_guard_trg ON public.beacon_promotions;
''',
  r'''
CREATE TRIGGER beacon_promotions_consistency_guard_trg
  BEFORE INSERT OR UPDATE ON public.beacon_promotions
  FOR EACH ROW
  EXECUTE FUNCTION public.beacon_promotions_consistency_guard();
''',
  r'''
CREATE TABLE public.beacon_hierarchy_events (
  id text PRIMARY KEY,
  source_beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON DELETE RESTRICT,
  source_sequence bigint NOT NULL,
  from_status smallint NOT NULL,
  to_status smallint NOT NULL,
  occurred_at timestamptz NOT NULL,
  actor_user_id text NULL
    REFERENCES public."user"(id) ON DELETE SET NULL,
  CONSTRAINT beacon_hierarchy_events_source_sequence_uq
    UNIQUE (source_beacon_id, source_sequence)
);
''',
  r'''
CREATE INDEX beacon_hierarchy_events_source_idx
  ON public.beacon_hierarchy_events (source_beacon_id, source_sequence DESC);
''',
  r'''
CREATE TABLE public.beacon_hierarchy_deliveries (
  event_id text NOT NULL
    REFERENCES public.beacon_hierarchy_events(id) ON DELETE RESTRICT,
  target_beacon_id text NOT NULL
    REFERENCES public.beacon(id) ON DELETE RESTRICT,
  direction text NOT NULL
    CHECK (direction IN ('ancestor', 'child')),
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'leased', 'delivered', 'suppressed', 'parked')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_safe_error_code text NULL,
  notice_message_id text NULL
    REFERENCES public.beacon_room_message(id) ON DELETE SET NULL,
  completed_at timestamptz NULL,
  lease_owner text NULL,
  lease_until timestamptz NULL,
  PRIMARY KEY (event_id, target_beacon_id),
  CHECK ((state = 'leased') = (lease_owner IS NOT NULL AND lease_until IS NOT NULL)),
  CHECK ((state IN ('delivered', 'suppressed', 'parked')) = (completed_at IS NOT NULL))
);
''',
  r'''
CREATE INDEX beacon_hierarchy_deliveries_due_idx
  ON public.beacon_hierarchy_deliveries (next_attempt_at, event_id, target_beacon_id)
  WHERE state IN ('pending', 'leased');
''',
  r'''
ALTER TABLE public.beacon_room_message
  ALTER COLUMN author_id DROP NOT NULL;
''',
  r'''
ALTER TABLE public.beacon_room_message
  DROP CONSTRAINT IF EXISTS beacon_room_message_author_id_fkey;
''',
  r'''
ALTER TABLE public.beacon_room_message
  ADD CONSTRAINT beacon_room_message_author_id_fkey
    FOREIGN KEY (author_id)
    REFERENCES public."user"(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.beacon_room_message
  ADD COLUMN system_message_kind smallint NULL,
  ADD COLUMN hierarchy_notice_identity text NULL;
''',
  r'''
ALTER TABLE public.beacon_room_message
  ADD CONSTRAINT beacon_room_message_author_or_system_ck
    CHECK (author_id IS NOT NULL OR system_message_kind IS NOT NULL);
''',
  r'''
CREATE UNIQUE INDEX beacon_room_message_hierarchy_notice_identity_uidx
  ON public.beacon_room_message (hierarchy_notice_identity)
  WHERE hierarchy_notice_identity IS NOT NULL;
''',
  r'''
COMMENT ON COLUMN public.beacon_room_message.system_message_kind IS
  'NULL for ordinary user messages; non-null marks system-authored notices (1=hierarchy lifecycle, 2=child created).';
''',
  r'''
COMMENT ON COLUMN public.beacon_room_message.hierarchy_notice_identity IS
  'Stable notice identity for system messages: child_created:<childId> or hierarchy:<eventId>:<targetId>.';
''',
]);
