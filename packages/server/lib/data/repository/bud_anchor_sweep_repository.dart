import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/domain/port/bud_anchor_sweep_port.dart';

import '../database/tentura_db.dart' hide ConstellationAnchor;

/// Raw SQL over `beacon_child_commands` (m0239 `bud_result`,
/// `anchor_inherited_at`) and `constellation_anchor` for the anchor
/// inheritance sweep (plan C8). Reads run outside any transaction.
@LazySingleton(as: BudAnchorSweepPort)
class BudAnchorSweepRepository implements BudAnchorSweepPort {
  const BudAnchorSweepRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<PendingBudAnchor>> pendingBuds({required int limit}) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT c.actor_user_id, c.client_command_id, child.id AS child_id,
       post.id AS post_id
FROM public.beacon_child_commands c
LEFT JOIN public.beacon child ON child.id = c.result_beacon_id
LEFT JOIN public.beacon post
  ON post.id = child.parent_beacon_id AND post.kind = 1
WHERE c.bud_result IS NOT NULL
  AND c.result_state = 0
  AND c.anchor_inherited_at IS NULL
ORDER BY c.created_at, c.actor_user_id, c.client_command_id
LIMIT $1
''',
          variables: [Variable.withInt(limit)],
        )
        .get();
    return [
      for (final r in rows)
        PendingBudAnchor(
          actorUserId: r.read<String>('actor_user_id'),
          clientCommandId: r.read<String>('client_command_id'),
          childBeaconId: r.readNullable<String>('child_id'),
          postId: r.readNullable<String>('post_id'),
        ),
    ];
  }

  @override
  Future<List<String>> inheritingViewerIds({
    required String childBeaconId,
    required String postId,
  }) async {
    final readable = constellationBeaconContentReadableSql(
      viewerParam: 'a.viewer_id',
      beaconAlias: 'child',
    );
    final status = constellationBeaconUpsertStatusSql(beaconAlias: 'child');
    final rows = await _database
        .customSelect(
          '''
SELECT a.viewer_id
FROM public.constellation_anchor a
JOIN public.beacon child ON child.id = \$1
WHERE a.beacon_id = \$2
  AND a.tombstone_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.constellation_anchor own
    WHERE own.viewer_id = a.viewer_id AND own.beacon_id = \$1
  )
  AND $status
  AND $readable
ORDER BY a.viewer_id
''',
          variables: [
            Variable.withString(childBeaconId),
            Variable.withString(postId),
          ],
        )
        .get();
    return [for (final r in rows) r.read<String>('viewer_id')];
  }

  @override
  Future<BudPostPlacement?> postPlacement({
    required String viewerId,
    required String postId,
  }) async {
    final row = await _database
        .customSelect(
          r'''
SELECT a.x_units, a.y_units, a.coordinate_space_version,
       (post.status = 6) AS post_closed
FROM public.constellation_anchor a
JOIN public.beacon post ON post.id = a.beacon_id
WHERE a.viewer_id = $1 AND a.beacon_id = $2 AND a.tombstone_at IS NULL
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(postId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return BudPostPlacement(
      position: ConstellationAnchorPosition(
        xUnits: row.read<double>('x_units'),
        yUnits: row.read<double>('y_units'),
        coordinateSpaceVersion: row.read<int>('coordinate_space_version'),
      ),
      postClosed: row.read<bool>('post_closed'),
    );
  }

  @override
  Future<void> markInherited({
    required String actorUserId,
    required String clientCommandId,
  }) => _database.withMutatingSystem(
    () => _database.customUpdate(
      r'''
UPDATE public.beacon_child_commands
SET anchor_inherited_at = now()
WHERE actor_user_id = $1 AND client_command_id = $2
  AND anchor_inherited_at IS NULL
''',
      variables: [
        Variable.withString(actorUserId),
        Variable.withString(clientCommandId),
      ],
    ),
    kind: MainDbWorkKind.full,
  );
}
