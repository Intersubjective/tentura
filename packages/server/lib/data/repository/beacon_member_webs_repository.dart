import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/beacon_member_webs_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(
  as: BeaconMemberWebsRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class BeaconMemberWebsRepository
    implements BeaconMemberWebsRepositoryPort {
  const BeaconMemberWebsRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<ConstellationMemberWebRecord>> memberWebs({
    required String beaconId,
    required String viewerId,
    required String context,
    required bool includeForwarded,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT m.person_id, bool_or(m.is_inside) AS is_inside
FROM (
  SELECT b.user_id AS person_id, true AS is_inside
  FROM public.beacon b
  WHERE b.id = $1
  UNION ALL
  SELECT bp.user_id, true
  FROM public.beacon_participant bp
  WHERE bp.beacon_id = $1 AND bp.room_access = 3
  UNION ALL
  SELECT e.recipient_id, false
  FROM public.beacon_forward_edge e
  WHERE $4 AND e.beacon_id = $1 AND e.cancelled_at IS NULL
) m
WHERE m.person_id <> $2
  AND EXISTS (
    SELECT 1 FROM public.person_visible_peers_symmetric($2, $3) s
    WHERE s.peer_id::text = m.person_id
      AND NOT public.block_hides($2, m.person_id)
      AND NOT public.block_hides(m.person_id, $2)
  )
GROUP BY m.person_id
ORDER BY m.person_id
''',
          variables: [
            Variable.withString(beaconId),
            Variable.withString(viewerId),
            Variable.withString(context),
            Variable.withBool(includeForwarded),
          ],
        )
        .get();
    return [
      for (final row in rows)
        ConstellationMemberWebRecord(
          beaconId: beaconId,
          personId: row.read<String>('person_id'),
          state: row.read<bool>('is_inside')
              ? ConstellationMemberWebState.inside
              : ConstellationMemberWebState.forwarded,
        ),
    ];
  }
}
