part of '_migrations.dart';

/// Append-only commitment participation facts + help-offer projection columns.
final m0139 = Migration('0139', [
  r'''
CREATE TABLE public.beacon_commitment_event (
  id text PRIMARY KEY,
  seq bigserial NOT NULL,
  beacon_id text NOT NULL,
  user_id text NOT NULL,
  actor_user_id text NOT NULL REFERENCES public."user"(id),
  kind smallint NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beacon_commitment_event_offer_fk
    FOREIGN KEY (beacon_id, user_id)
    REFERENCES public.beacon_help_offer (beacon_id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT beacon_commitment_event_kind_check
    CHECK (kind BETWEEN 0 AND 8),
  CONSTRAINT beacon_commitment_event_reason_check
    CHECK (reason IS NULL OR length(trim(reason)) BETWEEN 1 AND 500)
);
''',
  r'''
COMMENT ON TABLE public.beacon_commitment_event IS 'Append-only participation facts for a help
   offer. kind: 0=offered,1=acknowledged,2=acknowledgement_softened,3=withdrawn_by_helper,
   4=released_by_author,5=removed_from_chat,6=readmitted_to_chat,7=blocked_cleanup,
   8=unanswered_at_close. Rows are never updated or deleted.';
''',
  r'''
CREATE UNIQUE INDEX beacon_commitment_event_pair_idx ON public.beacon_commitment_event
   (beacon_id, user_id, seq DESC);
''',
  r'''
CREATE INDEX beacon_commitment_event_beacon_idx ON public.beacon_commitment_event (beacon_id);
''',
  r'''
ALTER TABLE public.beacon_help_offer ADD COLUMN offer_kind smallint NOT NULL DEFAULT 0;
''',
  r'''
ALTER TABLE public.beacon_help_offer ADD CONSTRAINT beacon_help_offer_offer_kind_check
   CHECK (offer_kind IN (0, 1));
''',
  r'''
COMMENT ON COLUMN public.beacon_help_offer.offer_kind IS '0=normal, 1=backup (offered while the
   request already signalled enough help)';
''',
  r'''
ALTER TABLE public.beacon_help_offer ADD COLUMN stake_state smallint NOT NULL DEFAULT 0;
''',
  r'''
ALTER TABLE public.beacon_help_offer ADD CONSTRAINT beacon_help_offer_stake_state_check
    CHECK (stake_state BETWEEN 0 AND 5);
''',
  r'''
COMMENT ON COLUMN public.beacon_help_offer.stake_state IS 'Display-only projection of
    beacon_commitment_event: 0=none,1=offered,2=acknowledged,3=softened,4=exited,5=released.
    Never an input for gates (see docs/plans/commitment-truth-rework-plan.md §2.5).';
''',
  r'''
ALTER TABLE public.beacon ADD COLUMN review_reopen_count smallint NOT NULL DEFAULT 0;
''',
  r'''
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  ho.beacon_id, ho.user_id, ho.user_id, 0, NULL, ho.created_at
FROM public.beacon_help_offer ho;
''',
  r'''
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  c.offer_beacon_id,
  c.offer_user_id,
  c.author_user_id,
  1,
  NULL,
  c.created_at
FROM public.beacon_help_offer_coordination c
JOIN public.beacon_help_offer ho
  ON ho.beacon_id = c.offer_beacon_id AND ho.user_id = c.offer_user_id
WHERE c.response_type IN (0, 3);
''',
  r'''
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  a.beacon_id,
  a.offer_user_id,
  a.actor_user_id,
  1,
  NULL,
  a.created_at
FROM public.beacon_help_offer_admission_event a
WHERE a.action IN (0, 1)
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_commitment_event e
    WHERE e.beacon_id = a.beacon_id AND e.user_id = a.offer_user_id AND e.kind = 1
  );
''',
  r'''
INSERT INTO public.beacon_commitment_event (id, beacon_id, user_id, actor_user_id, kind, reason, created_at)
SELECT
  'CE' || replace(gen_random_uuid()::text, '-', ''),
  ho.beacon_id,
  ho.user_id,
  ho.user_id,
  3,
  ho.withdraw_reason,
  ho.updated_at
FROM public.beacon_help_offer ho
WHERE ho.status = 1;
''',
  r'''
UPDATE public.beacon_help_offer ho
SET stake_state = CASE
  WHEN ho.status = 1 THEN 4                                  -- withdrawn → exited
  WHEN EXISTS (SELECT 1 FROM public.beacon_commitment_event e
               WHERE e.beacon_id = ho.beacon_id AND e.user_id = ho.user_id AND e.kind = 1)
       AND COALESCE((SELECT c.response_type FROM public.beacon_help_offer_coordination c
                     WHERE c.offer_beacon_id = ho.beacon_id AND c.offer_user_id = ho.user_id), -1)
           IN (0, 3) THEN 2                                  -- acknowledged
  WHEN EXISTS (SELECT 1 FROM public.beacon_commitment_event e
               WHERE e.beacon_id = ho.beacon_id AND e.user_id = ho.user_id AND e.kind = 1)
       THEN 3                                                -- ack был, ответ понижен → softened
  ELSE 1                                                     -- offered
END;
''',
]);
