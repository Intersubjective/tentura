part of '_migrations.dart';

final m0344 = Migration('0344', [
  '''
ALTER TABLE public.account_verified_contact
  ADD COLUMN match_hmac bytea,
  ADD COLUMN hmac_key_version smallint,
  ADD CONSTRAINT account_verified_contact_match_hash_check CHECK (
    (match_hmac IS NULL AND hmac_key_version IS NULL)
    OR (
      kind = 'email' AND match_hmac IS NOT NULL AND octet_length(match_hmac) = 32
      AND hmac_key_version IS NOT NULL AND hmac_key_version > 0
    )
  )
''',
  '''
CREATE INDEX account_verified_contact_match_hmac_idx
ON public.account_verified_contact (match_hmac) WHERE match_hmac IS NOT NULL
''',
]);
