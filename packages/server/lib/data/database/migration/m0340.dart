part of '_migrations.dart';

/// Private avatar references and transactional cleanup of retired object keys.
final m0340 = Migration('0340', [
  '''
CREATE TABLE public.person_private_avatar (
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  subject_user_id text REFERENCES public."user" (id) ON DELETE CASCADE,
  subject_phantom_id text REFERENCES public.phantom (id) ON DELETE CASCADE,
  object_key text NOT NULL,
  blurhash text NOT NULL,
  width integer NOT NULL CHECK (width > 0),
  height integer NOT NULL CHECK (height > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (num_nonnulls(subject_user_id, subject_phantom_id) = 1),
  CHECK (owner_id <> subject_user_id),
  UNIQUE NULLS NOT DISTINCT (owner_id, subject_user_id, subject_phantom_id)
)
''',
  for (final subject in const ['subject_user_id', 'subject_phantom_id'])
    '''
CREATE INDEX person_private_avatar_${subject}_idx
ON public.person_private_avatar ($subject) WHERE $subject IS NOT NULL
''',
  '''
CREATE INDEX person_private_avatar_object_key_idx
ON public.person_private_avatar (object_key)
''',
  '''
CREATE TRIGGER assert_owner_scope
BEFORE INSERT OR UPDATE ON public.person_private_avatar
FOR EACH ROW EXECUTE FUNCTION public.assert_owner_scope('owner_id')
''',
  '''
CREATE TABLE public.private_object_gc (
  object_key text PRIMARY KEY,
  enqueued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  attempts integer NOT NULL DEFAULT 0,
  lease_owner text,
  lease_until timestamptz,
  next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_error text
)
''',
  '''
CREATE INDEX private_object_gc_claim_idx
ON public.private_object_gc (next_attempt_at, enqueued_at, object_key)
WHERE attempts < 10
''',
  // Serialize an enqueue with the collector discarding a still-referenced key.
  r'''
CREATE FUNCTION public.lock_private_object_gc_key(p_object_key text)
RETURNS void LANGUAGE sql AS $$
  SELECT pg_advisory_xact_lock(
    hashtextextended('private_object_gc:' || p_object_key, 4242)
  )
$$
''',
  r'''
CREATE FUNCTION public.enqueue_retired_private_avatar() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.object_key = OLD.object_key THEN
    RETURN NEW;
  END IF;

  PERFORM public.lock_private_object_gc_key(OLD.object_key);
  INSERT INTO public.private_object_gc (object_key) VALUES (OLD.object_key)
  ON CONFLICT (object_key) DO NOTHING;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER enqueue_retired_private_avatar
BEFORE DELETE OR UPDATE OF object_key ON public.person_private_avatar
FOR EACH ROW EXECUTE FUNCTION public.enqueue_retired_private_avatar()
''',
]);
