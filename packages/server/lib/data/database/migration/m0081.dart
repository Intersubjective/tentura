part of '_migrations.dart';

/// Browser session store for app-host HttpOnly cookie auth (TMB / BFF).
final m0081 = Migration('0081', [
  r'''
CREATE TABLE public.account_session (
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
CREATE UNIQUE INDEX account_session__token_hash
  ON public.account_session (token_hash);
''',
  r'''
CREATE INDEX account_session__account_id
  ON public.account_session (account_id);
''',
]);
