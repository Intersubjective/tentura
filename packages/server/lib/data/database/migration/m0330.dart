part of '_migrations.dart';

/// Allow a Request to carry an expiry used when consuming its signup invite.
/// The existing expiry requirement for open Posts still applies.
final m0330 = Migration('0330', [
  '''
ALTER TABLE public.beacon
  DROP CONSTRAINT beacon_post_expires_at_ck,
  ADD CONSTRAINT beacon_post_expires_at_ck
    CHECK (kind <> 1 OR status <> 0 OR expires_at IS NOT NULL)
''',
]);
