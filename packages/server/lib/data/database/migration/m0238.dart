part of '_migrations.dart';

/// A published promotion may outlive its source message (post→Request
/// budding A1, Arch §10.3).
///
/// `beacon_promotions.source_message_id` is `ON DELETE SET NULL`, but the
/// check `(source_message_id IS NOT NULL) OR (published_at IS NULL)` made
/// deleting the source of a published child fail. Drop it: the child keeps
/// its parent, and the consistency trigger still validates non-null sources.
/// A draft whose source is gone is still rejected by `publishDraft`.
final m0238 = Migration('0238', [
  '''
ALTER TABLE public.beacon_promotions
  DROP CONSTRAINT IF EXISTS beacon_promotions_source_general_ck
''',
]);
