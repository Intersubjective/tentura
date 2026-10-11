part of '_migrations.dart';

/// Post→Request budding schema (budding B1, Arch §2).
///
/// - `beacon_bud_observer`: the snapshot of the effective Post members that
///   may read a Request budded from a Post (N3). Written once, never extended.
/// - `beacon_author_invite`: an author-confirmed invitation of a Post member
///   into the budded Request (D7). Status: 0 pending, 1 accepted, 2 declined,
///   3 withdrawn, 4 expired, 5 superseded. Provenance columns are immutable.
///   `source_post_id` is NULL for repair invites; `arrival_post_edge_id` has
///   no FK because it is immutable provenance.
/// - `beacon_child_commands` gains `bud_result` and `anchor_inherited_at`: the
///   one idempotency table for budding (Arch §2.6).
/// - `beacon_forward_edge.contact_sweep_exempt`: the ignored-contact sweep
///   skips exempt edges (Arch §2.5).
/// - `beacon_post_shape_ck` admits the closed Post status 6 (Arch §2.3).
///
/// None of these is tracked by Hasura.
final m0239 = Migration('0239', [
  '''
CREATE TABLE public.beacon_bud_observer (
    beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
    user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (beacon_id, user_id)
)
''',
  '''
CREATE INDEX beacon_bud_observer_user_idx
    ON public.beacon_bud_observer (user_id, beacon_id)
''',
  r'''
CREATE TABLE public.beacon_author_invite (
    id text DEFAULT concat('BI', "substring"((gen_random_uuid())::text, '\w{12}'::text)) NOT NULL PRIMARY KEY,
    beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
    inviter_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
    invitee_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
    source_post_id text,
    forward_edge_id text REFERENCES public.beacon_forward_edge(id) ON DELETE SET NULL,
    arrival_post_edge_id text,
    warm boolean NOT NULL,
    note text,
    status smallint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    resolved_by text REFERENCES public."user"(id) ON DELETE SET NULL,
    CONSTRAINT beacon_author_invite_status_ck CHECK (status BETWEEN 0 AND 5)
)
''',
  '''
CREATE UNIQUE INDEX beacon_author_invite_pending_source_uq
    ON public.beacon_author_invite (inviter_id, invitee_id, source_post_id)
    WHERE status = 0 AND source_post_id IS NOT NULL
''',
  '''
CREATE UNIQUE INDEX beacon_author_invite_pending_beacon_uq
    ON public.beacon_author_invite (beacon_id, invitee_id)
    WHERE status = 0
''',
  '''
CREATE INDEX beacon_author_invite_pending_invitee_idx
    ON public.beacon_author_invite (invitee_id)
    WHERE status = 0
''',
  '''
CREATE INDEX beacon_author_invite_beacon_status_idx
    ON public.beacon_author_invite (beacon_id, status)
''',
  '''
CREATE INDEX beacon_author_invite_forward_edge_idx
    ON public.beacon_author_invite (forward_edge_id)
''',
  r'''
CREATE FUNCTION public.beacon_author_invite_provenance_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.beacon_id IS DISTINCT FROM OLD.beacon_id
     OR NEW.inviter_id IS DISTINCT FROM OLD.inviter_id
     OR NEW.invitee_id IS DISTINCT FROM OLD.invitee_id
     OR NEW.source_post_id IS DISTINCT FROM OLD.source_post_id
     OR NEW.arrival_post_edge_id IS DISTINCT FROM OLD.arrival_post_edge_id
     OR NEW.warm IS DISTINCT FROM OLD.warm THEN
    RAISE EXCEPTION 'beacon_author_invite provenance is immutable' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER beacon_author_invite_provenance_guard_trg
    BEFORE UPDATE ON public.beacon_author_invite
    FOR EACH ROW EXECUTE FUNCTION public.beacon_author_invite_provenance_guard()
''',
  '''
ALTER TABLE public.beacon_child_commands
    ADD COLUMN bud_result jsonb,
    ADD COLUMN anchor_inherited_at timestamp with time zone
''',
  '''
CREATE INDEX beacon_child_commands_anchor_pending_idx
    ON public.beacon_child_commands (created_at)
    WHERE bud_result IS NOT NULL AND anchor_inherited_at IS NULL
''',
  '''
ALTER TABLE public.beacon_forward_edge
    ADD COLUMN contact_sweep_exempt boolean DEFAULT false NOT NULL
''',
  '''
ALTER TABLE public.beacon
    DROP CONSTRAINT beacon_post_shape_ck
''',
  '''
ALTER TABLE public.beacon
    ADD CONSTRAINT beacon_post_shape_ck CHECK (kind = 0 OR (status IN (0, 2, 3, 6) AND is_discoverable = false AND parent_beacon_id IS NULL AND start_at IS NULL AND end_at IS NULL AND title = '' AND description = '' AND cover_image_id IS NULL))
''',
]);
