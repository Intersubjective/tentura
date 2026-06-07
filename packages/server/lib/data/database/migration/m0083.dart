part of '_migrations.dart';

/// Verified contacts for cross-credential identity unification.
///
/// Pre-deploy audit (manual): detect emails that may already exist on multiple
/// accounts before enabling global `(kind, value)` uniqueness, e.g. compare
/// `account_credential` rows where `type = 'email_otp'` against any exported
/// Google signup logs for the same inbox.
final m0083 = Migration('0083', [
  r'''
CREATE TABLE public.account_verified_contact (
  id text PRIMARY KEY,
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  kind text NOT NULL,
  value text NOT NULL,
  last_source text NOT NULL,
  verified_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT account_verified_contact__kind_check
    CHECK (kind IN ('email', 'phone')),
  CONSTRAINT account_verified_contact__value_nonempty
    CHECK (char_length(value) > 0)
);
''',
  r'''
CREATE UNIQUE INDEX account_verified_contact__kind_value
  ON public.account_verified_contact (kind, value);
''',
  r'''
CREATE INDEX account_verified_contact__account_id
  ON public.account_verified_contact (account_id);
''',
  r'''
INSERT INTO public.account_verified_contact (
  id,
  account_id,
  kind,
  value,
  last_source,
  verified_at,
  created_at
)
SELECT
  'V' || substr(md5(random()::text || ac.id), 1, 12),
  ac.account_id,
  'email',
  ac.identifier,
  'email_otp',
  ac.created_at,
  ac.created_at
FROM public.account_credential ac
WHERE ac.type = 'email_otp'
ON CONFLICT DO NOTHING;
''',
]);
