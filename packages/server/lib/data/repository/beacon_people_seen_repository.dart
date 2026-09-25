import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/beacon_people_seen_repository_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: BeaconPeopleSeenRepositoryPort)
class BeaconPeopleSeenRepository implements BeaconPeopleSeenRepositoryPort {
  const BeaconPeopleSeenRepository(this._db);

  final TenturaDb _db;

  @override
  Future<DateTime> markSeen({
    required String userId,
    required String beaconId,
    required DateTime at,
  }) => _db.withMutatingUser(userId, () async {
    final row = await _db
        .customSelect(
          r'''
INSERT INTO beacon_people_seen (user_id, beacon_id, last_seen_at)
VALUES ($1, $2, $3::timestamptz)
ON CONFLICT (user_id, beacon_id)
DO UPDATE SET last_seen_at = GREATEST(
  beacon_people_seen.last_seen_at, EXCLUDED.last_seen_at
)
RETURNING last_seen_at
''',
          variables: [
            Variable<String>(userId),
            Variable<String>(beaconId),
            Variable<String>(at.toUtc().toIso8601String()),
          ],
        )
        .getSingle();
    return DateTime.parse(row.read<String>('last_seen_at')).toUtc();
  });

  @override
  Future<Map<String, DateTime>> lastSeenByUserIds({
    required String beaconId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          r'''
SELECT user_id, last_seen_at
FROM beacon_people_seen
WHERE beacon_id = $1 AND user_id = ANY($2::text[])
''',
          variables: [
            Variable<String>(beaconId),
            Variable<List<String>>(userIds, PgTypes.textArray),
          ],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('user_id'): DateTime.parse(
          r.read<String>('last_seen_at'),
        ).toUtc(),
    };
  }
}
