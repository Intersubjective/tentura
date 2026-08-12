part of '_migrations.dart';

/// Derived capability evidence tables, context normalization, and MR epoch
/// singleton (unit A2).
final m0142 = Migration('0142', [
  '''
CREATE TABLE public.capability_evidence_edge (
  observer_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  subject_user_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug         text NOT NULL,
  s_out            double precision NOT NULL DEFAULT 0,
  s_seed           double precision NOT NULL DEFAULT 0,
  anchor_at        timestamptz NOT NULL DEFAULT now(),
  built_from_gen   bigint NOT NULL DEFAULT 0,
  next_expiry_at   timestamptz NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (observer_user_id, subject_user_id, tag_slug),
  CONSTRAINT cee_no_self CHECK (observer_user_id <> subject_user_id)
);
''',
  '''
CREATE INDEX cee_projection_idx ON public.capability_evidence_edge (subject_user_id, tag_slug)
  INCLUDE (observer_user_id, s_out, s_seed, anchor_at);
''',
  '''
CREATE INDEX cee_expiry_idx ON public.capability_evidence_edge (next_expiry_at)
  WHERE next_expiry_at IS NOT NULL;
''',
  '''
CREATE TABLE public.capability_evidence_generation (
  observer_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  subject_user_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug text NOT NULL,
  generation bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (observer_user_id, subject_user_id, tag_slug));
''',
  '''
CREATE TABLE public.ego_witness_window (
  ego_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  context text NOT NULL,
  witness_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  m double precision NOT NULL,
  admitted boolean NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  mr_epoch bigint NOT NULL,
  PRIMARY KEY (ego_user_id, context, witness_user_id));
''',
  '''
CREATE INDEX eww_gc_idx ON public.ego_witness_window (computed_at);
''',
  '''
CREATE TABLE public.capability_routing_mute (
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, tag_slug));
''',
  '''
CREATE TABLE public.mr_publish_epoch (
  id boolean PRIMARY KEY DEFAULT true CHECK (id), epoch bigint NOT NULL DEFAULT 0);
''',
  '''
INSERT INTO public.mr_publish_epoch DEFAULT VALUES;
''',
  r'''
CREATE OR REPLACE FUNCTION public.cap_normalize_context(_c text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN _c IS NULL THEN ''
    WHEN length(btrim(_c)) < 3 OR length(btrim(_c)) > 32 THEN ''
    ELSE btrim(_c)
  END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.mutually_visible_users(
  context text,
  hasura_session json
) RETURNS SETOF public."user"
  LANGUAGE sql
  STABLE
  AS $$
SELECT u.*
FROM public."user" u
INNER JOIN public.person_visibility_peers(
  hasura_session ->> 'x-hasura-user-id',
  public.cap_normalize_context(context)
) p ON u.id = p.peer_id
WHERE nullif(trim(hasura_session ->> 'x-hasura-user-id'), '') IS NOT NULL
  AND u.id <> (hasura_session ->> 'x-hasura-user-id')
  AND p.is_mutually_visible
  AND NOT public.block_hides(
    hasura_session ->> 'x-hasura-user-id',
    u.id
  );
$$;
''',
]);
