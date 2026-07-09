part of '_migrations.dart';

/// Append-only log for author/steward help-offer admission decisions.
final m0113 = Migration('0113', [
  r'''
CREATE TABLE public.beacon_help_offer_admission_event (
  id text PRIMARY KEY,
  seq bigserial NOT NULL,
  beacon_id text NOT NULL,
  offer_user_id text NOT NULL,
  actor_user_id text NOT NULL REFERENCES public."user"(id),
  action smallint NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beacon_help_offer_admission_event_offer_fk
    FOREIGN KEY (beacon_id, offer_user_id)
    REFERENCES public.beacon_help_offer (beacon_id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT beacon_help_offer_admission_event_action_check
    CHECK (action BETWEEN 0 AND 3),
  CONSTRAINT beacon_help_offer_admission_event_reason_check
    CHECK (
      (action IN (0, 1) AND reason IS NULL) OR
      (action IN (2, 3) AND reason IS NOT NULL AND length(trim(reason)) BETWEEN 1 AND 500)
    )
);
''',
  r'''
COMMENT ON TABLE public.beacon_help_offer_admission_event IS
  'Append-only log of admit/decline/remove decisions for a help offer. action: 0=auto_admit,1=accept,2=decline,3=remove. reason is required for decline/remove, null for accept/auto_admit.';
''',
  r'''
CREATE UNIQUE INDEX beacon_help_offer_admission_event_offer_idx
  ON public.beacon_help_offer_admission_event (beacon_id, offer_user_id, seq DESC);
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_help_offer_admission_event_change()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  entity_id    text;
  offer_uid    text;
  user_ids     text[];
  suppress_uid text;
BEGIN
  entity_id := COALESCE(NEW.beacon_id, OLD.beacon_id);
  offer_uid := COALESCE(NEW.offer_user_id, OLD.offer_user_id);
  user_ids  := ARRAY[offer_uid];

  BEGIN
    user_ids := user_ids || COALESCE((
      SELECT ARRAY[b.user_id]
      FROM public.beacon b
      WHERE b.id = entity_id
    ), ARRAY[]::text[]);
  EXCEPTION
    WHEN no_data_found THEN
      NULL;
    WHEN OTHERS THEN
      RAISE WARNING 'notify_help_offer_admission_event_change: beacon author lookup failed for %: %',
        entity_id, SQLERRM;
  END;

  suppress_uid := current_setting('tentura.mutating_user_id', true);
  IF suppress_uid IS NOT NULL AND suppress_uid <> '' THEN
    user_ids := array_remove(user_ids, suppress_uid);
  END IF;

  user_ids := (
    SELECT coalesce(array_agg(DISTINCT uid), ARRAY[]::text[])
    FROM unnest(user_ids) AS uid
    WHERE uid IS NOT NULL AND uid <> ''
  );

  IF array_length(user_ids, 1) IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  PERFORM pg_notify(
    'entity_changes',
    json_build_object(
      'entity', 'help_offer',
      'id', entity_id,
      'event', lower(TG_OP),
      'user_ids', user_ids
    )::text
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;
''',
  r'''
DROP TRIGGER IF EXISTS help_offer_admission_event_notify
  ON public.beacon_help_offer_admission_event;
''',
  r'''
CREATE TRIGGER help_offer_admission_event_notify
  AFTER INSERT OR UPDATE OR DELETE ON public.beacon_help_offer_admission_event
  FOR EACH ROW EXECUTE FUNCTION public.notify_help_offer_admission_event_change();
''',
]);
