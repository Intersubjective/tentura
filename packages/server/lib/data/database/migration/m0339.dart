part of '_migrations.dart';

/// Owner-only notes are stored with their original subject even after linking.
final m0339 = Migration('0339', [
  '''
CREATE TABLE public.person_note (
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  subject_user_id text REFERENCES public."user" (id) ON DELETE CASCADE,
  subject_phantom_id text REFERENCES public.phantom (id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(body) <= 4000),
  updated_at timestamptz NOT NULL DEFAULT now(),
  revision bigint NOT NULL DEFAULT 0,
  CHECK (num_nonnulls(subject_user_id, subject_phantom_id) = 1),
  CHECK (owner_id <> subject_user_id),
  UNIQUE NULLS NOT DISTINCT (owner_id, subject_user_id, subject_phantom_id)
)
''',
  for (final subject in const ['subject_user_id', 'subject_phantom_id'])
    '''
CREATE INDEX person_note_${subject}_idx ON public.person_note ($subject)
WHERE $subject IS NOT NULL
''',
  '''
CREATE TRIGGER assert_owner_scope
BEFORE INSERT OR UPDATE ON public.person_note
FOR EACH ROW EXECUTE FUNCTION public.assert_owner_scope('owner_id')
''',
]);
