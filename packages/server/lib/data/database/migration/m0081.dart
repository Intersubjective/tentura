part of '_migrations.dart';

/// Browser session store for app-host HttpOnly cookie auth (TMB / BFF).
///
/// Ensures [account_credential] exists before the session FK: version `0080` was
/// once a beacon_activity_event backfill; DBs that applied that row skip [m0080]
/// and would otherwise fail here with 42P01.
final m0081 = Migration('0081', [
  r'''
CREATE TABLE IF NOT EXISTS public.account_credential (
  id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  type text NOT NULL,
  identifier text NOT NULL,
  public_data jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
''',
  r'''
CREATE UNIQUE INDEX IF NOT EXISTS account_credential__type_identifier
  ON public.account_credential (type, identifier);
''',
  r'''
CREATE INDEX IF NOT EXISTS account_credential__account_id
  ON public.account_credential (account_id);
''',
  r'''
INSERT INTO public.account_credential (id, account_id, type, identifier)
SELECT 'C' || substr(md5(random()::text || u.id), 1, 12),
       u.id,
       'ed25519_device',
       u.public_key
FROM public."user" u
ON CONFLICT (type, identifier) DO NOTHING;
''',
  r'''
CREATE TABLE IF NOT EXISTS public.account_session (
  id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  token_hash text NOT NULL,
  credential_id text REFERENCES public.account_credential(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz
);
''',
  r'''
CREATE UNIQUE INDEX IF NOT EXISTS account_session__token_hash
  ON public.account_session (token_hash);
''',
  r'''
CREATE INDEX IF NOT EXISTS account_session__account_id
  ON public.account_session (account_id);
''',
]);
