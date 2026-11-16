part of '_migrations.dart';

/// Baton «together» storage (`docs/plans/baton-together-plan.md` §2.3): a
/// candidate may name a partner (`partner_*`), and a taken baton may record a
/// `co_taker_id`. Both user references are ON DELETE SET NULL so erasure keeps
/// the answer and is not blocked on an archived Post (they are left out of the
/// m0271 guard column lists for the same reason). Realtime fan-out widens to
/// the partners; the guard lists gain the partner answer columns.
final m0316 = Migration('0316', [
  '''
ALTER TABLE public.beacon_room_baton_candidate
  ADD COLUMN partner_user_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  ADD COLUMN partner_response smallint NULL,
  ADD COLUMN partner_responded_at timestamptz NULL,
  ADD COLUMN partner_invites smallint NOT NULL DEFAULT 0,
  ADD CONSTRAINT baton_candidate_partner_not_self
    CHECK (partner_user_id IS DISTINCT FROM user_id),
  ADD CONSTRAINT baton_candidate_partner_response_range
    CHECK (partner_response IS NULL OR partner_response IN (0, 1, 2)),
  ADD CONSTRAINT baton_candidate_partner_invites_range
    CHECK (partner_invites BETWEEN 0 AND 3),
  ADD CONSTRAINT baton_candidate_partner_state
    CHECK (
      partner_response IS NULL
      OR (partner_response IN (0, 1) AND response = 1)
      OR (partner_response = 2 AND response = 0)
    )
''',
  '''
CREATE INDEX beacon_room_baton_candidate_partner
  ON public.beacon_room_baton_candidate(partner_user_id)
  WHERE partner_user_id IS NOT NULL
''',
  '''
CREATE UNIQUE INDEX beacon_room_baton_candidate_one_accepted_partner
  ON public.beacon_room_baton_candidate(baton_id, partner_user_id)
  WHERE partner_user_id IS NOT NULL AND partner_response = 1
''',
  '''
ALTER TABLE public.beacon_room_baton
  ADD COLUMN co_taker_id text NULL REFERENCES public."user"(id) ON DELETE SET NULL,
  ADD CONSTRAINT baton_co_taker_only_when_taken
    CHECK (co_taker_id IS NULL OR (status = 1 AND co_taker_id IS DISTINCT FROM taker_id))
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_room_baton_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  user_ids text[];
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.co_taker_id IS NOT DISTINCT FROM OLD.co_taker_id THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT u), ARRAY[]::text[])
  INTO user_ids
  FROM (
    SELECT NEW.author_id AS u
    UNION ALL SELECT c.user_id FROM public.beacon_room_baton_candidate c
      WHERE c.baton_id = NEW.id
    UNION ALL SELECT c.partner_user_id FROM public.beacon_room_baton_candidate c
      WHERE c.baton_id = NEW.id AND c.partner_user_id IS NOT NULL
  ) s;

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
  'DROP TRIGGER room_baton_notify ON public.beacon_room_baton',
  '''
CREATE TRIGGER room_baton_notify
  AFTER INSERT OR UPDATE OF status, co_taker_id ON public.beacon_room_baton
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_room_baton_change()
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_room_baton_candidate_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  baton_author_id text;
  baton_beacon_id text;
BEGIN
  IF NEW.response IS NOT DISTINCT FROM OLD.response
     AND NEW.partner_user_id IS NOT DISTINCT FROM OLD.partner_user_id
     AND NEW.partner_response IS NOT DISTINCT FROM OLD.partner_response THEN
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
    (SELECT array_agg(DISTINCT u) FROM unnest(ARRAY[
      baton_author_id, NEW.user_id, NEW.partner_user_id, OLD.partner_user_id
    ]) AS u WHERE u IS NOT NULL)
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
  'DROP TRIGGER room_baton_candidate_notify ON public.beacon_room_baton_candidate',
  '''
CREATE TRIGGER room_baton_candidate_notify
  AFTER UPDATE OF response, partner_user_id, partner_response
  ON public.beacon_room_baton_candidate
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_room_baton_candidate_change()
''',
  'DROP TRIGGER beacon_post_write_guard ON public.beacon_room_baton_candidate',
  '''
CREATE TRIGGER beacon_post_write_guard
  BEFORE INSERT OR UPDATE OF baton_id, user_id, tier, response, responded_at,
    partner_response, partner_responded_at, partner_invites
  ON public.beacon_room_baton_candidate
  FOR EACH ROW EXECUTE FUNCTION public.beacon_post_related_write_guard()
''',
]);
