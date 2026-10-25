import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;
import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_layout_snapshot_repository_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';
import 'constellation_viewer_tx.dart';

/// History snapshots kept per viewer; older ones go in the writing transaction.
const _historyLimit = 20;

const _columns =
    'id, kind, reason, anchor_count, created_at::text AS created_at';

ConstellationLayoutSnapshot _fromRow(QueryRow row) =>
    ConstellationLayoutSnapshot(
      id: row.read<String>('id'),
      kind: ConstellationLayoutSnapshotKind.values[row.read<int>('kind')],
      reason: ConstellationLayoutSnapshotReason.values[row.read<int>('reason')],
      anchorCount: row.read<int>('anchor_count'),
      createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
    );

/// Captures the viewer's live anchors as a snapshot inside the caller's
/// transaction and trims the history to the newest [_historyLimit]; a
/// favourite replaces the previous one.
Future<ConstellationLayoutSnapshot> insertConstellationLayoutSnapshot(
  TenturaDb db, {
  required String viewerId,
  required ConstellationLayoutSnapshotKind kind,
  required ConstellationLayoutSnapshotReason reason,
  required String clientOpId,
}) async {
  if (kind == ConstellationLayoutSnapshotKind.favourite) {
    await db
        .customSelect(
          r'''
DELETE FROM public.constellation_layout_snapshot
WHERE viewer_id = $1 AND kind = 0
RETURNING 1
''',
          variables: [Variable<String>(viewerId)],
        )
        .get();
  }
  final row = await db
      .customSelect(
        '''
INSERT INTO public.constellation_layout_snapshot
  (id, viewer_id, kind, reason, anchors, anchor_count, client_op_id)
SELECT \$1, \$2, \$3::smallint, \$4::smallint,
       coalesce(
         jsonb_agg(jsonb_build_object(
           'targetKind', lower(target_kind),
           'targetId', target_id,
           'x', x_units,
           'y', y_units,
           'coordinateSpaceVersion', coordinate_space_version
         )),
         '[]'::jsonb
       ),
       count(*)::integer,
       \$5
FROM public.constellation_anchor
WHERE viewer_id = \$2 AND tombstone_at IS NULL
RETURNING $_columns
''',
        variables: [
          Variable<String>(generateId('LS')),
          Variable<String>(viewerId),
          Variable<int>(kind.index),
          Variable<int>(reason.index),
          Variable<String>(clientOpId),
        ],
      )
      .getSingle();
  if (kind == ConstellationLayoutSnapshotKind.history) {
    await db
        .customSelect(
          r'''
DELETE FROM public.constellation_layout_snapshot
WHERE viewer_id = $1 AND kind = 1 AND id NOT IN (
  SELECT id FROM public.constellation_layout_snapshot
  WHERE viewer_id = $1 AND kind = 1
  ORDER BY created_at DESC, id DESC
  LIMIT $2
)
RETURNING 1
''',
          variables: [
            Variable<String>(viewerId),
            const Variable<int>(_historyLimit),
          ],
        )
        .get();
  }
  return _fromRow(row);
}

/// `constellation_layout_snapshot` (m0265). Writes are one transaction under
/// the viewer's batch lock, idempotent by `(viewerId, clientOpId)`.
@LazySingleton(as: ConstellationLayoutSnapshotRepositoryPort)
class ConstellationLayoutSnapshotRepository
    implements ConstellationLayoutSnapshotRepositoryPort {
  const ConstellationLayoutSnapshotRepository(this._db);

  final TenturaDb _db;

  @override
  Future<List<ConstellationLayoutSnapshot>> list(String viewerId) async {
    final rows = await _db
        .customSelect(
          '''
SELECT $_columns
FROM public.constellation_layout_snapshot
WHERE viewer_id = \$1
ORDER BY kind ASC, created_at DESC, id DESC
''',
          variables: [Variable<String>(viewerId)],
        )
        .get();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<ConstellationLayoutSnapshot> save({
    required String viewerId,
    required ConstellationLayoutSnapshotKind kind,
    required ConstellationLayoutSnapshotReason reason,
    required String clientOpId,
  }) => _db.withMutatingRepeatableRead(viewerId, () async {
    await lockConstellationViewerBatch(_db, viewerId);
    final recorded = await _byOpId(viewerId, clientOpId);
    if (recorded != null) return recorded;
    return insertConstellationLayoutSnapshot(
      _db,
      viewerId: viewerId,
      kind: kind,
      reason: reason,
      clientOpId: clientOpId,
    );
  });

  @override
  Future<ConstellationLayoutSnapshot> restore({
    required String viewerId,
    required String snapshotId,
    required String clientOpId,
  }) => _db.withMutatingRepeatableRead(viewerId, () async {
    await lockConstellationViewerBatch(_db, viewerId);
    final row = await _db
        .customSelect(
          '''
SELECT $_columns, anchors::text AS anchors
FROM public.constellation_layout_snapshot
WHERE id = \$1 AND viewer_id = \$2
''',
          variables: [
            Variable<String>(snapshotId),
            Variable<String>(viewerId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw PeopleTagsException(
        peopleTagsCode: PeopleTagsExceptionCode.snapshotNotFound,
      );
    }
    final snapshot = _fromRow(row);
    final recorded = await _byOpId(viewerId, clientOpId);
    if (recorded != null &&
        recorded.reason == ConstellationLayoutSnapshotReason.restore) {
      return snapshot;
    }
    await lockConstellationViewerCursor(_db, viewerId);
    await insertConstellationLayoutSnapshot(
      _db,
      viewerId: viewerId,
      kind: ConstellationLayoutSnapshotKind.history,
      reason: ConstellationLayoutSnapshotReason.restore,
      clientOpId: clientOpId,
    );
    await _applyAnchors(
      viewerId,
      (jsonDecode(row.read<String>('anchors')) as List<dynamic>)
          .cast<Map<String, dynamic>>(),
    );
    return snapshot;
  });

  Future<ConstellationLayoutSnapshot?> _byOpId(
    String viewerId,
    String clientOpId,
  ) async {
    final row = await _db
        .customSelect(
          '''
SELECT $_columns
FROM public.constellation_layout_snapshot
WHERE viewer_id = \$1 AND client_op_id = \$2
''',
          variables: [
            Variable<String>(viewerId),
            Variable<String>(clientOpId),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Makes the live anchors equal [anchors] for targets that still exist and
  /// unpins the rest. A target that is gone keeps its stored (tombstone)
  /// position, so it is still there when the target returns.
  Future<void> _applyAnchors(
    String viewerId,
    List<Map<String, dynamic>> anchors,
  ) async {
    final kinds = [for (final a in anchors) a['targetKind']! as String];
    final ids = [for (final a in anchors) a['targetId']! as String];
    final xs = [for (final a in anchors) (a['x']! as num).toDouble()];
    final ys = [for (final a in anchors) (a['y']! as num).toDouble()];
    final spaces = [
      for (final a in anchors) (a['coordinateSpaceVersion']! as num).toInt(),
    ];
    final newIds = [for (final _ in anchors) generateId('CA')];
    Variable<Object> textArray(List<String> v) =>
        Variable(TypedValue(Type.textArray, v));

    final unpinned = await _db
        .customSelect(
          r'''
DELETE FROM public.constellation_anchor
WHERE viewer_id = $1 AND tombstone_at IS NULL
  AND (target_kind, target_id) NOT IN (
    SELECT upper(s.kind), s.id FROM unnest($2::text[], $3::text[]) AS s(kind, id)
  )
RETURNING target_kind, target_id
''',
          variables: [
            Variable<String>(viewerId),
            textArray(kinds),
            textArray(ids),
          ],
        )
        .get();
    final moved = await _db
        .customSelect(
          r'''
UPDATE public.constellation_anchor a
SET x_units = s.x, y_units = s.y, coordinate_space_version = s.cs
FROM unnest($2::text[], $3::text[], $4::double precision[],
            $5::double precision[], $6::integer[]) AS s(kind, id, x, y, cs)
WHERE a.viewer_id = $1 AND a.tombstone_at IS NULL
  AND a.target_kind = upper(s.kind) AND a.target_id = s.id
  AND (a.x_units, a.y_units, a.coordinate_space_version)
      IS DISTINCT FROM (s.x, s.y, s.cs)
RETURNING a.target_kind, a.target_id
''',
          variables: [
            Variable<String>(viewerId),
            textArray(kinds),
            textArray(ids),
            Variable(TypedValue(Type.doubleArray, xs)),
            Variable(TypedValue(Type.doubleArray, ys)),
            Variable(TypedValue(Type.integerArray, spaces)),
          ],
        )
        .get();
    final placed = await _db
        .customSelect(
          r'''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, beacon_id,
  x_units, y_units, coordinate_space_version, revision, placed_at
)
SELECT s.new_id, $1,
       CASE WHEN s.kind = 'person' THEN s.id END,
       CASE WHEN s.kind = 'beacon' THEN s.id END,
       s.x, s.y, s.cs, 0, 'epoch'::timestamptz
FROM unnest($2::text[], $3::text[], $4::double precision[],
            $5::double precision[], $6::integer[], $7::text[])
     AS s(kind, id, x, y, cs, new_id)
WHERE (
    (s.kind = 'person' AND EXISTS (
      SELECT 1 FROM public."user" u WHERE u.id = s.id))
    OR (s.kind = 'beacon' AND EXISTS (
      SELECT 1 FROM public.beacon b WHERE b.id = s.id))
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.constellation_anchor a
    WHERE a.viewer_id = $1 AND a.target_kind = upper(s.kind)
      AND a.target_id = s.id)
RETURNING target_kind, target_id
''',
          variables: [
            Variable<String>(viewerId),
            textArray(kinds),
            textArray(ids),
            Variable(TypedValue(Type.doubleArray, xs)),
            Variable(TypedValue(Type.doubleArray, ys)),
            Variable(TypedValue(Type.integerArray, spaces)),
            textArray(newIds),
          ],
        )
        .get();
    final touched = [...unpinned, ...moved, ...placed];
    if (touched.isEmpty) return;
    // A conditional write (ifRevision) based on an earlier revision of any
    // touched target conflicts from now on.
    await _db
        .customSelect(
          r'''
INSERT INTO public.constellation_anchor_target_watermark
  (viewer_id, target_kind, target_id, revision)
SELECT $1, t.kind, t.id, (
  SELECT revision FROM public.constellation_anchor_cursor WHERE viewer_id = $1
)
FROM unnest($2::text[], $3::text[]) AS t(kind, id)
ON CONFLICT (viewer_id, target_kind, target_id)
DO UPDATE SET revision = EXCLUDED.revision
RETURNING 1
''',
          variables: [
            Variable<String>(viewerId),
            textArray([for (final r in touched) r.read<String>('target_kind')]),
            textArray([for (final r in touched) r.read<String>('target_id')]),
          ],
        )
        .get();
  }
}
