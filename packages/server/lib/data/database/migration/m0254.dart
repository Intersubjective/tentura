part of '_migrations.dart';

/// Request **Questions** (internally: the Request lobby; U088, #526, sprint
/// decision D1): one conversation per Request, open **before** offering help
/// to the Request's addressed audience, and public to all of it.
///
/// It reuses the dormant item-thread scope instead of a new message table:
/// the Questions scope is one `coordination_item` of kind 7 per Request, and
/// its messages are ordinary `beacon_room_message` rows whose
/// `thread_item_id` is that item (the per-thread `beacon_room_seen`
/// watermark comes with it). This is the one named exception to "rooms are
/// General-only"; every other item thread stays disabled.
///
/// - The two General-only guards let a thread scope through only when it is
///   the Request's own Questions item.
/// - One Questions item per Request (partial unique index).
/// - `beacon_lobby_ban`: who the author removed from Questions. A ban is per
///   Request and person, outlives withdrawing and offering again, and ends
///   only when the author lifts it (or the Request / account is deleted).
/// - `questions_access_levels` / `questions_audience`: the ONE access policy
///   (0 none, 1 read-only, 2 read and write). Every server path (open, read,
///   history, post, edit, delete, react, seen, mentions, notifications,
///   realtime) goes through it; see `docs/features/beacon_questions.md`.
/// - `notify_questions_message_change`: realtime hints for Questions messages
///   to audience members outside the General room (scoped recipients only;
///   the General `notify_entity_change` path is unchanged).
/// - `reject_questions_message_reference`: General-only features (facts,
///   plan/coordination items, batons, next moves, promotions, activity
///   events) can never point at a Questions message.
final m0254 = Migration('0254', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_message_general_only_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.thread_item_id IS DISTINCT FROM OLD.thread_item_id THEN
    IF NEW.thread_item_id IS NOT NULL
      AND NOT public.discussion_internal_fixture_allowed()
      AND NOT EXISTS (
        SELECT 1 FROM public.coordination_item ci
        WHERE ci.id = NEW.thread_item_id
          AND ci.beacon_id = NEW.beacon_id
          AND ci.kind = 7
      ) THEN
      RAISE EXCEPTION 'discussion_scope_disabled'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_seen_general_only_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.thread_item_id IS NOT NULL
    AND NOT public.discussion_internal_fixture_allowed()
    AND NOT EXISTS (
      SELECT 1 FROM public.coordination_item ci
      WHERE ci.id = NEW.thread_item_id
        AND ci.beacon_id = NEW.beacon_id
        AND ci.kind = 7
    ) THEN
    RAISE EXCEPTION 'discussion_scope_disabled'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$
''',
  '''
CREATE UNIQUE INDEX coordination_item_one_lobby_per_beacon
  ON public.coordination_item USING btree (beacon_id)
  WHERE kind = 7
''',
  '''
CREATE TABLE public.beacon_lobby_ban (
    beacon_id text NOT NULL
      REFERENCES public.beacon(id) ON DELETE CASCADE,
    user_id text NOT NULL
      REFERENCES public."user"(id) ON DELETE CASCADE,
    banned_by text
      REFERENCES public."user"(id) ON DELETE SET NULL,
    banned_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (beacon_id, user_id)
)
''',
  '''
COMMENT ON TABLE public.beacon_lobby_ban IS
  'People the Request author removed from the Request Questions space (U088).'
''',
  // The policy. `p_user_ids` are candidates; the result has one row per
  // distinct candidate when the beacon is a Request (none otherwise).
  //
  // Own standing (always writes on an open Request): author; steward
  // (beacon_steward or participant role 1); admitted participant
  // (room_access 3); a live help offer.
  // Addressed standing (writes unless the person withdrew, was declined or
  // answered "Can't help"):
  // a live forward edge to them they did not answer "Can't help" to; direct
  // addressee (participant role 6).
  // Read-only standing (Q4): a live forward edge answered "Can't help"
  // (recipient_rejected); a help offer that is no longer live (withdrawn or
  // declined) — it also turns addressed standing read-only; offering again
  // restores writing.
  // Never standing: cancelled forwards, historical inbox items, discovery or
  // hierarchy readability (Q3).
  // Then: banned (never the author) -> none; Request content not readable
  // (blocks with the author, deleted, draft, ... via
  // beacon_can_read_content) -> none; write standing on a Request whose
  // lifecycle allows discussion writes (not cancelled 1 / deleted 2 /
  // closed 6) -> 2; otherwise -> 1.
  r'''
CREATE FUNCTION public.questions_access_levels(p_beacon_id text, p_user_ids text[])
RETURNS TABLE(user_id text, access smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH b AS (
  SELECT beacon.id, beacon.user_id AS author_id, beacon.status
  FROM public.beacon
  WHERE beacon.id = p_beacon_id AND beacon.kind = 0
),
cand AS (
  SELECT DISTINCT u AS user_id
  FROM unnest(COALESCE(p_user_ids, ARRAY[]::text[])) AS u
  WHERE u IS NOT NULL AND u <> ''
),
standing AS (
  SELECT
    c.user_id,
    b.status,
    c.user_id = b.author_id AS is_author,
    (
      c.user_id = b.author_id
      OR EXISTS (
        SELECT 1 FROM public.beacon_steward bs
        WHERE bs.beacon_id = b.id AND bs.user_id = c.user_id
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_participant bp
        WHERE bp.beacon_id = b.id AND bp.user_id = c.user_id
          AND (bp.role = 1 OR bp.room_access = 3)
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_help_offer ho
        WHERE ho.beacon_id = b.id AND ho.user_id = c.user_id
          AND ho.status = 0
      )
    ) AS own_standing,
    (
      EXISTS (
        SELECT 1 FROM public.beacon_forward_edge fe
        WHERE fe.beacon_id = b.id AND fe.recipient_id = c.user_id
          AND fe.cancelled_at IS NULL AND NOT fe.recipient_rejected
      )
      OR EXISTS (
        SELECT 1 FROM public.beacon_participant bp
        WHERE bp.beacon_id = b.id AND bp.user_id = c.user_id
          AND bp.role = 6
      )
    ) AS addressed,
    EXISTS (
      SELECT 1 FROM public.beacon_help_offer ho
      WHERE ho.beacon_id = b.id AND ho.user_id = c.user_id
        AND ho.status <> 0
    ) AS past_offer,
    EXISTS (
      SELECT 1 FROM public.beacon_forward_edge fe
      WHERE fe.beacon_id = b.id AND fe.recipient_id = c.user_id
        AND fe.cancelled_at IS NULL AND fe.recipient_rejected
    ) AS rejected_forward,
    EXISTS (
      SELECT 1 FROM public.beacon_lobby_ban ban
      WHERE ban.beacon_id = b.id AND ban.user_id = c.user_id
    ) AS banned
  FROM cand c
  CROSS JOIN b
)
SELECT
  s.user_id,
  (CASE
    WHEN NOT (s.own_standing OR s.addressed OR s.past_offer
              OR s.rejected_forward) THEN 0
    WHEN s.banned AND NOT s.is_author THEN 0
    WHEN NOT public.beacon_can_read_content(p_beacon_id, s.user_id) THEN 0
    WHEN (s.own_standing
          OR (s.addressed AND NOT s.past_offer AND NOT s.rejected_forward))
      AND s.status NOT IN (1, 2, 6) THEN 2
    ELSE 1
  END)::smallint AS access
FROM standing s
$$
''',
  // Everyone with access > 0. The candidate set is the union of every
  // standing source above (kept next to the policy on purpose).
  r'''
CREATE FUNCTION public.questions_audience(p_beacon_id text)
RETURNS TABLE(user_id text, access smallint)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT l.user_id, l.access
FROM public.questions_access_levels(
  p_beacon_id,
  ARRAY(
    SELECT b.user_id FROM public.beacon b
    WHERE b.id = p_beacon_id AND b.user_id IS NOT NULL
    UNION
    SELECT bs.user_id FROM public.beacon_steward bs
    WHERE bs.beacon_id = p_beacon_id
    UNION
    SELECT bp.user_id FROM public.beacon_participant bp
    WHERE bp.beacon_id = p_beacon_id
      AND (bp.role IN (1, 6) OR bp.room_access = 3)
    UNION
    SELECT fe.recipient_id FROM public.beacon_forward_edge fe
    WHERE fe.beacon_id = p_beacon_id AND fe.cancelled_at IS NULL
    UNION
    SELECT ho.user_id FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = p_beacon_id
  )
) l
WHERE l.access > 0
$$
''',
  // Realtime: Questions messages also reach audience members who are not
  // General room recipients (those already get the General hint). Same wire
  // kind and envelope as the General path; the websocket layer paints no
  // thread text (bare hint) and clients refetch through the gated API.
  r'''
CREATE FUNCTION public.notify_questions_message_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_beacon_id text := COALESCE(NEW.beacon_id, OLD.beacon_id);
  v_thread_item_id text := COALESCE(NEW.thread_item_id, OLD.thread_item_id);
  v_user_ids text[];
BEGIN
  IF v_thread_item_id IS NULL THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.coordination_item ci
    WHERE ci.id = v_thread_item_id
      AND ci.beacon_id = v_beacon_id
      AND ci.kind = 7
  ) THEN
    RETURN NULL;
  END IF;
  SELECT COALESCE(array_agg(a.user_id), ARRAY[]::text[])
  INTO v_user_ids
  FROM public.questions_audience(v_beacon_id) a
  WHERE NOT (a.user_id = ANY (public.realtime_room_recipients(v_beacon_id)))
    -- No hint about a message to someone blocked with its author.
    AND (COALESCE(NEW.author_id, OLD.author_id) IS NULL
      OR NOT public.block_hides(COALESCE(NEW.author_id, OLD.author_id), a.user_id));
  PERFORM public.emit_realtime_entity_change(
    'room_message',
    v_beacon_id,
    lower(TG_OP),
    v_user_ids,
    jsonb_build_object('message_id', COALESCE(NEW.id, OLD.id))
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_questions_message_change failed without aborting write: %', SQLERRM;
    RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER beacon_room_message_questions_notify
  AFTER INSERT OR DELETE OR UPDATE ON public.beacon_room_message
  FOR EACH ROW EXECUTE FUNCTION public.notify_questions_message_change()
''',
  // General-only features must never point at a thread-scoped (Questions)
  // message: their audience is the General room, so the reference would
  // carry Questions text or existence there. TG_ARGV[0] names the column.
  r'''
CREATE FUNCTION public.reject_questions_message_reference() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_message_id text := to_jsonb(NEW) ->> TG_ARGV[0];
BEGIN
  IF v_message_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.beacon_room_message m
    WHERE m.id = v_message_id AND m.thread_item_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'discussion_scope_disabled'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER beacon_fact_card_questions_ref_guard
  BEFORE INSERT OR UPDATE OF source_message_id ON public.beacon_fact_card
  FOR EACH ROW EXECUTE FUNCTION public.reject_questions_message_reference('source_message_id')
''',
  '''
CREATE TRIGGER beacon_promotions_questions_ref_guard
  BEFORE INSERT OR UPDATE OF source_message_id ON public.beacon_promotions
  FOR EACH ROW EXECUTE FUNCTION public.reject_questions_message_reference('source_message_id')
''',
  '''
CREATE TRIGGER coordination_item_linked_questions_ref_guard
  BEFORE INSERT OR UPDATE OF linked_message_id ON public.coordination_item
  FOR EACH ROW EXECUTE FUNCTION public.reject_questions_message_reference('linked_message_id')
''',
  '''
CREATE TRIGGER coordination_item_target_questions_ref_guard
  BEFORE INSERT OR UPDATE OF target_message_id ON public.coordination_item
  FOR EACH ROW EXECUTE FUNCTION public.reject_questions_message_reference('target_message_id')
''',
  '''
CREATE TRIGGER beacon_participant_questions_ref_guard
  BEFORE INSERT OR UPDATE OF linked_message_id ON public.beacon_participant
  FOR EACH ROW EXECUTE FUNCTION public.reject_questions_message_reference('linked_message_id')
''',
  '''
CREATE TRIGGER beacon_room_baton_questions_ref_guard
  BEFORE INSERT OR UPDATE OF message_id ON public.beacon_room_baton
  FOR EACH ROW EXECUTE FUNCTION public.reject_questions_message_reference('message_id')
''',
  // `beacon.last_activity_at` is readable by everyone who can read the
  // Request (Hasura), including people outside the Questions audience: a
  // Questions message or reaction must not move it (m0209 bodies otherwise
  // unchanged).
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_message_bump_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.system_message_kind IS NULL AND NEW.thread_item_id IS NULL THEN
    PERFORM public.beacon_bump_last_activity(NEW.beacon_id, NEW.created_at);
  END IF;
  RETURN NEW;
END
$$
''',
  r'''
CREATE OR REPLACE FUNCTION public.beacon_room_message_reaction_bump_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_beacon text;
BEGIN
  SELECT m.beacon_id INTO v_beacon FROM public.beacon_room_message m
  WHERE m.id = NEW.message_id AND m.thread_item_id IS NULL;
  IF v_beacon IS NOT NULL THEN
    PERFORM public.beacon_bump_last_activity(v_beacon, NEW.created_at);
  END IF;
  RETURN NEW;
END
$$
''',
  '''
CREATE TRIGGER beacon_activity_event_questions_ref_guard
  BEFORE INSERT OR UPDATE OF source_message_id ON public.beacon_activity_event
  FOR EACH ROW EXECUTE FUNCTION public.reject_questions_message_reference('source_message_id')
''',
]);
