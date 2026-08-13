part of '_migrations.dart';

/// Per-user request-receptiveness storage (availability v1).
final m0148 = Migration('0148', [
  r'''
CREATE TABLE public.user_availability (
  user_id     text PRIMARY KEY REFERENCES public."user"(id) ON DELETE CASCADE,
  is_limited  boolean     NOT NULL DEFAULT false,
  resume_on   date        NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_availability_not_empty
    CHECK (is_limited OR resume_on IS NOT NULL)
);
''',
  r'''
CREATE INDEX user_availability_resume_on_idx
  ON public.user_availability (resume_on) WHERE resume_on IS NOT NULL;
''',
  r'''
CREATE OR REPLACE FUNCTION public.user_availability_hidden_for_viewer(
  user_availability_row public.user_availability,
  hasura_session json
) RETURNS boolean
  LANGUAGE sql
  STABLE
  AS $$
  SELECT public.block_hides(
    hasura_session ->> 'x-hasura-user-id',
    user_availability_row.user_id
  );
$$;
''',
]);
