part of '_migrations.dart';

/// Request plan («либретто», #220).
///
/// - Plan steps live in `coordination_item` with the new kind `6`. Legacy
///   readers of kind `1` never see them. Ticks (`done_at`, `done_by_id`) sit
///   on the step row and never enter revisions.
/// - `beacon_plan` is the per-Request head: revision counter, lock row and the
///   realtime source (`beacon_plan` wire kind, room recipients + stewards).
/// - `beacon_plan_revision` keeps every saved snapshot (without ticks) plus a
///   l10n-neutral `changes_json`.
/// - `beacon_plan_member` is the per-person «Понятно» ledger.
///
/// Per-row `coordination_item` NOTIFY is silenced for plan steps: an edit of N
/// steps would otherwise trigger N full Request refreshes. The `beacon_plan`
/// head row publishes once per write instead.
///
/// Legacy kinds are left unconstrained: only kind 6 rows get the plan shape
/// CHECK, and plan columns stay NULL on every other kind.
final m0223 = Migration('0223', [
  r'''
ALTER TABLE public.coordination_item
  ADD COLUMN start_at timestamptz NULL,
  ADD COLUMN end_at timestamptz NULL,
  ADD COLUMN done_at timestamptz NULL,
  ADD COLUMN done_by_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  ADD COLUMN source_item_id text NULL REFERENCES public.coordination_item(id) ON DELETE SET NULL,
  ADD COLUMN created_seq integer NULL,
  ADD COLUMN content_seq integer NULL,
  ADD COLUMN ack_seq integer NULL,
  ADD COLUMN removed_seq integer NULL
''',

  r'''
ALTER TABLE public.coordination_item
  ADD CONSTRAINT coordination_item_plan_step_time_chk
    CHECK (end_at IS NULL OR start_at IS NULL OR end_at >= start_at),
  ADD CONSTRAINT coordination_item_plan_step_shape_chk CHECK (
    kind <> 6 OR (
      status IN (0, 3)
      AND linked_parent_item_id IS NULL
      AND published
      AND created_seq IS NOT NULL
      AND content_seq IS NOT NULL
      AND ack_seq IS NOT NULL
      AND ((status = 3) = (removed_seq IS NOT NULL))
      AND (done_at IS NOT NULL OR done_by_id IS NULL)
    )),
  ADD CONSTRAINT coordination_item_plan_only_cols_chk CHECK (
    kind = 6 OR (
      start_at IS NULL AND end_at IS NULL AND done_at IS NULL
      AND done_by_id IS NULL AND source_item_id IS NULL
      AND created_seq IS NULL AND content_seq IS NULL
      AND ack_seq IS NULL AND removed_seq IS NULL
    ))
''',

  r'''
CREATE INDEX coordination_item_plan_live_order
  ON public.coordination_item (beacon_id, ordering)
  WHERE kind = 6 AND status = 0
''',

  r'''
CREATE INDEX coordination_item_plan_assignee_live
  ON public.coordination_item (target_person_id, beacon_id)
  WHERE kind = 6 AND status = 0
''',

  r'''
CREATE INDEX coordination_item_plan_start_open
  ON public.coordination_item (start_at)
  WHERE kind = 6 AND status = 0 AND done_at IS NULL AND start_at IS NOT NULL
''',

  r'''
CREATE INDEX coordination_item_plan_end_open
  ON public.coordination_item (end_at)
  WHERE kind = 6 AND status = 0 AND done_at IS NULL AND end_at IS NOT NULL
''',

  r'''
CREATE INDEX coordination_item_source_item
  ON public.coordination_item (source_item_id)
  WHERE source_item_id IS NOT NULL
''',

  r'''
CREATE INDEX coordination_item_done_by
  ON public.coordination_item (done_by_id)
  WHERE done_by_id IS NOT NULL
''',

  r'''
CREATE TABLE public.beacon_plan (
  beacon_id text PRIMARY KEY REFERENCES public.beacon(id) ON DELETE CASCADE,
  revision_seq integer NOT NULL DEFAULT 0,
  change_seq integer NOT NULL DEFAULT 0,
  last_edited_by text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  last_edited_at timestamptz NULL,
  copied_from_beacon_id text NULL REFERENCES public.beacon(id) ON DELETE SET NULL,
  copied_from_seq integer NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
)
''',

  r'''
CREATE INDEX beacon_plan_last_edited_by
  ON public.beacon_plan (last_edited_by)
  WHERE last_edited_by IS NOT NULL
''',

  r'''
CREATE INDEX beacon_plan_copied_from
  ON public.beacon_plan (copied_from_beacon_id)
  WHERE copied_from_beacon_id IS NOT NULL
''',

  // kind: 0 created, 1 edited, 2 restored, 3 copied, 4 cant_make,
  // 5 unassigned_on_leave, 6 cant_make_chat (snapshot unchanged).
  r'''
CREATE TABLE public.beacon_plan_revision (
  id text PRIMARY KEY DEFAULT concat('PR', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  beacon_id text NOT NULL REFERENCES public.beacon_plan(beacon_id) ON DELETE CASCADE,
  seq integer NOT NULL,
  base_seq integer NULL,
  kind smallint NOT NULL CHECK (kind BETWEEN 0 AND 6),
  actor_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  restored_from_seq integer NULL,
  comment text NOT NULL DEFAULT '' CHECK (char_length(comment) <= 280),
  steps_json jsonb NOT NULL,
  changes_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (beacon_id, seq),
  CHECK (kind <> 2 OR restored_from_seq IS NOT NULL)
)
''',

  r'''
CREATE INDEX beacon_plan_revision_actor_created
  ON public.beacon_plan_revision (actor_id, created_at DESC)
''',

  r'''
CREATE TABLE public.beacon_plan_member (
  beacon_id text NOT NULL REFERENCES public.beacon_plan(beacon_id) ON DELETE CASCADE,
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  pending_from_seq integer NULL,
  acked_seq integer NOT NULL DEFAULT 0,
  acked_at timestamptz NULL,
  PRIMARY KEY (beacon_id, user_id)
)
''',

  r'''
CREATE INDEX beacon_plan_member_pending
  ON public.beacon_plan_member (user_id)
  WHERE pending_from_seq IS NOT NULL
''',

  r'''
CREATE FUNCTION public.notify_beacon_plan_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  PERFORM public.emit_realtime_entity_change(
    'beacon_plan',
    NEW.beacon_id,
    lower(TG_OP),
    public.realtime_room_recipients(NEW.beacon_id)
      || ARRAY(
        SELECT s.user_id
        FROM public.beacon_steward s
        WHERE s.beacon_id = NEW.beacon_id
      ),
    jsonb_build_object('change_seq', NEW.change_seq)
  );
  RETURN NULL;
END
$$
''',

  r'''
CREATE TRIGGER beacon_plan_entity_notify
  AFTER INSERT OR UPDATE ON public.beacon_plan
  FOR EACH ROW EXECUTE FUNCTION public.notify_beacon_plan_change()
''',

  r'''
DROP TRIGGER coordination_item_entity_notify ON public.coordination_item
''',

  r'''
CREATE TRIGGER coordination_item_entity_notify_ins
  AFTER INSERT ON public.coordination_item
  FOR EACH ROW WHEN (NEW.kind <> 6)
  EXECUTE FUNCTION public.notify_entity_change('coordination_item')
''',

  r'''
CREATE TRIGGER coordination_item_entity_notify_upd
  AFTER UPDATE ON public.coordination_item
  FOR EACH ROW WHEN (OLD.kind <> 6 OR NEW.kind <> 6)
  EXECUTE FUNCTION public.notify_entity_change('coordination_item')
''',

  r'''
CREATE TRIGGER coordination_item_entity_notify_del
  AFTER DELETE ON public.coordination_item
  FOR EACH ROW WHEN (OLD.kind <> 6)
  EXECUTE FUNCTION public.notify_entity_change('coordination_item')
''',
]);
