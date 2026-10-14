part of '_migrations.dart';

/// U088 — the Request lobby: a discussion for the people who offered help
/// (and the author), with the author able to ban someone from it.
///
/// It reuses the dormant item-thread scope instead of a new message table:
/// a lobby is one `coordination_item` of kind 7 per Request, and lobby
/// messages are ordinary `beacon_room_message` rows whose `thread_item_id`
/// is that item (the per-thread `beacon_room_seen` watermark comes with it).
///
/// - The two General-only guards now let a thread scope through when it is
///   the Request's lobby item; every other item thread stays disabled.
/// - One lobby per Request (partial unique index).
/// - `beacon_lobby_ban`: who the author banned from the lobby. A ban is per
///   Request and person, outlives withdrawing and offering again, and ends
///   only when the author lifts it (or the Request / account is deleted).
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
  'People the Request author banned from the Request lobby (U088).'
''',
]);
