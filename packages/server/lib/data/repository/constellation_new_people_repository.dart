import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/port/constellation_new_people_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: ConstellationNewPeopleRepositoryPort)
final class ConstellationNewPeopleRepository
    implements ConstellationNewPeopleRepositoryPort {
  ConstellationNewPeopleRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> recordFirstSeen({
    required String viewerId,
    required List<String> peerIds,
    required bool backfill,
  }) async {
    if (peerIds.isEmpty) return;
    await _database.withMutatingSystem(
      () => _database.customUpdate(
        r'''
INSERT INTO public.person_field_first_seen (viewer_id, peer_id, first_seen_at)
SELECT $1, p, CASE WHEN $3::boolean THEN '-infinity'::timestamptz
                     ELSE now() END
FROM unnest($2::text[]) AS p
ON CONFLICT DO NOTHING
''',
        variables: [
          Variable.withString(viewerId),
          Variable(TypedValue(Type.textArray, peerIds)),
          Variable.withBool(backfill),
        ],
      ),
    );
  }

  @override
  Future<void> acknowledge({
    required String viewerId,
    required List<String> peerIds,
  }) async {
    if (peerIds.isEmpty) return;
    await _database.withMutatingUser(viewerId, () async {
      await _database.customUpdate(
        r'''
UPDATE public.person_field_first_seen
SET acknowledged_at = now()
WHERE viewer_id = $1 AND peer_id = ANY($2::text[])
  AND acknowledged_at IS NULL
''',
        variables: [
          Variable.withString(viewerId),
          Variable(TypedValue(Type.textArray, peerIds)),
        ],
      );
    });
  }
}
