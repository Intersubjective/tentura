part of '_migrations.dart';

/// Private imported contact details and committed chunks for keyed replays.
final m0343 = Migration('0343', [
  '''
CREATE TABLE public.phantom_contact_point (
  phantom_id text NOT NULL REFERENCES public.phantom (id) ON DELETE CASCADE,
  kind text NOT NULL,
  value text,
  match_hmac bytea,
  hmac_key_version smallint,
  PRIMARY KEY (phantom_id, kind),
  CHECK (
    (kind = 'email' AND match_hmac IS NOT NULL AND octet_length(match_hmac) = 32
     AND hmac_key_version IS NOT NULL AND hmac_key_version > 0)
    OR (kind = 'phone' AND value IS NOT NULL AND match_hmac IS NULL
        AND hmac_key_version IS NULL)
  )
)
''',
  '''
CREATE INDEX phantom_contact_point_match_hmac_idx
ON public.phantom_contact_point (match_hmac) WHERE match_hmac IS NOT NULL
''',
  '''
CREATE TABLE public.phantom_import_chunk (
  owner_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  client_op_id text NOT NULL,
  chunk_index integer NOT NULL,
  created_ids text[] NOT NULL,
  PRIMARY KEY (owner_id, client_op_id, chunk_index)
)
''',
  '''
CREATE TRIGGER assert_owner_scope
BEFORE INSERT OR UPDATE ON public.phantom_import_chunk
FOR EACH ROW EXECUTE FUNCTION public.assert_owner_scope('owner_id')
''',
]);
