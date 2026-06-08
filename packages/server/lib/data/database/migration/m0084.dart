part of '_migrations.dart';

/// Settings email-linking: a magic-link transaction may target an existing
/// account (link mode) instead of resolve-or-create (login mode). When
/// `link_account_id` is set, `verify` strict-links `email_otp` to that account
/// and mints no session.
final m0084 = Migration('0084', [
  r'''
ALTER TABLE public.email_auth_transaction
  ADD COLUMN link_account_id text;
''',
]);
