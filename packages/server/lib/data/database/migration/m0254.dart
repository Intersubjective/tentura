part of '_migrations.dart';

/// «Сбросить позиции» (#251, D5): the viewer's reset watermark.
///
/// A reset deletes every anchor of the viewer (all target kinds, hidden and
/// tombstoned ones too) and stamps the cursor revision it advanced to here.
/// An anchor write whose `baseRevision` (the anchor revision the client had
/// seen when the user made it) is below this watermark predates the reset and
/// is rejected, so a delayed or replayed placement cannot restore a position
/// the reset removed. Safe to replay.
final m0254 = Migration('0254', [
  '''
ALTER TABLE public.constellation_anchor_cursor
  ADD COLUMN IF NOT EXISTS reset_revision bigint DEFAULT 0 NOT NULL
''',
]);
