part of '_migrations.dart';

/// Ordered discoverable Request candidates for both lifecycle filters (#235 U42).
/// Keeps the shipped m0193 author-only index unchanged for baseline comparison.
final m0233 = Migration('0233', [
  '''
CREATE INDEX beacon_discoverable_user_id_id_idx ON public.beacon USING btree (user_id, id)
WHERE kind = 0
  AND is_discoverable
  AND published_at IS NOT NULL
  AND status IN (0, 4, 5, 6, 7, 8)
''',
]);
