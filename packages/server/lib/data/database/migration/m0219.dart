part of '_migrations.dart';

/// «Who'll take it?» (baton) storage — plan §2.1
/// (`docs/plans/baton-who-takes-it-plan.md`).
///
/// Two tables: `beacon_room_baton` (one live row per message, enforced by
/// the partial unique index) and `beacon_room_baton_candidate` (the people
/// asked, with their tier and response). Realtime fan-out mirrors the
/// `room_seen_peer` pattern (`m0196.dart`): a standalone trigger function per
/// table, both emitting entity kind `room_baton` scoped to the author and the
/// relevant candidates only — never to the whole room, which would leak that
/// a baton exists to people who were not asked.
final m0219 = Migration('0219', [
  '''
CREATE TABLE public.beacon_room_baton (
  id text PRIMARY KEY,
  message_id text NOT NULL REFERENCES public.beacon_room_message(id) ON DELETE CASCADE,
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  author_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  status smallint NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
  taker_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  selection_mode smallint NULL CHECK (selection_mode IN (1, 2)),
  all_answered_notified_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz NULL,
  CHECK (status <> 1 OR (selection_mode IS NOT NULL AND resolved_at IS NOT NULL))
);
''',

  '''
CREATE UNIQUE INDEX beacon_room_baton_live_per_message
  ON public.beacon_room_baton(message_id) WHERE status <> 2;
''',

  '''
CREATE INDEX beacon_room_baton_beacon ON public.beacon_room_baton(beacon_id);
''',

  '''
CREATE TABLE public.beacon_room_baton_candidate (
  baton_id text NOT NULL REFERENCES public.beacon_room_baton(id) ON DELETE CASCADE,
  user_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tier smallint NOT NULL DEFAULT 1 CHECK (tier BETWEEN 1 AND 3),
  response smallint NOT NULL DEFAULT 0 CHECK (response IN (0, 1, 2)),
  responded_at timestamptz NULL,
  PRIMARY KEY (baton_id, user_id)
);
''',

  '''
CREATE INDEX beacon_room_baton_candidate_user
  ON public.beacon_room_baton_candidate(user_id);
''',

  r'''
CREATE FUNCTION public.notify_room_baton_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  user_ids text[];
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NULL;
  END IF;

  SELECT ARRAY[NEW.author_id] || COALESCE(array_agg(c.user_id), ARRAY[]::text[])
  INTO user_ids
  FROM public.beacon_room_baton_candidate c
  WHERE c.baton_id = NEW.id;

  PERFORM public.emit_realtime_entity_change(
    'room_baton',
    NEW.beacon_id,
    'update',
    user_ids
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_room_baton_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$
''',

  '''
CREATE TRIGGER room_baton_notify
  AFTER INSERT OR UPDATE OF status ON public.beacon_room_baton
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_room_baton_change();
''',

  r'''
CREATE FUNCTION public.notify_room_baton_candidate_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  baton_author_id text;
  baton_beacon_id text;
BEGIN
  IF NEW.response IS NOT DISTINCT FROM OLD.response THEN
    RETURN NULL;
  END IF;

  SELECT b.author_id, b.beacon_id INTO baton_author_id, baton_beacon_id
  FROM public.beacon_room_baton b
  WHERE b.id = NEW.baton_id;

  IF baton_author_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM public.emit_realtime_entity_change(
    'room_baton',
    baton_beacon_id,
    'update',
    ARRAY[baton_author_id, NEW.user_id]
  );
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_room_baton_candidate_change failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$
''',

  '''
CREATE TRIGGER room_baton_candidate_notify
  AFTER UPDATE OF response ON public.beacon_room_baton_candidate
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_room_baton_candidate_change();
''',
]);
