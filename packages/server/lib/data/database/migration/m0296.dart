part of '_migrations.dart';

/// Gratitude evolves in place while acceptance occurrences remain immutable.
/// The partial key makes concurrent writes obey the same collapse identity.
final m0296 = Migration('0296', [
  '''
CREATE UNIQUE INDEX notification_outbox_forward_helped_identity
ON public.notification_outbox (beacon_id, account_id)
WHERE presentation_key = 'forward_helped'
''',
]);
