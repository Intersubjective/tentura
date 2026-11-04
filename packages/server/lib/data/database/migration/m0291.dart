part of '_migrations.dart';

/// Activity-ordered Field candidates can stop at the readability batch limit
/// without filtering and sorting every discoverable Request first.
final m0291 = Migration('0291', [
  '''
CREATE INDEX beacon_discoverable_activity_id_idx ON public.beacon (
  (COALESCE(last_activity_at, published_at, created_at)) DESC, id ASC
)
WHERE kind = 0
  AND is_discoverable
  AND published_at IS NOT NULL
  AND status IN (0, 4, 5, 6, 7, 8)
''',
]);
