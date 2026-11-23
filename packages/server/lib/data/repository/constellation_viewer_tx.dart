import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

import '../database/postgres_advisory_lock.dart';
import '../database/tentura_db.dart' hide ConstellationAnchor;

/// Serializes this viewer's batches (lock-first order). Waiting means the
/// previous holder committed after this transaction's snapshot, so the
/// cursor lock would fail with 40001 after a wasted preparation: fail now.
Future<void> lockConstellationViewerBatch(
  TenturaDb db,
  String viewerId,
) => lockAdvisoryScopeForSnapshot(db, 'constellation_anchor_apply:$viewerId');

Future<
  ({
    ConstellationAnchorWatermark watermark,
    ConstellationAnchorRevision resetRevision,
  })
>
lockConstellationViewerCursor(TenturaDb db, String viewerId) async {
  Future<QueryRow?> lock() => db
      .customSelect(
        r'''
SELECT revision, reset_revision
FROM public.constellation_anchor_cursor
WHERE viewer_id = $1
FOR UPDATE
''',
        variables: [Variable<String>(viewerId)],
      )
      .getSingleOrNull();
  // The cursor row exists after the viewer's first write; create it once.
  var row = await lock();
  if (row == null) {
    await _ensureViewerCursor(db, viewerId);
    row = await lock();
  }
  return (
    watermark: ConstellationAnchorWatermark(
      ConstellationAnchorRevision(row!.read<BigInt>('revision')),
    ),
    resetRevision: ConstellationAnchorRevision(
      row.read<BigInt>('reset_revision'),
    ),
  );
}

Future<void> _ensureViewerCursor(TenturaDb db, String viewerId) async {
  await db.customStatement(
    r'''
INSERT INTO public.constellation_anchor_cursor (viewer_id)
VALUES ($1)
ON CONFLICT (viewer_id) DO NOTHING
''',
    [viewerId],
  );
}
