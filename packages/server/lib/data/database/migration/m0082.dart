part of '_migrations.dart';

/// Email magic-link auth transactions (Phase 2 invite onboarding).
final m0082 = Migration('0082', [
  r'''
CREATE TABLE public.email_auth_transaction (
  id text PRIMARY KEY,
  token_hash text NOT NULL,
  normalized_email text NOT NULL,
  invite_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  user_agent_hash text NOT NULL,
  ip_hash text NOT NULL
);
''',
  r'''
CREATE UNIQUE INDEX email_auth_transaction__token_hash
  ON public.email_auth_transaction (token_hash);
''',
  r'''
CREATE INDEX email_auth_transaction__email_created
  ON public.email_auth_transaction (normalized_email, created_at);
''',
  r'''
CREATE INDEX email_auth_transaction__ip_created
  ON public.email_auth_transaction (ip_hash, created_at);
''',
  r'''
CREATE INDEX email_auth_transaction__invite_created
  ON public.email_auth_transaction (invite_code, created_at)
  WHERE invite_code IS NOT NULL;
''',
]);
