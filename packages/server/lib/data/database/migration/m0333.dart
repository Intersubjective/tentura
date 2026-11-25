part of '_migrations.dart';

/// Private storage for people added before they join Tentura.
final m0333 = Migration('0333', [
  r'''
CREATE TABLE public.phantom (
  id text PRIMARY KEY CHECK (id ~ '^PH[0-9a-f]{12}$'),
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  display_name text NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 3 AND 32),
  emoji text CHECK (char_length(emoji) <= 8),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  merged_user_id text REFERENCES public."user" (id) ON DELETE SET NULL,
  merged_at timestamptz,
  merge_origin smallint CHECK (merge_origin BETWEEN 1 AND 3),
  current_merge_id text,
  revision bigint NOT NULL DEFAULT 0
)
''',
  '''
CREATE TABLE public.phantom_merge (
  id text PRIMARY KEY,
  phantom_id text NOT NULL REFERENCES public.phantom (id) ON DELETE CASCADE,
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  user_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  origin smallint NOT NULL CHECK (origin BETWEEN 1 AND 3),
  created_at timestamptz NOT NULL DEFAULT now(),
  undo jsonb NOT NULL,
  undone_at timestamptz
)
''',
  '''
ALTER TABLE public.phantom ADD CONSTRAINT phantom_current_merge_id_fkey
  FOREIGN KEY (current_merge_id) REFERENCES public.phantom_merge (id) ON DELETE SET NULL
''',
  // The invite transaction can queue a job without locking the phantom row.
  '''
CREATE TABLE public.phantom_merge_job (
  id text PRIMARY KEY,
  phantom_id text NOT NULL,
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  user_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  origin smallint NOT NULL CHECK (origin BETWEEN 1 AND 3),
  invitation_id text NOT NULL UNIQUE,
  state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued', 'done', 'skipped', 'failed')),
  reason text,
  attempts integer NOT NULL DEFAULT 0,
  lease_owner text,
  lease_until timestamptz,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  done_at timestamptz
)
''',
  '''
CREATE UNIQUE INDEX phantom_merge_job_one_queued_per_phantom
ON public.phantom_merge_job (phantom_id) WHERE state = 'queued'
''',
  '''
CREATE TABLE public.phantom_link_hint_dismissal (
  phantom_id text NOT NULL REFERENCES public.phantom (id) ON DELETE CASCADE,
  user_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  PRIMARY KEY (phantom_id, user_id)
)
''',
  '''
CREATE TABLE public.person_field_first_seen_init (
  viewer_id text PRIMARY KEY REFERENCES public."user" (id) ON DELETE CASCADE,
  at timestamptz NOT NULL DEFAULT now(),
  backfill_pending boolean NOT NULL
)
''',
  '''
INSERT INTO public.person_field_first_seen_init (viewer_id, backfill_pending)
SELECT DISTINCT viewer_id, false FROM public.person_field_first_seen
''',
  for (final table in const ['phantom', 'phantom_merge'])
    '''
CREATE TRIGGER assert_owner_scope
BEFORE INSERT OR UPDATE ON public.$table
FOR EACH ROW EXECUTE FUNCTION public.assert_owner_scope('owner_id')
''',
]);
