
import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../database/tentura_db.dart';

/// C2 upsert authorization for one target (mirrors
/// [ConstellationFieldSnapshotReader._loadAuthorizedAnchors] predicates).
Future<bool> isConstellationAnchorUpsertAuthorized(
  TenturaDb database, {
  required String viewerId,
  required String context,
  required ConstellationAnchorTarget target,
}) async {
  return switch (target.kind) {
    ConstellationAnchorTargetKind.person => _personAuthorized(
        database,
        viewerId: viewerId,
        context: context,
        personId: target.id,
      ),
    ConstellationAnchorTargetKind.beacon => _beaconAuthorized(
        database,
        viewerId: viewerId,
        beaconId: target.id,
      ),
  };
}

Future<bool> _personAuthorized(
  TenturaDb database, {
  required String viewerId,
  required String context,
  required String personId,
}) async {
  final row = await database
      .customSelect(
        r'''
SELECT 1 AS ok
WHERE $3::text <> $1::text
  AND EXISTS (
    SELECT 1
    WHERE $3 = ANY(public.person_visible_peer_ids_tx($1, $2))
  )
  AND NOT public.block_hides($1, $3)
  AND NOT public.block_hides($3, $1)
''',
        variables: [
          Variable<String>(viewerId),
          Variable<String>(context),
          Variable<String>(personId),
        ],
      )
      .getSingleOrNull();
  return row != null;
}

Future<bool> _beaconAuthorized(
  TenturaDb database, {
  required String viewerId,
  required String beaconId,
}) async {
  final row = await database
      .customSelect(
        '''
SELECT 1 AS ok
FROM public.beacon b
WHERE b.id = \$2
  AND ${constellationBeaconContentReadableSql(viewerParam: r'$1', beaconAlias: 'b')}
  AND ${constellationBeaconUpsertStatusSql(beaconAlias: 'b')}
''',
        variables: [
          Variable<String>(viewerId),
          Variable<String>(beaconId),
        ],
      )
      .getSingleOrNull();
  return row != null;
}
