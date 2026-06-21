part of '_migrations.dart';

/// Phase 1 multi-credential model: `account_credential` (one account, many
/// credentials). Backfills one `ed25519_device` credential per existing user
/// from `user.public_key`. `user.public_key` is kept (dual-written) so the
/// change is reversible and avoids Hasura/GraphQL ripple.
final m0080 = Migration('0080', [
  '''
CREATE TABLE public.account_credential (
  id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  type text NOT NULL,
  identifier text NOT NULL,
  public_data jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
''',
  '''
CREATE UNIQUE INDEX account_credential__type_identifier
  ON public.account_credential (type, identifier);
''',
  '''
CREATE INDEX account_credential__account_id
  ON public.account_credential (account_id);
''',
  // Backfill: one ed25519_device credential per existing user. Idempotent via
  // the unique (type, identifier) index. `id` is internal-only — any
  // collision-free text PK works ('C' + 12 hex, matching utils/id.dart).
  '''
INSERT INTO public.account_credential (id, account_id, type, identifier)
SELECT 'C' || substr(md5(random()::text || u.id), 1, 12),
       u.id,
       'ed25519_device',
       u.public_key
FROM public."user" u
ON CONFLICT (type, identifier) DO NOTHING;
''',
]);
